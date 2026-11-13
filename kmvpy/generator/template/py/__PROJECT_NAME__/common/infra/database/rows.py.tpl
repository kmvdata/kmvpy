# coding: utf-8
"""在既有数据库连接上只读分页读取表数据。

只接受调用方已经持有的 ``AsyncEngine``（配置声明的默认连接），不接受库名、
连接字符串或任何 SQL 文本，因此无法借此切换到配置文件之外的数据库，也无法
执行任何写语句。

- 只用 ``engine.connect()``，不进入 ``engine.begin()``；
- 列与排序目标都取自反射得到的 ``Table`` 对象，不拼接字符串 SQL；
- 总行数只在第一页读取，失败时降级为 ``None``，不阻塞当前页数据读取。

条件与排序分两条路径：

- ``where_node`` / ``order_terms`` 是 :mod:`__PROJECT_NAME__.common.infra.database.query_lang`
  解析出的 AST。它们会被映射成 SQLAlchemy 表达式，字面量全部走绑定参数，列对象
  只取自反射得到的 ``Table``，因此不存在字符串拼接的 SQL。
- 兼容旧契约的单列 ``order_by`` + ``order_desc``；列名必须命中反射列，由
  ``DatabaseTableRowsHub.resolve_order_column`` 转成 46012 业务错误。

条件里出现反射列之外的列时抛 ``query_lang.UnknownColumnError``，由 Service 转成
对应业务错误码后返回，绝不降级成“忽略该条件后继续查询”。
"""

from __future__ import annotations

from datetime import date, datetime, time
from decimal import Decimal
from time import perf_counter
from typing import Any

from sqlalchemy import (
    MetaData,
    Table,
    asc,
    desc,
    func,
    inspect as sa_inspect,
    select,
    text,
)
from sqlalchemy.ext.asyncio import AsyncEngine

from __PROJECT_NAME__.common.infra.database.query_lang import (
    OrderTerm,
    WhereNode,
    build_order_by,
    build_where,
)
from __PROJECT_NAME__.common.infra.orm import _savepoint_call

# 单元格文本上限：超出即截断并标记，避免把整段长文本塞进列表响应。
MAX_CELL_TEXT_LENGTH = 512

# 单条只读查询的语句超时（毫秒）：只在 PostgreSQL 上生效。
# 管理端允许手写条件，因此必须给可能退化成全表扫描的条件一个上限，
# 避免单次请求长期占用连接池。其它方言没有等价的事务级设置，按注释说明跳过。
STATEMENT_TIMEOUT_MS = 3000


def normalize_cell(value: Any) -> dict[str, Any]:
    """把数据库返回值归一化成可传输的单元格结构，不做任何业务判断。"""
    if value is None:
        return {"kind": "null", "text": None, "truncated": False, "byte_length": None}
    if isinstance(value, (bytes, bytearray, memoryview)):
        return {
            "kind": "binary",
            "text": None,
            "truncated": False,
            "byte_length": len(bytes(value)),
        }
    # bool 是 int 的子类，必须先判断，否则会退化成 number。
    if isinstance(value, bool):
        return {
            "kind": "bool",
            "text": "true" if value else "false",
            "truncated": False,
            "byte_length": None,
        }
    if isinstance(value, (int, float, Decimal)):
        return {
            "kind": "number",
            "text": str(value),
            "truncated": False,
            "byte_length": None,
        }
    if isinstance(value, (datetime, date, time)):
        return {
            "kind": "datetime",
            "text": value.isoformat(),
            "truncated": False,
            "byte_length": None,
        }
    text = str(value)
    return {
        "kind": "text",
        "text": text[:MAX_CELL_TEXT_LENGTH],
        "truncated": len(text) > MAX_CELL_TEXT_LENGTH,
        "byte_length": None,
    }


def _apply_statement_timeout(sync_conn: Any) -> None:
    """为当前事务设置语句超时（PostgreSQL）。

    这里必须把常量直接写进语句：PostgreSQL 的 ``SET`` 是工具语句，不接受绑定参数。
    写入的是本模块内的整型常量（经 ``int()`` 归一），不接受任何外部输入。
    使用保存点包裹，保证设置失败不会把整个事务留在 aborted 状态。
    """
    if sync_conn.dialect.name != "postgresql":
        return
    timeout_ms = int(STATEMENT_TIMEOUT_MS)
    _savepoint_call(
        sync_conn,
        "设置只读查询语句超时",
        lambda: sync_conn.execute(
            text(f"SET LOCAL statement_timeout = {timeout_ms}")
        ),
        None,
    )


def _count_rows(sync_conn: Any, table: Table, where_expr: Any) -> int | None:
    """统计总行数；条件与分页一致，失败降级为 None。

    总数必须带上与列表相同的过滤条件，否则分页尾页与“共 N 行”会与实际结果不符。
    """
    statement = select(func.count()).select_from(table)
    if where_expr is not None:
        statement = statement.where(where_expr)
    return _savepoint_call(
        sync_conn,
        f"读取表 {table.name} 总行数",
        lambda: int(sync_conn.execute(statement).scalar_one()),
        None,
    )


def _read_rows_sync(
    sync_conn: Any,
    table_name: str,
    page: int,
    size: int,
    order_by: str | None,
    order_desc: bool,
    where_node: WhereNode | None,
    order_terms: tuple[OrderTerm, ...] | None,
) -> dict[str, Any]:
    inspector = sa_inspect(sync_conn)
    if not inspector.has_table(table_name):
        return {
            "table_name": table_name,
            "exists": False,
            "columns": [],
            "rows": [],
            "primary_key_columns": [],
            "total": None,
        }

    table = Table(table_name, MetaData(), autoload_with=sync_conn)
    pk_constraint = inspector.get_pk_constraint(table_name) or {}
    primary_key_columns = [
        str(name) for name in pk_constraint.get("constrained_columns") or [] if name
    ]
    pk_columns = set(primary_key_columns)
    columns = [
        {
            "name": str(column.name),
            "type": str(column.type),
            "nullable": bool(column.nullable),
            "primary_key": str(column.name) in pk_columns,
        }
        for column in table.columns
    ]

    # 列对象来自反射结果：条件、排序与投影都不接受外部传入的 SQL 片段。
    # where_node / order_terms 已在 Hub 通过文法白名单，这里只做列名解析与表达式映射，
    # 未知名会抛 UnknownColumnError 而不是被忽略。
    where_expr = build_where(table.c, where_node) if where_node is not None else None

    _apply_statement_timeout(sync_conn)

    statement = select(table)
    if where_expr is not None:
        statement = statement.where(where_expr)
    if order_terms:
        statement = statement.order_by(*build_order_by(table.c, order_terms))
    else:
        order_column = (order_by or "").strip()
        if order_column and order_column in table.c:
            target = table.c[order_column]
            statement = statement.order_by(
                desc(target) if order_desc else asc(target)
            )
    statement = statement.limit(size).offset((page - 1) * size)

    rows = [
        [normalize_cell(value) for value in row]
        for row in sync_conn.execute(statement).all()
    ]
    total = _count_rows(sync_conn, table, where_expr) if page == 1 else None
    return {
        "table_name": table_name,
        "exists": True,
        "columns": columns,
        "rows": rows,
        "primary_key_columns": primary_key_columns,
        "total": total,
    }


async def read_table_rows(
    engine: AsyncEngine,
    table_name: str,
    *,
    page: int,
    size: int,
    order_by: str | None = None,
    order_desc: bool = False,
    where_node: WhereNode | None = None,
    order_terms: tuple[OrderTerm, ...] | None = None,
) -> dict[str, Any]:
    """只读读取指定表的一页数据；表不存在时返回 ``exists: False``。

    ``where_node`` / ``order_terms`` 来自受限查询语言解析结果；为 ``None`` 时退化成
    无条件、单列排序（与旧契约一致）。
    """
    started = perf_counter()
    async with engine.connect() as conn:
        raw = await conn.run_sync(
            _read_rows_sync,
            table_name,
            page,
            size,
            order_by,
            order_desc,
            where_node,
            order_terms,
        )
    raw["elapsed_ms"] = max(int((perf_counter() - started) * 1000), 0)
    return raw
