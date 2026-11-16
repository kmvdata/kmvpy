# coding: utf-8
"""表结构编辑的业务规则：差异、风险与执行计划。

本 Hub 只做纯规则计算，全部 ``@staticmethod``，不 import FastAPI / DTO /
Router / Service，也不自行开启事务。SQL 文本渲染与串行执行属于 Infra
（``common/infra/database/ddl.py``），因为那是技术资源生命周期。

规划模型是结构化 dict，不是 SQL：

- ``path`` 决定走快路径还是重建路径；
- ``column_mapping`` 决定重建时如何搬数据（这就是「尽量保住旧数据」）；
- 风险项携带内部 ``_probe``，由 Infra 渲染成计数 SQL 后回填真实受影响行数。
"""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import datetime
from time import perf_counter
from typing import Any

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.database import ddl as database_ddl
from __PROJECT_NAME__.common.infra.orm import registered_orm_model_by_table_name, schema_spec

# 执行计划路径
PATH_CREATE = "create"
PATH_ALTER = "alter"
PATH_REBUILD = "rebuild"

# 预览模式
MODE_AUTO = "auto"
MODE_MANUAL = "manual"

# 风险等级
LEVEL_INFO = "info"
LEVEL_CONFIRM = "confirm"
LEVEL_BLOCKING = "blocking"

# 稳定风险码；文案由 SPA 侧翻译，后端只下发 code。
RISK_TYPE_NARROWING = "TYPE_NARROWING"
RISK_NOT_NULL_WITH_NULLS = "NOT_NULL_WITH_NULLS"
RISK_UNIQUE_WITH_DUPLICATES = "UNIQUE_WITH_DUPLICATES"
RISK_DROP_COLUMN = "DROP_COLUMN"
RISK_DROP_INDEX = "DROP_INDEX"
RISK_REBUILD_TABLE = "REBUILD_TABLE"
RISK_LARGE_TABLE_LOCK = "LARGE_TABLE_LOCK"
RISK_NON_ATOMIC_DIALECT = "NON_ATOMIC_DIALECT"
RISK_COLUMN_REORDER = "COLUMN_REORDER"
RISK_IDENTIFIER_INVALID = "IDENTIFIER_INVALID"
RISK_PATH_NOT_SUPPORTED = "PATH_NOT_SUPPORTED"

# 大表阈值：超过即提示可能长时间持锁。缺少生产容量证据，取保守值。
LARGE_TABLE_ROW_THRESHOLD = 1_000_000

# 备份表名后缀长度：``__bak_`` + ``yyyymmddHHMMSS``。
_BACKUP_SUFFIX_LENGTH = len("__bak_") + 14
_MAX_IDENTIFIER_LENGTH = 63

_SUPPORTED_ATOMIC_DIALECTS = frozenset({"postgresql", "sqlite"})


def capabilities_of(dialect: str) -> dict[str, bool]:
    """返回某方言的能力矩阵。

    ``reorder_column`` 三个方言统一为 False：真实列序调整需要重建表，
    而编辑器只允许新增列参与排序，避免随手拖动被误判成结构变更。
    """
    name = (dialect or "").strip().lower()
    if name == "postgresql":
        return {
            "atomic_ddl": True,
            "rename_column": True,
            "alter_type": True,
            "reorder_column": False,
        }
    if name == "sqlite":
        return {
            "atomic_ddl": True,
            "rename_column": False,
            "alter_type": False,
            "reorder_column": False,
        }
    if name == "mysql":
        return {
            "atomic_ddl": False,
            "rename_column": True,
            "alter_type": True,
            "reorder_column": False,
        }
    return {
        "atomic_ddl": False,
        "rename_column": False,
        "alter_type": False,
        "reorder_column": False,
    }


def backup_table_name(table_name: str, timestamp: str | None = None) -> str:
    """生成只创建、只展示的备份表名。"""
    stamp = timestamp or datetime.now().strftime("%Y%m%d%H%M%S")
    suffix = f"__bak_{stamp}"
    keep = max(_MAX_IDENTIFIER_LENGTH - _BACKUP_SUFFIX_LENGTH, 1)
    return f"{table_name[:keep]}{suffix}"


def _match_target_column(current_columns: Sequence[Mapping[str, Any]],
                         target: Mapping[str, Any]) -> str | None:
    """把目标列映射回当前列名。

    改名必须通过 ``original_name`` 显式表达；没有改名标记时只按同名列
    匹配。这样「改名」不会被误判成「删列 + 加列」，不会丢数据。
    """
    original_name = target.get("original_name")
    if original_name:
        return str(original_name)
    name = str(target.get("name") or "")
    for column in current_columns:
        if column.get("name") == name:
            return name
    return None


def _column_type_signature(column: Mapping[str, Any]) -> tuple[Any, ...]:
    return (
        column.get("type"),
        tuple(column.get("type_args") or ()),
    )


def _integer_primary_key_equivalent(
    current: Mapping[str, Any],
    target: Mapping[str, Any],
) -> bool:
    """自增整型主键在不同方言下的物理类型不同，不视为结构变更。

    SQLite 上 ``AUTO_INCREMENT_PK_TYPE`` 编译为 ``INTEGER``，PostgreSQL 上
    编译为 ``BIGINT``。同一张表在两种方言下内省结果不同，按字面比较会为
    每张表制造一个虚假的类型变更。
    """
    if not (current.get("primary_key") and target.get("primary_key")):
        return False
    if not (current.get("autoincrement") and target.get("autoincrement")):
        return False
    return (
        current.get("type") in schema_spec.INTEGER_TYPES
        and target.get("type") in schema_spec.INTEGER_TYPES
    )


def _modified_aspects(
    current: Mapping[str, Any],
    target: Mapping[str, Any],
) -> list[str]:
    """返回发生变化的列属性名列表。``comment`` 不参与结构比较。"""
    aspects: list[str] = []
    if _column_type_signature(current) != _column_type_signature(target):
        if not _integer_primary_key_equivalent(current, target):
            aspects.append("type")
    if bool(current.get("nullable")) != bool(target.get("nullable")):
        aspects.append("nullable")
    if current.get("server_default") != target.get("server_default"):
        aspects.append("server_default")
    if bool(current.get("primary_key")) != bool(target.get("primary_key")):
        aspects.append("primary_key")
    if bool(current.get("autoincrement")) != bool(target.get("autoincrement")):
        aspects.append("autoincrement")
    return aspects


def _index_signature(index: Mapping[str, Any]) -> tuple[tuple[str, ...], bool]:
    return (tuple(str(name) for name in index.get("columns") or ()),
            bool(index.get("unique")))


def _index_payload(index: Mapping[str, Any]) -> dict[str, Any]:
    return {
        "name": index.get("name"),
        "columns": [str(name) for name in index.get("columns") or ()],
        "unique": bool(index.get("unique")),
        "primary": bool(index.get("primary")),
    }


def build_diff(
    current: Mapping[str, Any],
    target_columns: Sequence[Mapping[str, Any]],
    target_indexes: Sequence[Mapping[str, Any]],
    dialect: str,
) -> dict[str, Any]:
    """比当前结构与目标结构，产出结构化差异。

    已有列的相对顺序不参与差异判定；只有「已有列相对顺序被改动」时
    才记录 ``reorder_required``，由风险评估升级为 blocking。
    """
    current_columns = list(current.get("columns") or ())
    current_by_name = {
        str(column.get("name")): column for column in current_columns
    }
    exists = bool(current.get("exists", True))

    matched: dict[str, Mapping[str, Any]] = {}
    added: list[dict[str, Any]] = []
    renamed: list[dict[str, Any]] = []
    modified: list[dict[str, Any]] = []

    for target in target_columns:
        source_name = _match_target_column(current_columns, target)
        if source_name is None:
            added.append(dict(target))
            continue
        source = current_by_name.get(source_name)
        if source is None:
            added.append(dict(target))
            continue
        matched[source_name] = target
        if source_name != target.get("name"):
            renamed.append({
                "from_name": source_name,
                "to_name": str(target.get("name")),
                "target": dict(target),
                "source": dict(source),
            })
        aspects = _modified_aspects(source, target)
        if aspects:
            modified.append({
                "name": source_name,
                "target_name": str(target.get("name")),
                "aspects": aspects,
                "source": dict(source),
                "target": dict(target),
            })

    dropped = [
        dict(column)
        for name, column in current_by_name.items()
        if name not in matched
    ]

    # 已有列的相对顺序：取「匹配到的当前列」在目标顺序中的先后。
    matched_order = [
        _match_target_column(current_columns, target)
        for target in target_columns
    ]
    matched_order = [name for name in matched_order if name is not None]
    current_order = [name for name in current_by_name if name in set(matched_order)]
    reorder_required = matched_order != current_order

    current_indexes = [
        _index_payload(index)
        for index in current.get("indexes") or ()
        if not index.get("primary")
    ]
    current_index_map = {
        _index_signature(index): index for index in current_indexes
    }
    target_index_signatures = {
        _index_signature(index) for index in target_indexes
    }
    keep_indexes = [
        _index_payload(index)
        for index in target_indexes
        if _index_signature(index) in current_index_map
    ]
    added_indexes = [
        _index_payload(index)
        for index in target_indexes
        if _index_signature(index) not in current_index_map
    ]
    dropped_indexes = [
        _index_payload(index)
        for index in current_indexes
        if _index_signature(index) not in target_index_signatures
    ]

    primary_changed = any(
        "primary_key" in item["aspects"] or "autoincrement" in item["aspects"]
        for item in modified
    ) or any(column.get("primary_key") for column in added)

    type_changes = [
        schema_spec.classify_type_change(item["source"], item["target"])
        for item in modified
        if "type" in item["aspects"]
    ]
    type_narrowed = any(
        change in (schema_spec.TYPE_CHANGE_NARROW, schema_spec.TYPE_CHANGE_REBUILD)
        for change in type_changes
    )

    column_changed = bool(added or dropped or renamed or modified)
    index_changed = bool(added_indexes or dropped_indexes)

    needs_rebuild = (
        primary_changed
        or type_narrowed
        or reorder_required
        or (
            dialect == "sqlite"
            and column_changed
        )
    )

    if not exists:
        path = PATH_CREATE
        needs_rebuild = False
    elif needs_rebuild:
        path = PATH_REBUILD
    else:
        path = PATH_ALTER

    return {
        "exists": exists,
        "path": path,
        "added_columns": added,
        "dropped_columns": dropped,
        "renamed_columns": renamed,
        "modified_columns": modified,
        "added_indexes": added_indexes,
        "dropped_indexes": dropped_indexes,
        "kept_indexes": keep_indexes,
        "reorder_required": reorder_required,
        "primary_changed": primary_changed,
        "column_changed": column_changed,
        "index_changed": index_changed,
        "has_changes": column_changed or index_changed,
        "plan_summary": {
            "added": len(added),
            "modified": len(modified),
            "removed": len(dropped),
            "renamed": len(renamed),
            "indexes_added": len(added_indexes),
            "indexes_removed": len(dropped_indexes),
            "indexes_unchanged": len(keep_indexes),
            "total": (
                len(added)
                + len(modified)
                + len(dropped)
                + len(renamed)
                + len(added_indexes)
                + len(dropped_indexes)
            ),
        },
    }


def _risk(
    code: str,
    level: str,
    *,
    affected_rows: int | None = None,
    probe: Mapping[str, Any] | None = None,
    detail: Mapping[str, Any] | None = None,
) -> dict[str, Any]:
    item: dict[str, Any] = {
        "code": code,
        "level": level,
        "statement_index": None,
        "affected_rows": affected_rows,
        "detail": dict(detail or {}),
    }
    if probe:
        item["_probe"] = dict(probe)
    return item


def assess_risk(
    current: Mapping[str, Any],
    target_columns: Sequence[Mapping[str, Any]],
    dialect: str,
    diff: Mapping[str, Any],
    row_count: int | None,
) -> list[dict[str, Any]]:
    """评估风险；每项都带稳定 code、等级与可选探针。

    需要读取数据的确认项携带 ``_probe``，由 Infra 渲染并执行计数 SQL 后
    回填真实受影响行数：计数为 0 的确认项会自动消失，避免无意义勾选。
    """
    risks: list[dict[str, Any]] = []
    target_by_name = {
        str(column.get("name")): column for column in target_columns
    }

    if dialect not in _SUPPORTED_ATOMIC_DIALECTS:
        risks.append(_risk(RISK_NON_ATOMIC_DIALECT, LEVEL_BLOCKING))
        if diff.get("path") != PATH_ALTER:
            risks.append(_risk(RISK_PATH_NOT_SUPPORTED, LEVEL_BLOCKING))

    for name in [current.get("table_name"), *[
        column.get("name") for column in current.get("columns") or ()
    ]]:
        if name is None:
            continue
        if not schema_spec.is_identifier_valid(name):
            risks.append(
                _risk(RISK_IDENTIFIER_INVALID, LEVEL_BLOCKING,
                      detail={"name": str(name)})
            )
            break

    if diff.get("reorder_required"):
        risks.append(_risk(RISK_COLUMN_REORDER, LEVEL_BLOCKING))

    if diff.get("path") == PATH_REBUILD:
        risks.append(
            _risk(RISK_REBUILD_TABLE, LEVEL_INFO, affected_rows=row_count)
        )

    for item in diff.get("modified_columns") or ():
        if "type" not in item["aspects"]:
            continue
        change = schema_spec.classify_type_change(item["source"], item["target"])
        if change in (schema_spec.TYPE_CHANGE_NARROW, schema_spec.TYPE_CHANGE_REBUILD):
            risks.append(
                _risk(
                    RISK_TYPE_NARROWING,
                    LEVEL_CONFIRM,
                    affected_rows=row_count,
                    detail={"column": item.get("name")},
                )
            )

    for column in diff.get("added_columns") or ():
        if bool(column.get("nullable")) or column.get("server_default") is not None:
            continue
        # 新列 NOT NULL 且无默认值：现存行都会是 NULL，无法直接加。
        risks.append(
            _risk(
                RISK_NOT_NULL_WITH_NULLS,
                LEVEL_CONFIRM,
                affected_rows=row_count,
                detail={"column": column.get("name")},
            )
        )

    for item in diff.get("modified_columns") or ():
        if "nullable" not in item["aspects"]:
            continue
        if bool(item["target"].get("nullable")):
            continue
        if item["source"].get("server_default") != item["target"].get("server_default"):
            # 同时改了默认值，风险已由默认值变更覆盖。
            continue
        risks.append(
            _risk(
                RISK_NOT_NULL_WITH_NULLS,
                LEVEL_CONFIRM,
                probe={"kind": "nulls", "column": str(item.get("name"))},
                detail={"column": item.get("name")},
            )
        )

    for index in diff.get("added_indexes") or ():
        if not index.get("unique"):
            continue
        columns = [str(name) for name in index.get("columns") or ()]
        risks.append(
            _risk(
                RISK_UNIQUE_WITH_DUPLICATES,
                LEVEL_CONFIRM,
                probe={"kind": "duplicates", "columns": columns},
                detail={"columns": columns},
            )
        )

    for column in diff.get("dropped_columns") or ():
        risks.append(
            _risk(
                RISK_DROP_COLUMN,
                LEVEL_CONFIRM,
                affected_rows=row_count,
                detail={"column": column.get("name")},
            )
        )

    for index in diff.get("dropped_indexes") or ():
        risks.append(
            _risk(
                RISK_DROP_INDEX,
                LEVEL_CONFIRM,
                detail={"index": index.get("name")},
            )
        )

    if (
        row_count is not None
        and row_count > LARGE_TABLE_ROW_THRESHOLD
        and diff.get("has_changes")
    ):
        risks.append(
            _risk(RISK_LARGE_TABLE_LOCK, LEVEL_CONFIRM, affected_rows=row_count)
        )

    # 去掉首尾相同的单列别名：改名后列定义不变时不应误报类型收窄。
    if not diff.get("has_changes"):
        risks = [
            item for item in risks
            if item["code"] in (RISK_NON_ATOMIC_DIALECT, RISK_IDENTIFIER_INVALID,
                                RISK_COLUMN_REORDER)
        ]

    return risks


def resolve_risk_probes(
    risks: Sequence[Mapping[str, Any]],
    measured: Mapping[int, int],
) -> list[dict[str, Any]]:
    """把探针计数回填到风险项。

    ``measured`` 的键是风险项在「带探针风险项」序列中的序号，由 Infra
    按渲染顺序返回。计数为 0 的确认项直接移除：没有 NULL、没有重复值时
    该变更并没有数据风险，不该逼用户勾选。
    """
    resolved: list[dict[str, Any]] = []
    probe_index = 0
    for item in risks:
        probe = item.get("_probe")
        if not probe:
            resolved.append({
                key: value for key, value in item.items() if key != "_probe"
            })
            continue
        count = measured.get(probe_index)
        probe_index += 1
        if count is None:
            continue
        if count <= 0:
            continue
        item_payload = {
            key: value for key, value in item.items() if key != "_probe"
        }
        item_payload["affected_rows"] = int(count)
        resolved.append(item_payload)
    return resolved


def probe_sequence(risks: Sequence[Mapping[str, Any]]) -> list[dict[str, Any]]:
    """按渲染顺序取出探针定义，供 Infra 依次渲染并执行计数 SQL。"""
    return [dict(item["_probe"]) for item in risks if item.get("_probe")]


def summarize_risk_levels(risks: Sequence[Mapping[str, Any]]) -> dict[str, int]:
    """统计各等级风险数量，供 UI 徽标与计划摘要使用。"""
    counts = {LEVEL_INFO: 0, LEVEL_CONFIRM: 0, LEVEL_BLOCKING: 0}
    for item in risks:
        level = str(item.get("level"))
        if level in counts:
            counts[level] += 1
    return counts


def decide_mode(risks: Sequence[Mapping[str, Any]]) -> str:
    """有任一 blocking 风险即只能手动处理。"""
    for item in risks:
        if item.get("level") == LEVEL_BLOCKING:
            return MODE_MANUAL
    return MODE_AUTO


def build_plan(
    table_name: str,
    current: Mapping[str, Any],
    target_columns: Sequence[Mapping[str, Any]],
    target_indexes: Sequence[Mapping[str, Any]],
    diff: Mapping[str, Any],
    dialect: str,
    backup: bool,
    timestamp: str | None = None,
) -> dict[str, Any]:
    """产出结构化执行计划；SQL 文本由 Infra 渲染。

    ``column_mapping`` 是重建路径搬数据的唯一依据：

    - 能匹配到当前列 → 按来源列名复制（改名也走这里）；
    - 新增列 → 不复制，走默认值或 NULL；
    - 被删除列 → 不复制，数据随旧表保留在备份表中。
    """
    path = str(diff.get("path") or PATH_ALTER)
    exists = bool(diff.get("exists", True))
    current_columns = list(current.get("columns") or ())
    current_by_name = {
        str(column.get("name")): column for column in current_columns
    }

    column_mapping: list[dict[str, Any]] = []
    for target in target_columns:
        source_name = _match_target_column(current_columns, target)
        source = current_by_name.get(source_name) if source_name else None
        column_mapping.append({
            "source": source_name if source is not None else None,
            "target": str(target.get("name")),
        })

    backup_table = None
    if backup and exists:
        backup_table = backup_table_name(table_name, timestamp)
    if path == PATH_REBUILD and backup_table is None:
        # 重建路径必须保留旧表，否则数据没有任何回退余地。
        backup_table = backup_table_name(table_name, timestamp)

    return {
        "table_name": table_name,
        "dialect": dialect,
        "path": path,
        "exists": exists,
        "backup_requested": bool(backup),
        "backup_table": backup_table,
        "target_columns": [dict(column) for column in target_columns],
        "target_indexes": [dict(index) for index in target_indexes],
        "current_columns": current_columns,
        "current_indexes": [
            _index_payload(index)
            for index in current.get("indexes") or ()
            if not index.get("primary")
        ],
        "added_columns": [dict(column) for column in diff.get("added_columns") or ()],
        "dropped_columns": [dict(column) for column in diff.get("dropped_columns") or ()],
        "renamed_columns": [dict(item) for item in diff.get("renamed_columns") or ()],
        "modified_columns": [dict(item) for item in diff.get("modified_columns") or ()],
        "added_indexes": [dict(index) for index in diff.get("added_indexes") or ()],
        "dropped_indexes": [dict(index) for index in diff.get("dropped_indexes") or ()],
        "column_mapping": column_mapping,
    }


class DatabaseTableSchemaHub:
    """表结构编辑的规则入口；结构读取委托给 Infra。"""

    @staticmethod
    def normalize_spec(
        columns: Sequence[Mapping[str, Any]],
        indexes: Sequence[Mapping[str, Any]],
    ) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
        """收窄并规范化目标结构；不合法立即抛 46008。"""
        return schema_spec.normalize_specification(columns, indexes)

    @staticmethod
    def capabilities(dialect: str) -> dict[str, bool]:
        return capabilities_of(dialect)

    @staticmethod
    def build_diff(
        current: Mapping[str, Any],
        target_columns: Sequence[Mapping[str, Any]],
        target_indexes: Sequence[Mapping[str, Any]],
        dialect: str,
    ) -> dict[str, Any]:
        return build_diff(current, target_columns, target_indexes, dialect)

    @staticmethod
    def assess_risk(
        current: Mapping[str, Any],
        target_columns: Sequence[Mapping[str, Any]],
        dialect: str,
        diff: Mapping[str, Any],
        row_count: int | None,
    ) -> list[dict[str, Any]]:
        return assess_risk(current, target_columns, dialect, diff, row_count)

    @staticmethod
    def build_plan(
        table_name: str,
        current: Mapping[str, Any],
        target_columns: Sequence[Mapping[str, Any]],
        target_indexes: Sequence[Mapping[str, Any]],
        diff: Mapping[str, Any],
        dialect: str,
        backup: bool,
        timestamp: str | None = None,
    ) -> dict[str, Any]:
        return build_plan(
            table_name,
            current,
            target_columns,
            target_indexes,
            diff,
            dialect,
            backup,
            timestamp,
        )

    @staticmethod
    def target_fingerprint(
        columns: Sequence[Mapping[str, Any]],
        indexes: Sequence[Mapping[str, Any]],
    ) -> str:
        return schema_spec.structure_fingerprint(columns, indexes)

    @staticmethod
    def orm_suggestion(table_name: str) -> dict[str, Any] | None:
        """把已注册 ORM 模型翻译成编辑器草稿初值。

        只作为「从 ORM 建议…」按钮的预填内容：用户仍需在编辑器里确认并显式
        执行，本方法不产生任何自动同步。模型类型不在白名单内时返回 None。
        """
        model = registered_orm_model_by_table_name(table_name)
        if model is None:
            return None
        table = getattr(model, "__table__", None)
        if table is None:
            return None

        columns: list[dict[str, Any]] = []
        for column in table.columns:
            mapped = schema_spec.describe_orm_type(column.type)
            if mapped is None:
                return None
            column_type, type_args = mapped
            columns.append({
                "name": str(column.name),
                "original_name": None,
                "type": column_type,
                "type_args": type_args,
                "nullable": bool(column.nullable),
                "primary_key": bool(column.primary_key),
                "autoincrement": bool(
                    column.primary_key and column.autoincrement is True
                ),
                "server_default": schema_spec.normalize_orm_default(
                    column.server_default
                ),
                "unique": bool(column.unique),
                "indexed": bool(column.index),
                "comment": column.comment or None,
            })

        indexes: list[dict[str, Any]] = []
        seen: set[tuple[tuple[str, ...], bool]] = set()
        for column in table.columns:
            if not (column.unique or column.index):
                continue
            signature = ((str(column.name),), bool(column.unique))
            if signature in seen:
                continue
            seen.add(signature)
            indexes.append({
                "name": None,
                "columns": [str(column.name)],
                "unique": bool(column.unique),
                "primary": False,
            })
        for index in table.indexes:
            names = tuple(str(column.name) for column in index.columns)
            signature = (names, bool(index.unique))
            if signature in seen:
                continue
            seen.add(signature)
            indexes.append({
                "name": None,
                "columns": list(names),
                "unique": bool(index.unique),
                "primary": False,
            })
        return {"columns": columns, "indexes": indexes}

    @staticmethod
    def _dialect_of(storage: Any) -> str:
        return str(storage.engine.dialect.name or "").strip().lower()

    @staticmethod
    def _structure_fingerprint(current: Mapping[str, Any]) -> str:
        return schema_spec.structure_fingerprint(
            list(current.get("columns") or ()),
            list(current.get("indexes") or ()),
        )

    @staticmethod
    async def describe(storage: Any, table_name: str) -> dict[str, Any]:
        """读取当前结构、方言能力、指纹与 ORM 建议初值。"""
        name = schema_spec.normalize_identifier(table_name)
        dialect = DatabaseTableSchemaHub._dialect_of(storage)
        current = await database_ddl.read_table_schema(storage.engine, name)
        return {
            "table_name": name,
            "dialect": dialect,
            "table_exists": bool(current.get("exists")),
            "registered": registered_orm_model_by_table_name(name) is not None,
            "row_count": current.get("row_count"),
            "columns": list(current.get("columns") or ()),
            "indexes": list(current.get("indexes") or ()),
            "capabilities": capabilities_of(dialect),
            "structure_fingerprint": DatabaseTableSchemaHub._structure_fingerprint(
                current
            ),
            "orm_suggestion": DatabaseTableSchemaHub.orm_suggestion(name),
        }

    @staticmethod
    async def preview(
        storage: Any,
        *,
        table_name: str,
        columns: Sequence[Mapping[str, Any]],
        indexes: Sequence[Mapping[str, Any]],
        backup: bool,
    ) -> dict[str, Any]:
        """重读当前结构并计算差异、风险与执行计划。

        确认级风险里的探针会先执行只读计数，把真实受影响行数回填；计数为 0
        的风险项自动消失，用户不需要为不存在的数据风险勾选确认。
        """
        name = schema_spec.normalize_identifier(table_name)
        dialect = DatabaseTableSchemaHub._dialect_of(storage)
        current = await database_ddl.read_table_schema(storage.engine, name)
        target_columns, target_indexes = schema_spec.normalize_specification(
            list(columns), list(indexes)
        )
        diff = build_diff(current, target_columns, target_indexes, dialect)
        row_count = current.get("row_count")
        raw_risks = assess_risk(
            current, target_columns, dialect, diff, row_count
        )

        probes = probe_sequence(raw_risks)
        measured = await database_ddl.measure_probes(
            storage.engine, name, probes
        )
        risks = resolve_risk_probes(raw_risks, measured)

        fingerprint = DatabaseTableSchemaHub._structure_fingerprint(current)
        plan = None
        if diff.get("has_changes"):
            plan = build_plan(
                name,
                current,
                target_columns,
                target_indexes,
                diff,
                dialect,
                backup=backup,
            )

        mode = decide_mode(risks)
        return {
            "table_name": name,
            "mode": mode,
            "statements": (
                database_ddl.render_statements(plan)
                if plan is not None and mode == MODE_AUTO
                else []
            ),
            "manual_plan": (
                {
                    "precheck": database_ddl.render_precheck(plan),
                    "changes": database_ddl.render_statements(plan),
                    "rollback": database_ddl.render_rollback(plan),
                }
                if plan is not None
                else {
                    "precheck": [],
                    "changes": [],
                    "rollback": [],
                }
            ),
            "risk_items": risks,
            "estimated_rows": row_count,
            "plan_summary": dict(diff.get("plan_summary") or {}),
            "structure_fingerprint": fingerprint,
        }

    @staticmethod
    async def apply(
        storage: Any,
        *,
        table_name: str,
        confirm_table_name: str,
        expected_fingerprint: str,
        columns: Sequence[Mapping[str, Any]],
        indexes: Sequence[Mapping[str, Any]],
        backup: bool,
        acknowledged_risk_ids: Sequence[str],
    ) -> dict[str, Any]:
        """校验并执行结构变更。

        任何一项校验不通过都必须先失败、再动 DDL：表名确认、结构指纹、
        未被确认的风险项、必须手动处理的路径。``apply`` 不信任 ``preview``
        的语句，而是按提交的结构重新计算一次完整计划。
        """
        started = perf_counter()
        name = schema_spec.normalize_identifier(table_name)
        if confirm_table_name.strip() != name:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_CONFIRM_MISMATCH_ERROR
            )

        dialect = DatabaseTableSchemaHub._dialect_of(storage)
        current = await database_ddl.read_table_schema(storage.engine, name)
        fingerprint = DatabaseTableSchemaHub._structure_fingerprint(current)
        if fingerprint != expected_fingerprint.strip():
            raise KmvException(error=database_table_exc.SCHEMA_STALE_ERROR)

        target_columns, target_indexes = schema_spec.normalize_specification(
            list(columns), list(indexes)
        )
        diff = build_diff(current, target_columns, target_indexes, dialect)
        if not diff.get("has_changes"):
            return {
                "table_name": name,
                "success": True,
                "executed_statements": [],
                "backup_table": None,
                "duration_ms": int((perf_counter() - started) * 1000),
            }

        row_count = current.get("row_count")
        raw_risks = assess_risk(
            current, target_columns, dialect, diff, row_count
        )
        # 与 preview 使用同一套探针口径：先测量再解析。否则需要确认的数据
        # 风险会因为「未计数」被静默丢弃，等于绕过用户逐项勾选。
        measured = await database_ddl.measure_probes(
            storage.engine, name, probe_sequence(raw_risks)
        )
        risks = resolve_risk_probes(raw_risks, measured)
        if decide_mode(risks) == MODE_MANUAL:
            raise KmvException(
                error=database_table_exc.SCHEMA_MANUAL_REQUIRED_ERROR
            )

        acknowledged = {str(value) for value in acknowledged_risk_ids}
        for risk in risks:
            if risk.get("level") != LEVEL_CONFIRM:
                continue
            if str(risk.get("code")) in acknowledged:
                continue
            raise KmvException(
                error=database_table_exc.SCHEMA_SPEC_INVALID_ERROR
            )

        plan = build_plan(
            name,
            current,
            target_columns,
            target_indexes,
            diff,
            dialect,
            backup=backup,
        )
        statements = database_ddl.render_statements(plan)
        try:
            executed = await database_ddl.execute_statements(
                storage.engine, statements
            )
        except KmvException:
            raise
        except Exception as error:  # noqa: BLE001
            logger.warning(
                "执行表结构变更失败 table=%s: %s", name, error, exc_info=error
            )
            raise KmvException(
                error=database_table_exc.SCHEMA_APPLY_FAILED_ERROR
            ) from error

        return {
            "table_name": name,
            "success": True,
            "executed_statements": executed,
            "backup_table": plan.get("backup_table"),
            "duration_ms": int((perf_counter() - started) * 1000),
        }