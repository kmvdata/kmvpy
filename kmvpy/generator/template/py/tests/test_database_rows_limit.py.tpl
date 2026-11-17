# coding: utf-8
"""行数上限（LIMIT 结果窗口）的数据库无关单元测试。

运行方式（在 __PY_PROJECT_NAME__ 下）：

    PYTHONPATH=. python -m unittest discover -s tests -p "test_database_rows_limit.py"

本模块不连接数据库：只验证 Hub 的上限收敛、响应组装与 Infra 的窗口换算。
真正落到数据库的读取由 ``test_database_rows_postgres.py`` 覆盖，环境不可用时
在那里整体 skip，不把环境问题伪装成失败。
"""

import unittest

from kmvpy.common.exception.kmv_exception import KmvException

from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.database.rows import page_limit
from __PROJECT_NAME__.core.main.hub.database.table_rows import DatabaseTableRowsHub


class RowLimitNormalizationTest(unittest.TestCase):
    """默认值与上限边界。"""

    def test_default_and_max_are_accepted(self) -> None:
        self.assertEqual(
            DatabaseTableRowsHub.normalized_row_limit(
                DatabaseTableRowsHub.DEFAULT_ROW_LIMIT
            ),
            DatabaseTableRowsHub.DEFAULT_ROW_LIMIT,
        )
        self.assertEqual(
            DatabaseTableRowsHub.normalized_row_limit(
                DatabaseTableRowsHub.MAX_ROW_LIMIT
            ),
            DatabaseTableRowsHub.MAX_ROW_LIMIT,
        )

    def test_default_is_one_hundred(self) -> None:
        self.assertEqual(DatabaseTableRowsHub.DEFAULT_ROW_LIMIT, 100)
        self.assertEqual(DatabaseTableRowsHub.MAX_ROW_LIMIT, 10000)

    def test_over_max_is_rejected(self) -> None:
        """超过上限必须拒绝，不能静默收敛成 10000。"""
        with self.assertRaises(KmvException):
            DatabaseTableRowsHub.normalized_row_limit(
                DatabaseTableRowsHub.MAX_ROW_LIMIT + 1
            )

    def test_rejection_uses_dedicated_error_code(self) -> None:
        self.assertEqual(
            database_table_exc.DATABASE_TABLE_ROW_LIMIT_EXCEEDED_ERROR[0], 46014
        )

    def test_non_positive_is_clamped_to_one(self) -> None:
        self.assertEqual(DatabaseTableRowsHub.normalized_row_limit(0), 1)
        self.assertEqual(DatabaseTableRowsHub.normalized_row_limit(-5), 1)


class PageLimitWindowTest(unittest.TestCase):
    """LIMIT 窗口与 offset 的换算。"""

    def test_no_window_keeps_full_page(self) -> None:
        self.assertEqual(page_limit(50, 0, None), 50)
        self.assertEqual(page_limit(50, 500, None), 50)

    def test_window_cuts_page_after_limit(self) -> None:
        self.assertEqual(page_limit(50, 0, 100), 50)
        self.assertEqual(page_limit(50, 50, 100), 50)
        self.assertEqual(page_limit(50, 100, 100), 0)
        self.assertEqual(page_limit(50, 150, 100), 0)

    def test_partial_page_inside_window(self) -> None:
        self.assertEqual(page_limit(50, 50, 60), 10)
        self.assertEqual(page_limit(200, 0, 100), 100)
        self.assertEqual(page_limit(20, 0, 1), 1)


class BuildResultLimitTest(unittest.TestCase):
    """响应组装：total 收敛与截断标记。"""

    @staticmethod
    def _raw(total: int | None) -> dict[str, object]:
        return {
            "table_name": "user_base",
            "columns": [
                {
                    "name": "id",
                    "type": "BIGINT",
                    "nullable": False,
                    "primary_key": True,
                }
            ],
            "rows": [],
            "primary_key_columns": ["id"],
            "total": total,
            "elapsed_ms": 3,
        }

    def test_total_is_capped_by_row_limit(self) -> None:
        data = DatabaseTableRowsHub.build_result(
            self._raw(5000), page=1, size=50, row_limit=100
        )
        self.assertEqual(data["total"], 100)
        self.assertTrue(data["total_truncated"])
        self.assertEqual(data["row_limit"], 100)

    def test_total_below_limit_is_not_truncated(self) -> None:
        data = DatabaseTableRowsHub.build_result(
            self._raw(40), page=1, size=50, row_limit=100
        )
        self.assertEqual(data["total"], 40)
        self.assertFalse(data["total_truncated"])

    def test_total_equal_to_limit_is_not_truncated(self) -> None:
        data = DatabaseTableRowsHub.build_result(
            self._raw(100), page=1, size=50, row_limit=100
        )
        self.assertEqual(data["total"], 100)
        self.assertFalse(data["total_truncated"])

    def test_unknown_total_stays_none(self) -> None:
        data = DatabaseTableRowsHub.build_result(
            self._raw(None), page=2, size=50, row_limit=100
        )
        self.assertIsNone(data["total"])
        self.assertFalse(data["total_truncated"])


if __name__ == "__main__":
    unittest.main()
