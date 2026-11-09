# coding: utf-8
"""把结构计划渲染成 SQL，并在单个事务内严格串行地执行。

**为什么 DDL 事务下沉在 Infra**：建表、改列、搬数据、切表名属于技术资源
生命周期，与 ``KOrmStorage`` 的引擎能力绑定；Hub 只负责业务规则与计划，
不创建事务。这是刻意设计，不是越层。

约定：

- 列与索引片段一律用 SQLAlchemy 构造器 + ``compile(dialect=...)`` 编译，
  不手拼类型字符串；
- 标识符、类型参数、默认值在进入本模块前已被 ``schema_spec`` 收窄，
  本模块只做渲染，不做业务判断；
- MySQL 等不支持原子 DDL 的方言仍会渲染完整 SQL，但只用于人工执行。
"""

from __future__ import annotations

import re
from collections.abc import Mapping, Sequence
from typing import Any

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger
from sqlalchemy import (
    Boolean,
    BigInteger,
    Column,
    DateTime,
    Integer,
    MetaData,
    Numeric,
    SmallInteger,
    String,
    Table,
    Text,
    func,
    inspect as sa_inspect,
    select,
    text,
)
from sqlalchemy.ext.asyncio import AsyncEngine
from sqlalchemy.schema import CreateColumn

from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.orm import schema_spec
from __PROJECT_NAME__.common.infra.orm import AUTO_INCREMENT_PK_TYPE, BIGINT_TYPE

# 语句类别；供 UI 分组与手动方案分区。
CATEGORY_BACKUP = "backup"
CATEGORY_CREATE_TABLE = "create_table"
CATEGORY_ALTER_TABLE = "alter_table"
CATEGORY_MIGRATE_DATA = "migrate_data"
CATEGORY_RENAME_TABLE = "rename_table"
CATEGORY_CREATE_INDEX = "create_index"
CATEGORY_DROP_INDEX = "drop_index"

_MAX_IDENTIFIER_LENGTH = 63
_NEW_TABLE_SUFFIX = "__new"

# PostgreSQL 的 ``pg_get_expr`` 会把默认值渲染成带类型转换的表达式。
_CAST_SUFFIX_RE = re.compile(
    r"::\s*[a-zA-Z_][a-zA-Z0-9_ ]*(?:\(\s*\d+(?:\s*,\s*\d+)?\s*\))?$"
)


def _unsupported() -> KmvException:
    return KmvException(error=database_table_exc.SCHEMA_MANUAL_REQUIRED_ERROR)


# ---------------------------------------------------------------------------
# 类型映射
# ---------------------------------------------------------------------------


def _type_from_database(sa_type: Any) -> tuple[str, list[int] | None] | None:
    """把反射得到的 SQLAlchemy 类型映射回白名单枚举。"""
    if isinstance(sa_type, Boolean):
        return "boolean", None
    if isinstance(sa_type, SmallInteger):
        return "smallint", None
    if isinstance(sa_type, BigInteger):
        return "bigint", None
    if isinstance(sa_type, Integer):
        return "int", None
    if isinstance(sa_type, Numeric):
        precision = getattr(sa_type, "precision", None)
        scale = getattr(sa_type, "scale", None)
        if precision is None:
            return "numeric", None
        return "numeric", [int(precision), int(scale or 0)]
    if isinstance(sa_type, DateTime):
        return "datetime", None
    if isinstance(sa_type, Text):
        return "text", None
    if isinstance(sa_type, String):
        length = getattr(sa_type, "length", None)
        return "varchar", [int(length)] if length else None
    return None


def _type_object(column: Mapping[str, Any], dialect: str) -> Any:
    """由目标列定义还原 SQLAlchemy 类型对象。"""
    column_type = str(column.get("type") or "")
    args = list(column.get("type_args") or [])
    if column_type == "int":
        return Integer()
    if column_type == "bigint":
        return BIGINT_TYPE
    if column_type == "smallint":
        return SmallInteger()
    if column_type == "varchar":
        return String(int(args[0])) if args else String()
    if column_type == "text":
        return Text()
    if column_type == "datetime":
        return DateTime()
    if column_type == "boolean":
        return Boolean()
    if column_type == "numeric":
        if len(args) == 2:
            return Numeric(int(args[0]), int(args[1]))
        return Numeric()
    raise _unsupported()


def _primary_key_type(_dialect: str) -> Any:
    """自增主键沿用项目共享类型，保证 SQLite 得到 INTEGER PRIMARY KEY。"""
    return AUTO_INCREMENT_PK_TYPE


def _render_type(column: Mapping[str, Any], dialect: str) -> str:
    type_object = _type_object(column, dialect)
    return str(type_object.compile(dialect=_dialect_object(dialect)))


def _dialect_object(dialect: str) -> Any:
    """返回渲染用的方言实例；只用于让 SQLAlchemy 生成正确字面量。"""
    from sqlalchemy.dialects import mysql, postgresql, sqlite

    name = (dialect or "").strip().lower()
    if name == "postgresql":
        return postgresql.dialect()
    if name == "sqlite":
        return sqlite.dialect()
    if name == "mysql":
        return mysql.dialect()
    return postgresql.dialect()


def _default_sql(default: str | None) -> str | None:
    """把归一化默认值渲染成 SQL 片段。"""
    kind = schema_spec.default_kind(default)
    if kind == "none" or default is None:
        return None
    if kind in ("keyword", "boolean"):
        return default
    # 数字与字符串字面量统一加单引号：数据库会按目标列类型转换，
    # 而对 varchar 列必须加引号才是合法 SQL。
    return "'" + default + "'"


def _build_column(column: Mapping[str, Any], dialect: str) -> Column:
    """构造用于渲染的列对象；唯一约束与索引由索引清单统一表达。"""
    primary_key = bool(column.get("primary_key"))
    autoincrement = bool(column.get("autoincrement"))
    if primary_key and autoincrement:
        type_object = _primary_key_type(dialect)
    else:
        type_object = _type_object(column, dialect)

    default_sql = _default_sql(column.get("server_default"))
    return Column(
        str(column.get("name")),
        type_object,
        nullable=bool(column.get("nullable")),
        primary_key=primary_key,
        autoincrement=autoincrement,
        server_default=text(default_sql) if default_sql else None,
        unique=False,
        comment=column.get("comment") or None,
    )


def _render_column_definition(column: Mapping[str, Any], dialect: str) -> str:
    column_object = _build_column(column, dialect)
    return str(CreateColumn(column_object).compile(dialect=_dialect_object(dialect)))


def _render_change_type(
    table_name: str,
    column: Mapping[str, Any],
    dialect: str,
) -> str:
    """渲染列类型变更语句。

    只有 PostgreSQL 与 MySQL 会用到该语句：SQLite 的任何结构变更都走重建
    路径。MySQL 不认识 ``ALTER COLUMN ... TYPE``，按其 ``MODIFY COLUMN``
    语法渲染——MySQL 的计划只作为手动 SQL 交付，不在本模块执行。
    """
    name = str(column.get("name"))
    if dialect == "mysql":
        definition = _render_column_definition(column, dialect)
        return f"ALTER TABLE {table_name} MODIFY COLUMN {definition}"
    return (
        f"ALTER TABLE {table_name} ALTER COLUMN {name}"
        f" TYPE {_render_type(column, dialect)}"
    )


# ---------------------------------------------------------------------------
# 语句收集
# ---------------------------------------------------------------------------


class _Statements:
    """按顺序收集语句，自动编号。"""

    def __init__(self) -> None:
        self._items: list[dict[str, Any]] = []

    def add(
        self,
        sql: str,
        category: str,
        *,
        destructive: bool = False,
        inline: bool = False,
    ) -> None:
        statement = sql.strip()
        if not statement:
            return
        self._items.append({
            "sql": statement,
            "category": category,
            "destructive": bool(destructive),
            "statement_index": len(self._items),
            # inline 表示该语句只用于手动方案的预检查分区，不是变更。
            "_precheck": inline,
        })

    def extend(self, other: "_Statements") -> None:
        for item in other._items:
            self.add(
                item["sql"],
                item["category"],
                destructive=item["destructive"],
                inline=item["_precheck"],
            )

    def items(self) -> list[dict[str, Any]]:
        return list(self._items)


def _quote_index_name(table_name: str, columns: Sequence[str]) -> str:
    """为未命名的索引生成稳定名称。

    PostgreSQL 允许 ``CREATE INDEX ON t (c)`` 省略名字，SQLite 不允许；
    统一生成确定性名称，双端 SQL 都可直接执行。
    """
    joined = "_".join(str(name) for name in columns)
    candidate = f"ix_{table_name}_{joined}"
    return candidate[:_MAX_IDENTIFIER_LENGTH]


def _statement_index_name(
    table_name: str,
    index: Mapping[str, Any],
) -> str:
    raw_name = index.get("name")
    if raw_name:
        return str(raw_name)
    return _quote_index_name(table_name, [str(name) for name in index.get("columns") or ()])


def _create_index_sql(
    table_name: str,
    index: Mapping[str, Any],
) -> str:
    name = _statement_index_name(table_name, index)
    unique = "UNIQUE " if index.get("unique") else ""
    columns = ", ".join(str(column) for column in index.get("columns") or ())
    return f"CREATE {unique}INDEX {name} ON {table_name} ({columns})"


def _drop_index_sql(index_name: str) -> str:
    return f"DROP INDEX {index_name}"


def _backup_sql(table_name: str, backup_table: str, dialect: str) -> str:
    if dialect == "sqlite":
        return f"CREATE TABLE {backup_table} AS SELECT * FROM {table_name}"
    return f"CREATE TABLE {backup_table} AS TABLE {table_name}"


# ---------------------------------------------------------------------------
# 计划渲染
# ---------------------------------------------------------------------------


def _render_create(plan: Mapping[str, Any], statements: _Statements) -> None:
    table_name = str(plan["table_name"])
    dialect = str(plan["dialect"])
    columns = [str(column["name"]) for column in plan.get("target_columns") or ()]
    definitions = [
        _render_column_definition(column, dialect)
        for column in plan.get("target_columns") or ()
    ]
    if any(
        column.get("primary_key") for column in plan.get("target_columns") or ()
    ):
        definitions.append(
            f"CONSTRAINT pk_{table_name} PRIMARY KEY ({', '.join(columns)})"
        )
    body = ",\n    ".join(definitions)
    statements.add(
        f"CREATE TABLE {table_name} (\n    {body}\n)",
        CATEGORY_CREATE_TABLE,
    )
    for index in plan.get("target_indexes") or ():
        statements.add(
            _create_index_sql(table_name, index),
            CATEGORY_CREATE_INDEX,
        )


def _render_alter(plan: Mapping[str, Any], statements: _Statements) -> None:
    table_name = str(plan["table_name"])
    dialect = str(plan["dialect"])
    backup_table = plan.get("backup_table")

    if backup_table:
        statements.add(
            _backup_sql(table_name, str(backup_table), dialect),
            CATEGORY_BACKUP,
        )

    for item in plan.get("renamed_columns") or ():
        statements.add(
            f"ALTER TABLE {table_name} RENAME COLUMN {item['from_name']}"
            f" TO {item['to_name']}",
            CATEGORY_ALTER_TABLE,
        )

    for index in plan.get("dropped_indexes") or ():
        name = index.get("name")
        if name:
            statements.add(_drop_index_sql(str(name)), CATEGORY_DROP_INDEX)

    for column in plan.get("added_columns") or ():
        definition = _render_column_definition(column, dialect)
        statements.add(
            f"ALTER TABLE {table_name} ADD COLUMN {definition}",
            CATEGORY_ALTER_TABLE,
        )

    for item in plan.get("modified_columns") or ():
        target = item["target"]
        target_name = str(target["name"])
        aspects = list(item.get("aspects") or ())
        if "type" in aspects:
            narrowed = (
                schema_spec.classify_type_change(item["source"], target)
                in (schema_spec.TYPE_CHANGE_NARROW, schema_spec.TYPE_CHANGE_REBUILD)
            )
            statements.add(
                _render_change_type(table_name, target, dialect),
                CATEGORY_ALTER_TABLE,
                destructive=narrowed,
            )
        if "nullable" in aspects:
            action = "DROP NOT NULL" if target.get("nullable") else "SET NOT NULL"
            statements.add(
                f"ALTER TABLE {table_name} ALTER COLUMN {target_name} {action}",
                CATEGORY_ALTER_TABLE,
                destructive=not bool(target.get("nullable")),
            )
        if "server_default" in aspects:
            default_sql = _default_sql(target.get("server_default"))
            if default_sql is None:
                statements.add(
                    f"ALTER TABLE {table_name} ALTER COLUMN {target_name}"
                    " DROP DEFAULT",
                    CATEGORY_ALTER_TABLE,
                )
            else:
                statements.add(
                    f"ALTER TABLE {table_name} ALTER COLUMN {target_name}"
                    f" SET DEFAULT {default_sql}",
                    CATEGORY_ALTER_TABLE,
                )

    for column in plan.get("dropped_columns") or ():
        statements.add(
            f"ALTER TABLE {table_name} DROP COLUMN {column['name']}",
            CATEGORY_ALTER_TABLE,
            destructive=True,
        )

    for index in plan.get("added_indexes") or ():
        statements.add(
            _create_index_sql(table_name, index),
            CATEGORY_CREATE_INDEX,
        )


def _render_rebuild(plan: Mapping[str, Any], statements: _Statements) -> None:
    table_name = str(plan["table_name"])
    dialect = str(plan["dialect"])
    working_table = f"{table_name[:_MAX_IDENTIFIER_LENGTH - len(_NEW_TABLE_SUFFIX)]}"
    working_table = f"{working_table}{_NEW_TABLE_SUFFIX}"
    backup_table = str(plan.get("backup_table") or "")

    # 上一次失败理论上会随事务回滚，这里仍先清理可能的同名残留。
    statements.add(
        f"DROP TABLE IF EXISTS {working_table}",
        CATEGORY_ALTER_TABLE,
    )

    definitions = [
        _render_column_definition(column, dialect)
        for column in plan.get("target_columns") or ()
    ]
    primary_columns = [
        str(column["name"])
        for column in plan.get("target_columns") or ()
        if column.get("primary_key")
    ]
    if primary_columns:
        definitions.append(
            f"CONSTRAINT pk_{working_table} PRIMARY KEY"
            f" ({', '.join(primary_columns)})"
        )
    statements.add(
        f"CREATE TABLE {working_table} (\n    " + ",\n    ".join(definitions) + "\n)",
        CATEGORY_CREATE_TABLE,
    )

    mapping = [
        item for item in plan.get("column_mapping") or () if item.get("source")
    ]
    if mapping:
        target_list = ", ".join(str(item["target"]) for item in mapping)
        source_list = ", ".join(str(item["source"]) for item in mapping)
        statements.add(
            f"INSERT INTO {working_table} ({target_list})"
            f" SELECT {source_list} FROM {table_name}",
            CATEGORY_MIGRATE_DATA,
        )

    statements.add(
        f"ALTER TABLE {table_name} RENAME TO {backup_table}",
        CATEGORY_RENAME_TABLE,
    )

    # 索引名在 PostgreSQL / SQLite 里是库级唯一，旧索引仍占着名字；
    # 切名后统一释放。备份表只保数据，索引定义记录在计划里可人工重建。
    for index in plan.get("current_indexes") or ():
        name = index.get("name")
        if name:
            statements.add(_drop_index_sql(str(name)), CATEGORY_DROP_INDEX)

    statements.add(
        f"ALTER TABLE {working_table} RENAME TO {table_name}",
        CATEGORY_RENAME_TABLE,
    )

    for index in plan.get("target_indexes") or ():
        statements.add(
            _create_index_sql(table_name, index),
            CATEGORY_CREATE_INDEX,
        )


def render_statements(plan: Mapping[str, Any]) -> list[dict[str, Any]]:
    """把计划渲染成有序语句列表；纯函数，不触库。"""
    statements = _Statements()
    path = str(plan.get("path") or "")
    if path == "create":
        _render_create(plan, statements)
    elif path == "rebuild":
        _render_rebuild(plan, statements)
    else:
        _render_alter(plan, statements)
    return statements.items()


def render_precheck(plan: Mapping[str, Any]) -> list[dict[str, Any]]:
    """渲染只读预检查语句，供手动方案的第一段使用。"""
    statements = _Statements()
    table_name = str(plan["table_name"])
    statements.add(
        f"SELECT COUNT(*) FROM {table_name}",
        CATEGORY_MIGRATE_DATA,
        inline=True,
    )
    for column in plan.get("added_columns") or ():
        if bool(column.get("nullable")) or column.get("server_default") is not None:
            continue
        statements.add(
            f"SELECT COUNT(*) FROM {table_name}"
            f" WHERE {column['name']} IS NULL",
            CATEGORY_MIGRATE_DATA,
            inline=True,
        )
    for index in plan.get("added_indexes") or ():
        if not index.get("unique"):
            continue
        columns = ", ".join(str(name) for name in index.get("columns") or ())
        statements.add(
            "SELECT COUNT(*) FROM ("
            f"SELECT 1 FROM {table_name} GROUP BY {columns} HAVING COUNT(*) > 1"
            ") __probe",
            CATEGORY_MIGRATE_DATA,
            inline=True,
        )
    return statements.items()


def render_rollback(plan: Mapping[str, Any]) -> list[dict[str, Any]]:
    """渲染尽力而为的回滚脚本；不可逆处用 SQL 注释明示风险。"""
    statements = _Statements()
    table_name = str(plan["table_name"])
    dialect = str(plan["dialect"])
    path = str(plan.get("path") or "")
    backup_table = plan.get("backup_table")

    if path == "create":
        statements.add(f"DROP TABLE {table_name}", CATEGORY_ALTER_TABLE, destructive=True)
        return statements.items()

    if path == "rebuild":
        statements.add(
            f"-- 回滚：丢弃新表并从备份表恢复原结构与数据",
            CATEGORY_RENAME_TABLE,
        )
        statements.add(f"DROP TABLE {table_name}", CATEGORY_ALTER_TABLE, destructive=True)
        if backup_table:
            statements.add(
                f"ALTER TABLE {backup_table} RENAME TO {table_name}",
                CATEGORY_RENAME_TABLE,
            )
        for index in plan.get("current_indexes") or ():
            name = index.get("name")
            if not name:
                continue
            statements.add(
                _create_index_sql(table_name, index),
                CATEGORY_CREATE_INDEX,
            )
        return statements.items()

    for index in plan.get("added_indexes") or ():
        statements.add(
            _drop_index_sql(_statement_index_name(table_name, index)),
            CATEGORY_DROP_INDEX,
        )
    for item in plan.get("modified_columns") or ():
        source = item["source"]
        aspects = list(item.get("aspects") or ())
        source_name = str(source["name"])
        if "server_default" in aspects:
            default_sql = _default_sql(source.get("server_default"))
            if default_sql is None:
                statements.add(
                    f"ALTER TABLE {table_name} ALTER COLUMN {source_name}"
                    " DROP DEFAULT",
                    CATEGORY_ALTER_TABLE,
                )
            else:
                statements.add(
                    f"ALTER TABLE {table_name} ALTER COLUMN {source_name}"
                    f" SET DEFAULT {default_sql}",
                    CATEGORY_ALTER_TABLE,
                )
        if "nullable" in aspects:
            action = "DROP NOT NULL" if source.get("nullable") else "SET NOT NULL"
            statements.add(
                f"ALTER TABLE {table_name} ALTER COLUMN {source_name} {action}",
                CATEGORY_ALTER_TABLE,
            )
        if "type" in aspects:
            statements.add(
                _render_change_type(table_name, source, dialect),
                CATEGORY_ALTER_TABLE,
                destructive=True,
            )
    for item in plan.get("renamed_columns") or ():
        statements.add(
            f"ALTER TABLE {table_name} RENAME COLUMN {item['to_name']}"
            f" TO {item['from_name']}",
            CATEGORY_ALTER_TABLE,
        )
    for column in plan.get("added_columns") or ():
        statements.add(
            f"ALTER TABLE {table_name} DROP COLUMN {column['name']}",
            CATEGORY_ALTER_TABLE,
            destructive=True,
        )
    for column in plan.get("dropped_columns") or ():
        # 列数据已随 DDL 删除，只能从备份表人工回填。
        statements.add(
            f"-- 无法自动回滚：列 {column['name']} 的数据需从备份表"
            f" {backup_table or '<未备份>'} 人工恢复",
            CATEGORY_ALTER_TABLE,
        )
        statements.add(
            f"ALTER TABLE {table_name} ADD COLUMN"
            f" {_render_column_definition(column, dialect)}",
            CATEGORY_ALTER_TABLE,
        )
    for index in plan.get("dropped_indexes") or ():
        statements.add(
            _create_index_sql(table_name, index),
            CATEGORY_CREATE_INDEX,
        )
    return statements.items()


# ---------------------------------------------------------------------------
# 结构读取
# ---------------------------------------------------------------------------


def _strip_casts(value: str) -> str:
    """去掉 PostgreSQL 默认值表达式尾部的 ``::type`` 转换。"""
    current = value.strip()
    while True:
        match = _CAST_SUFFIX_RE.search(current)
        if not match:
            return current
        current = current[: match.start()].strip()


def _normalize_database_default(raw: Any) -> tuple[str | None, bool]:
    """把数据库返回的默认值归一成白名单形态。

    返回 ``(归一化默认值, 是否自增)``。自增列在 PostgreSQL 上表现为
    ``nextval(...)``，它不是业务默认值，交由 ``autoincrement`` 表达。
    无法识别的默认值归一为 ``None``：此时计划不会生成任何默认值变更语句，
    数据库里的原默认值保持不变，避免在用户未察觉时被清掉。
    """
    if raw is None:
        return None, False
    text_value = str(raw).strip()
    if not text_value:
        return None, False
    if text_value.lower().startswith("nextval("):
        return None, True
    sanitized = _strip_casts(text_value)
    try:
        return schema_spec.normalize_server_default(sanitized), False
    except KmvException:
        logger.warning(
            "无法归一的数据库默认值，按无默认值处理且不会主动清除: %s",
            sanitized,
        )
        return None, False


def _inspect_table(sync_conn: Any, table_name: str) -> dict[str, Any]:
    """读取单表结构；包含默认值与本模块需要的全部细节。"""
    inspector = sa_inspect(sync_conn)
    if not inspector.has_table(table_name):
        return {
            "table_name": table_name,
            "exists": False,
            "comment": None,
            "row_count": None,
            "columns": [],
            "indexes": [],
        }

    try:
        comment_payload = inspector.get_table_comment(table_name)
        comment = (
            comment_payload.get("text") if isinstance(comment_payload, dict) else None
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("读取表 %s 注释失败: %s", table_name, exc)
        comment = None

    try:
        row_count: int | None = int(
            sync_conn.execute(
                select(func.count()).select_from(
                    Table(table_name, MetaData(), autoload_with=sync_conn)
                )
            ).scalar_one()
        )
    except Exception as exc:  # noqa: BLE001
        logger.warning("读取表 %s 行数失败: %s", table_name, exc)
        row_count = None

    pk_constraint = inspector.get_pk_constraint(table_name) or {}
    pk_columns = [
        str(name) for name in pk_constraint.get("constrained_columns") or [] if name
    ]
    pk_name = str(pk_constraint.get("name") or "PRIMARY")

    index_columns: set[str] = set()
    unique_columns: set[str] = set()
    indexes: list[dict[str, Any]] = []
    if pk_columns:
        indexes.append({
            "name": pk_name,
            "columns": pk_columns,
            "unique": True,
            "primary": True,
        })

    seen_signatures: set[tuple[tuple[str, ...], bool]] = set()
    for index in inspector.get_indexes(table_name):
        names = [str(name) for name in index.get("column_names") or [] if name]
        index_name = str(index.get("name") or "")
        if not names or index_name == pk_name:
            continue
        signature = (tuple(names), bool(index.get("unique")))
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        index_columns.update(names)
        if index.get("unique"):
            unique_columns.update(names)
        indexes.append({
            "name": index_name,
            "columns": names,
            "unique": bool(index.get("unique")),
            "primary": False,
        })

    for constraint in inspector.get_unique_constraints(table_name):
        names = [
            str(name) for name in constraint.get("column_names") or [] if name
        ]
        if not names:
            continue
        signature = (tuple(names), True)
        unique_columns.update(names)
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        index_columns.update(names)
        indexes.append({
            "name": str(constraint.get("name") or ""),
            "columns": names,
            "unique": True,
            "primary": False,
        })

    columns: list[dict[str, Any]] = []
    for raw_column in inspector.get_columns(table_name):
        name = str(raw_column.get("name") or "")
        mapped = _type_from_database(raw_column.get("type"))
        if mapped is None:
            logger.warning(
                "表 %s 列 %s 的类型 %s 无法映射到白名单",
                table_name,
                name,
                raw_column.get("type"),
            )
            raise _unsupported()
        column_type, type_args = mapped
        server_default, sequence_default = _normalize_database_default(
            raw_column.get("default")
        )
        is_primary = name in pk_columns
        autoincrement = bool(
            sequence_default
            or (is_primary and len(pk_columns) == 1 and column_type in
                schema_spec.INTEGER_TYPES)
        )
        if autoincrement:
            server_default = None
        columns.append({
            "name": name,
            "original_name": None,
            "type": column_type,
            "type_args": type_args,
            "nullable": bool(raw_column.get("nullable", True)),
            "primary_key": is_primary,
            "autoincrement": autoincrement,
            "server_default": server_default,
            "unique": name in unique_columns,
            "indexed": name in index_columns,
            "comment": raw_column.get("comment") or None,
        })

    return {
        "table_name": table_name,
        "exists": True,
        "comment": comment,
        "row_count": row_count,
        "columns": columns,
        "indexes": indexes,
    }


async def read_table_schema(
    engine: AsyncEngine,
    table_name: str,
) -> dict[str, Any]:
    """读取当前表结构（含默认值）；表不存在时返回 ``exists: False``。"""
    async with engine.connect() as conn:
        return await conn.run_sync(_inspect_table, table_name)


def _measure(sync_conn: Any, table_name: str, probes: Sequence[Mapping[str, Any]]) -> dict[int, int]:
    measured: dict[int, int] = {}
    for position, probe in enumerate(probes):
        kind = str(probe.get("kind") or "")
        try:
            if kind == "nulls":
                sql = f"SELECT COUNT(*) FROM {table_name} WHERE {probe['column']} IS NULL"
            elif kind == "duplicates":
                columns = ", ".join(str(name) for name in probe["columns"])
                sql = (
                    "SELECT COUNT(*) FROM ("
                    f"SELECT 1 FROM {table_name} GROUP BY {columns}"
                    " HAVING COUNT(*) > 1) __probe"
                )
            else:
                continue
            measured[position] = int(sync_conn.execute(text(sql)).scalar_one())
        except Exception as exc:  # noqa: BLE001
            # 计数失败按「未知」处理，风险项保留，不替用户降低确认门槛。
            logger.warning("预检查计数失败 table=%s: %s", table_name, exc)
    return measured


async def measure_probes(
    engine: AsyncEngine,
    table_name: str,
    probes: Sequence[Mapping[str, Any]],
) -> dict[int, int]:
    """执行只读计数，回填确认级风险的真实受影响行数。"""
    if not probes:
        return {}
    async with engine.connect() as conn:
        return await conn.run_sync(_measure, table_name, probes)


# ---------------------------------------------------------------------------
# 执行
# ---------------------------------------------------------------------------


async def execute_statements(
    engine: AsyncEngine,
    statements: Sequence[Mapping[str, Any]],
) -> list[str]:
    """在单个事务内严格串行执行全部语句；任一失败整体回滚。

    刻意不使用 ``CREATE INDEX CONCURRENTLY``：它无法在事务内执行，会破坏
    整体回滚。
    """
    executed: list[str] = []
    async with engine.begin() as conn:
        for statement in statements:
            sql = str(statement.get("sql") or "").strip()
            if not sql or sql.startswith("--"):
                continue
            await conn.execute(text(sql))
            executed.append(sql)
    return executed