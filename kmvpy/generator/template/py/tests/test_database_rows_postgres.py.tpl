# coding: utf-8
"""对配置声明的数据库执行只读验证。

运行方式（在 __PY_PROJECT_NAME__ 下）：

    python -m unittest discover -s tests -p "test_database_rows_postgres.py"

设计约束：

- 只读：只执行 SELECT 语义的读取，不执行任何 DDL/DML。
- 不接触凭据文本：连接地址由应用自身的配置加载入口
  ``AppConfig.load_config()`` 提供；测试代码不解析 config.yaml、不打印 URL。
- 数据库不可达或配置缺失时整体 skip，不把环境问题伪装成失败。
- 只报告异常类型，不回显连接串、账号或密码。
"""

import functools
import os
import unittest

from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from __PROJECT_NAME__.common.conf import AppConfig
from __PROJECT_NAME__.common.infra.database import query_lang
from __PROJECT_NAME__.common.infra.database.rows import read_table_rows

# 页面默认打开的数据表（管理员操作审计日志）。
TABLE_NAME = "admin_operation_log"

# 与 app/run.py 一致的默认配置位置。
DEFAULT_CONFIG_PATH = os.path.join("app", "etc", "develop", "config.yaml")

# 探活语句：只读常量，不包含任何外部输入。
PROBE_SQL = "SELECT 1"


def configured_path() -> str:
    """返回应用配置路径：优先环境变量，其次 develop 默认路径。"""
    return os.getenv("__CONFIG_ENV_VAR__") or DEFAULT_CONFIG_PATH


@functools.lru_cache(maxsize=1)
def load_config_once(path: str) -> AppConfig:
    """按应用自身入口加载配置；只读取一次，避免重复解析密钥文件。"""
    return AppConfig.load_config(path)


class QueryLanguageRejectionTest(unittest.TestCase):
    """注入与越权输入必须在解析阶段被拒绝，不需要数据库。"""

    def test_statement_and_comment_rejected(self) -> None:
        for payload in (
            "id = 1; DROP TABLE admin_operation_log",
            "id = 1 --",
            "id = 1 /* comment */",
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(query_lang.QueryLanguageError):
                    query_lang.parse_where(payload)

    def test_subquery_and_union_rejected(self) -> None:
        for payload in (
            "id IN (SELECT id FROM user_base)",
            "id = 1 UNION SELECT id FROM user_base",
            "EXISTS (SELECT 1)",
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(query_lang.QueryLanguageError):
                    query_lang.parse_where(payload)

    def test_always_true_prefix_rejected(self) -> None:
        """没有列名开头的布尔常量不是合法谓词。"""
        for payload in ("1=1 OR 1=1", "TRUE", "'a' = 'a'"):
            with self.subTest(payload=payload):
                with self.assertRaises(query_lang.QueryLanguageError):
                    query_lang.parse_where(payload)

    def test_order_by_snippet_rejected(self) -> None:
        for payload in (
            "id; DROP TABLE admin_operation_log",
            "id DESC, (SELECT 1)",
            "1",
        ):
            with self.subTest(payload=payload):
                with self.assertRaises(query_lang.QueryLanguageError):
                    query_lang.parse_order_by(payload)


class DatabaseRowsReadOnlyTest(unittest.IsolatedAsyncioTestCase):
    """只读验证表数据浏览链路：分页、WHERE、ORDER BY 与列白名单。"""

    engine = None

    async def asyncSetUp(self) -> None:
        path = configured_path()
        if not os.path.exists(path):
            self.skipTest(f"未找到应用配置文件: {path}")
        config = load_config_once(os.path.abspath(path))
        database_config = config.get_default_storage_database_config()
        if database_config is None:
            self.skipTest("配置未声明 default_storage.database")
        self.engine = create_async_engine(database_config.url, pool_pre_ping=True)
        try:
            async with self.engine.connect() as connection:
                await connection.execute(text(PROBE_SQL))
        except Exception as exc:  # noqa: BLE001
            await self.engine.dispose()
            self.engine = None
            # 只报告异常类型，不回显连接串或凭据。
            self.skipTest(f"数据库不可达，跳过只读集成验证: {type(exc).__name__}")

    async def asyncTearDown(self) -> None:
        if self.engine is not None:
            await self.engine.dispose()
            self.engine = None

    async def _read(self, **kwargs):
        """统一的只读读取入口，表名固定为管理端默认浏览表。"""
        return await read_table_rows(self.engine, TABLE_NAME, **kwargs)

    # -- 基础读取 --

    async def test_first_page_shape(self) -> None:
        raw = await self._read(page=1, size=5, order_by="id", order_desc=False)
        if not raw["exists"]:
            self.skipTest(f"当前库不存在表 {TABLE_NAME}")
        column_names = [str(column["name"]) for column in raw["columns"]]
        self.assertTrue(column_names)
        self.assertLessEqual(len(raw["rows"]), 5)
        self.assertIsInstance(raw["total"], int)
        self.assertIn("id", column_names)
        self.assertIn("id", raw["primary_key_columns"])

    async def test_second_page_has_no_total(self) -> None:
        raw = await self._read(page=2, size=5)
        if not raw["exists"]:
            self.skipTest(f"当前库不存在表 {TABLE_NAME}")
        self.assertIsNone(raw["total"])

    async def test_missing_table_reports_absent(self) -> None:
        raw = await read_table_rows(
            self.engine, "no_such_table_for_rows_probe", page=1, size=1
        )
        self.assertFalse(raw["exists"])
        self.assertEqual(raw["rows"], [])

    # -- WHERE --

    async def test_where_filter_never_increases_total(self) -> None:
        baseline = await self._read(page=1, size=1)
        if not baseline["exists"]:
            self.skipTest(f"当前库不存在表 {TABLE_NAME}")
        if baseline["total"] is None:
            self.skipTest("无条件统计不可用，无法比较过滤效果")
        node = query_lang.parse_where("method = 'POST'")
        filtered = await self._read(page=1, size=1, where_node=node)
        self.assertIsNotNone(filtered["total"])
        self.assertLessEqual(filtered["total"], baseline["total"])

    async def test_where_rejects_unknown_column(self) -> None:
        node = query_lang.parse_where("no_such_column = 1")
        with self.assertRaises(query_lang.UnknownColumnError):
            await self._read(page=1, size=1, where_node=node)

    # -- ORDER BY --

    async def test_order_by_desc_first_row_is_largest_id(self) -> None:
        terms = query_lang.parse_order_by("id DESC")
        ordered = await self._read(page=1, size=2, order_terms=terms)
        if not ordered["exists"] or len(ordered["rows"]) < 2:
            self.skipTest("数据不足以验证排序")
        first = int(ordered["rows"][0][0]["text"])
        second = int(ordered["rows"][1][0]["text"])
        self.assertGreater(first, second)

    async def test_order_by_rejects_unknown_column(self) -> None:
        terms = query_lang.parse_order_by("no_such_column ASC")
        with self.assertRaises(query_lang.UnknownColumnError):
            await self._read(page=1, size=1, order_terms=terms)

    # -- 字面量与列类型 --

    async def test_numeric_column_accepts_number_literal(self) -> None:
        node = query_lang.parse_where("duration_ms > 0")
        raw = await self._read(page=1, size=2, where_node=node)
        if not raw["exists"]:
            self.skipTest(f"当前库不存在表 {TABLE_NAME}")
        self.assertIsInstance(raw["total"], int)

    async def test_datetime_column_accepts_iso_string(self) -> None:
        """时间列应能用 ISO 字符串过滤：按时间排查日志是页面最高频操作。"""
        node = query_lang.parse_where("create_time > '2020-01-01 00:00:00'")
        raw = await self._read(page=1, size=2, where_node=node)
        if not raw["exists"]:
            self.skipTest(f"当前库不存在表 {TABLE_NAME}")
        self.assertIsInstance(raw["total"], int)


if __name__ == "__main__":
    unittest.main()
