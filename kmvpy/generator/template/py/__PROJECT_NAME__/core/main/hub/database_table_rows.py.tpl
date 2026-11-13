# coding: utf-8
"""数据表行数据浏览的业务规则。

全部 ``@staticmethod`` / ``@classmethod``：不接收 session、不接收 DTO、不 import
FastAPI / Router / Service，也不自行开启连接或事务。真正的只读查询在
``common/infra/database/rows.py``，本层负责分页收敛、条件与排序文本的解析
（受限查询语言）、列白名单校验、表存在性判定、错误语义归一与响应结构组装。

**安全边界**：本层把外部输入的 WHERE / ORDER BY 文本交给
``query_lang`` 解析成 AST，解析失败或引用未知列一律失败，绝不把原文拼进 SQL，
也不会在失败时“忽略条件后继续查询”。
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.database import query_lang


class DatabaseTableRowsHub:
    """表数据浏览的规则入口。"""

    # 单页上限：与 DTO 的 ``le=200`` 一致，这里只做防御性收敛。
    MAX_PAGE_SIZE = 200

    # 页码上限：与 DTO 的 ``le=MAX_PAGE`` 一致，这里再收敛一次。
    # 每页是 OFFSET 分页，页码无界就等于允许调用方要求数据库扫描任意深的行。
    MAX_PAGE = 100000

    # 表名只允许普通标识符：与 DTO 的 ``max_length=128`` 呼应，并额外拒绝
    # ``schema.table``、引号标识符、空白与 ``%`` 等异常形态。
    MAX_TABLE_NAME_LENGTH = 128
    TABLE_NAME_PATTERN = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")

    @classmethod
    def validated_table_name(cls, table_name: str) -> str:
        """校验表名形态；不合法一律按“表不存在”（46002）失败。

        反射与查询都通过 SQLAlchemy 引用标识符，本身不存在字符串拼接 SQL；
        这里仍显式拒绝异常形态，避免把带引号、``schema.`` 前缀或通配符的输入
        送进反射路径，同时让非法输入的错误语义保持稳定。
        """
        name = (table_name or "").strip()
        if (
            not name
            or len(name) > cls.MAX_TABLE_NAME_LENGTH
            or cls.TABLE_NAME_PATTERN.fullmatch(name) is None
        ):
            logger.warning("管理端表名不合法 table=%r", table_name)
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_NOT_FOUND_ERROR
            )
        return name

    @classmethod
    def normalized_page(cls, page: int, size: int) -> tuple[int, int]:
        """把分页参数收敛到安全范围；DTO 已校验，合法请求不会被改动。"""
        safe_page = min(page, cls.MAX_PAGE) if page >= 1 else 1
        safe_size = min(size, cls.MAX_PAGE_SIZE) if size >= 1 else 1
        return safe_page, safe_size

    @staticmethod
    def normalized_clause(text: str | None) -> str | None:
        """归一条件文本：去空白，空串与纯空白都视为未提供。"""
        clause = (text or "").strip()
        return clause or None

    @classmethod
    def parse_where(cls, text: str | None) -> query_lang.WhereNode | None:
        """把 WHERE 文本解析成 AST；语法错误统一转成 46013。

        解析在访问数据库之前完成，非法条件不会产生任何查询。
        """
        clause = cls.normalized_clause(text)
        if clause is None:
            return None
        try:
            return query_lang.parse_where(clause)
        except query_lang.QueryLanguageError as exc:
            logger.warning("管理端 WHERE 条件被拒绝: %s", exc)
            raise KmvException(
                error=database_table_exc.QUERY_CLAUSE_SYNTAX_INVALID_ERROR
            ) from exc

    @classmethod
    def parse_order_by_terms(
        cls, text: str | None
    ) -> tuple[query_lang.OrderTerm, ...] | None:
        """把 ORDER BY 文本解析成排序列清单；语法错误统一转成 46013。"""
        clause = cls.normalized_clause(text)
        if clause is None:
            return None
        try:
            return query_lang.parse_order_by(clause)
        except query_lang.QueryLanguageError as exc:
            logger.warning("管理端 ORDER BY 条件被拒绝: %s", exc)
            raise KmvException(
                error=database_table_exc.QUERY_CLAUSE_SYNTAX_INVALID_ERROR
            ) from exc

    @staticmethod
    def ensure_clause_columns(
        column_names: Sequence[str],
        order_terms: tuple[query_lang.OrderTerm, ...] | None,
    ) -> None:
        """排序目标必须取自反射列名单，未知列直接失败（46012）。

        WHERE 里的列在 AST → 表达式映射阶段由 ``UnknownColumnError`` 拦截，
        这里先把可静态判定的 ORDER BY 列做完，避免发出必然失败的查询。
        """
        allowed = set(column_names)
        for term in order_terms or ():
            if term.column not in allowed:
                logger.warning("管理端 ORDER BY 引用了未知列: %s", term.column)
                raise KmvException(
                    error=database_table_exc.DATABASE_TABLE_COLUMN_UNKNOWN_ERROR
                )

    @staticmethod
    def resolve_order_column(
        column_names: Sequence[str],
        order_by: str | None,
    ) -> str | None:
        """校验排序列是否在当前表列名单内；不在名单内直接失败。

        排序目标必须取自反射列名单，绝不把外部字符串原样拼进查询。
        """
        target = (order_by or "").strip()
        if not target:
            return None
        if target not in column_names:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_COLUMN_UNKNOWN_ERROR
            )
        return target

    @staticmethod
    def ensure_table_exists(raw: Mapping[str, Any]) -> None:
        """表不存在时转成明确业务错误，避免空结构被误读成空表。"""
        if raw.get("exists") is False:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_NOT_FOUND_ERROR
            )

    @staticmethod
    def column_names(raw: Mapping[str, Any]) -> list[str]:
        """从 Infra 返回的列元数据中提取列名清单。"""
        return [
            str(column.get("name") or "")
            for column in raw.get("columns") or ()
            if isinstance(column, dict) and column.get("name")
        ]

    @staticmethod
    def build_result(
        raw: Mapping[str, Any],
        *,
        page: int,
        size: int,
    ) -> dict[str, Any]:
        """把 Infra 的原始结构整理成响应字段；不含任何 IO。"""
        total = raw.get("total")
        return {
            "table_name": str(raw.get("table_name") or ""),
            "columns": [
                dict(column)
                for column in raw.get("columns") or ()
                if isinstance(column, dict)
            ],
            "rows": [
                list(row) for row in raw.get("rows") or () if isinstance(row, list)
            ],
            "primary_key_columns": [
                str(name) for name in raw.get("primary_key_columns") or () if name
            ],
            "total": total if isinstance(total, int) else None,
            "page": page,
            "size": size,
            "elapsed_ms": int(raw.get("elapsed_ms") or 0),
        }
