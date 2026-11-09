# coding: utf-8
"""表结构定义的白名单校验与规范化（纯计算，无 IO）。

「编辑结构」允许管理员直接提交列与索引定义，本模块是唯一的输入收窄点：

- 列类型只允许 :data:`COLUMN_TYPES` 枚举，类型参数按类型分别校验；
- 表名、列名、索引名只允许 ``^[a-z][a-z0-9_]{0,62}$``；
- 默认值只允许 ``NULL``、数字、``'字面量'``、``now()``、
  ``CURRENT_TIMESTAMP``、``true``、``false``；
- 索引清单是唯一权威：列上的 ``unique`` / ``indexed`` 由索引反算，
  避免同一事实存在两处来源而互相冲突。

本模块不做 IO、不读配置、不访问 ORM、不定义错误三元组；校验失败统一抛
``SCHEMA_SPEC_INVALID_ERROR``（46008）。
"""

from __future__ import annotations

import hashlib
import json
import re
from collections.abc import Mapping, Sequence
from typing import Any

from kmvpy.common.exception.kmv_exception import KmvException

from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc

# 允许编辑的列类型白名单；顺序即前端下拉的展示顺序。
COLUMN_TYPES: tuple[str, ...] = (
    "int",
    "bigint",
    "smallint",
    "varchar",
    "text",
    "datetime",
    "boolean",
    "numeric",
)

# 整型家族：相互之间可以比较宽窄，也允许自增。
INTEGER_TYPES: tuple[str, ...] = ("smallint", "int", "bigint")

# 标识符规则：小写字母开头，仅含小写字母、数字与下划线，最长 63。
_IDENTIFIER_PATTERN = r"^[a-z][a-z0-9_]{0,62}$"
_IDENTIFIER_RE = re.compile(_IDENTIFIER_PATTERN)

_VARCHAR_MAX_LENGTH = 65535
_NUMERIC_MAX_PRECISION = 65
_COMMENT_MAX_LENGTH = 1024
_DEFAULT_LITERAL_MAX_LENGTH = 255

# 整型的宽窄次序，数值越大表示可容纳范围越宽。
_INTEGER_RANK: dict[str, int] = {"smallint": 1, "int": 2, "bigint": 3}

# 默认值中的数字形态：最多 18 位整数、6 位小数。
_DEFAULT_NUMBER_RE = re.compile(r"^-?\d{1,18}(?:\.\d{1,6})?$")

_KEYWORD_DEFAULTS = frozenset({"now()", "current_timestamp"})
_BOOLEAN_DEFAULTS = frozenset({"true", "false"})

# 类型变更的三分类：同宽、放宽、收窄/重建。
TYPE_CHANGE_SAME = "same"
TYPE_CHANGE_WIDEN = "widen"
TYPE_CHANGE_NARROW = "narrow"
TYPE_CHANGE_REBUILD = "rebuild"


def _invalid() -> KmvException:
    """构造统一的「结构定义不合法」异常（46008）。"""
    return KmvException(error=database_table_exc.SCHEMA_SPEC_INVALID_ERROR)


def is_identifier_valid(value: Any) -> bool:
    """判断标识符是否符合白名单规则；用于检查数据库里的既有名字。"""
    return isinstance(value, str) and bool(_IDENTIFIER_RE.match(value.strip()))


def normalize_identifier(value: Any) -> str:
    """规范化目标标识符；不合规立即失败，绝不猜测或静默修正。"""
    if not isinstance(value, str):
        raise _invalid()
    name = value.strip().lower()
    if not _IDENTIFIER_RE.match(name):
        raise _invalid()
    return name


def normalize_server_default(raw: Any) -> str | None:
    """把各种书写形态的默认值归一成稳定字符串。

    ``None`` 表示无默认值；关键字与布尔保留原样；字符串字面量去掉外层
    单引号，数字保留原样。归一结果参与指纹计算与 SQL 渲染，因此对同一
    语义的多种写法必须产出同一结果。
    """
    if raw is None:
        return None
    if isinstance(raw, bool):
        return "true" if raw else "false"

    text_value = str(raw).strip()
    if not text_value:
        return None

    lowered = text_value.lower()
    if lowered == "null":
        return None
    if lowered in _KEYWORD_DEFAULTS:
        # CURRENT_TIMESTAMP 统一归一为 now()，两者语义等价。
        return "now()"
    if lowered in _BOOLEAN_DEFAULTS:
        return lowered
    if len(text_value) >= 2 and text_value.startswith("'"):
        if not text_value.endswith("'"):
            raise _invalid()
        return _normalize_default_literal(text_value[1:-1])
    if _DEFAULT_NUMBER_RE.match(text_value):
        return text_value
    raise _invalid()


def _normalize_default_literal(inner: str) -> str:
    """校验字符串字面量内容：不允许引号、反斜杠与控制字符。"""
    if len(inner) > _DEFAULT_LITERAL_MAX_LENGTH:
        raise _invalid()
    if "'" in inner or "\\" in inner:
        raise _invalid()
    if any(ord(char) < 0x20 for char in inner):
        raise _invalid()
    return inner


def default_kind(value: str | None) -> str:
    """返回默认值的渲染类别：none / keyword / boolean / literal。"""
    if value is None:
        return "none"
    lowered = value.strip().lower()
    if lowered in _KEYWORD_DEFAULTS:
        return "keyword"
    if lowered in _BOOLEAN_DEFAULTS:
        return "boolean"
    return "literal"


def _as_int(value: Any) -> int:
    """只接受真正的整数，拒绝 bool 与字符串。"""
    if isinstance(value, bool) or not isinstance(value, int):
        raise _invalid()
    return value


def _normalize_type_args(
    column_type: str,
    raw_args: Any,
) -> list[int] | None:
    """按类型校验并规范化 ``type_args``。"""
    if column_type == "varchar":
        if raw_args is None:
            return None
        args = [_as_int(value) for value in raw_args]
        if len(args) != 1 or not 1 <= args[0] <= _VARCHAR_MAX_LENGTH:
            raise _invalid()
        return args

    if column_type == "numeric":
        if raw_args is None:
            return None
        args = [_as_int(value) for value in raw_args]
        if len(args) != 2:
            raise _invalid()
        precision, scale = args
        if not 1 <= precision <= _NUMERIC_MAX_PRECISION:
            raise _invalid()
        if not 0 <= scale <= precision:
            raise _invalid()
        return args

    if raw_args:
        # 其它类型不接受参数，避免拼出非法类型声明。
        raise _invalid()
    return None


def normalize_column(raw: Mapping[str, Any]) -> dict[str, Any]:
    """规范化单列定义。"""
    name = normalize_identifier(raw.get("name"))

    original_raw = raw.get("original_name")
    original_name = normalize_identifier(original_raw) if original_raw else None
    if original_name == name:
        # 改名入口未改动名字时按「未改名」处理，避免误判为删除 + 新增。
        original_name = None

    column_type = str(raw.get("type") or "").strip().lower()
    if column_type not in COLUMN_TYPES:
        raise _invalid()
    type_args = _normalize_type_args(column_type, raw.get("type_args"))

    primary_key = bool(raw.get("primary_key"))
    autoincrement = bool(raw.get("autoincrement"))
    if autoincrement and not primary_key:
        raise _invalid()
    if autoincrement and column_type not in INTEGER_TYPES:
        raise _invalid()

    comment = str(raw.get("comment") or "").strip() or None
    if comment is not None:
        comment = comment[:_COMMENT_MAX_LENGTH]

    return {
        "name": name,
        "original_name": original_name,
        "type": column_type,
        "type_args": type_args,
        "nullable": bool(raw.get("nullable", True)),
        "primary_key": primary_key,
        "autoincrement": autoincrement,
        "server_default": normalize_server_default(raw.get("server_default")),
        "unique": bool(raw.get("unique")),
        "indexed": bool(raw.get("indexed")),
        "comment": comment,
    }


def _normalize_index(
    raw: Mapping[str, Any],
    column_names: frozenset[str],
) -> dict[str, Any]:
    """规范化单个索引定义；``name`` 允许为空，表示交给数据库生成。"""
    raw_name = raw.get("name")
    name = normalize_identifier(raw_name) if raw_name else None

    raw_columns = raw.get("columns") or []
    if not isinstance(raw_columns, Sequence) or isinstance(raw_columns, str):
        raise _invalid()
    columns = [normalize_identifier(value) for value in raw_columns]
    if not columns:
        raise _invalid()
    for column in columns:
        if column not in column_names:
            raise _invalid()
    if len(set(columns)) != len(columns):
        raise _invalid()

    return {
        "name": name,
        "columns": columns,
        "unique": bool(raw.get("unique")),
        "primary": bool(raw.get("primary")),
    }


def _check_column_identity(columns: list[dict[str, Any]]) -> None:
    """校验列名与改名来源不重复，避免列映射产生歧义。"""
    seen_names: set[str] = set()
    seen_originals: set[str] = set()
    for column in columns:
        name = column["name"]
        if name in seen_names:
            raise _invalid()
        seen_names.add(name)

        original = column.get("original_name")
        if original is None:
            continue
        if original in seen_originals:
            raise _invalid()
        seen_originals.add(original)
        if original in seen_names:
            # 同一列既被新列占用、又被声明为改名来源，映射不唯一。
            raise _invalid()


def _apply_index_flags(
    columns: list[dict[str, Any]],
    indexes: list[dict[str, Any]],
) -> None:
    """以索引清单为唯一权威，反算列上的 unique / indexed 标记。"""
    by_name = {column["name"]: column for column in columns}
    for column in columns:
        column["unique"] = False
        column["indexed"] = False
    for index in indexes:
        for name in index["columns"]:
            column = by_name.get(name)
            if column is None:
                continue
            column["indexed"] = True
            if index["unique"] and len(index["columns"]) == 1:
                column["unique"] = True


def normalize_specification(
    columns: Sequence[Mapping[str, Any]],
    indexes: Sequence[Mapping[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """规范化整套目标结构，返回 ``(columns, indexes)``。

    索引清单是唯一权威：请求里列上的 ``unique`` / ``indexed`` 会被索引
    反算覆盖。主键索引不进入返回的索引清单，由列的主键标记表达。
    """
    normalized_columns = [normalize_column(column) for column in columns]
    if not normalized_columns:
        raise _invalid()
    _check_column_identity(normalized_columns)

    primary_columns = [
        column["name"] for column in normalized_columns if column["primary_key"]
    ]
    if len(primary_columns) > 1:
        # 现有 7 张表都是单列主键，不引入复合主键支持。
        raise _invalid()
    primary_name = primary_columns[0] if primary_columns else None

    column_names = frozenset(column["name"] for column in normalized_columns)

    collected: list[dict[str, Any]] = []
    seen_signature: set[tuple[tuple[str, ...], bool]] = set()
    seen_index_name: dict[str, tuple[tuple[str, ...], bool]] = {}

    for raw_index in indexes:
        index = _normalize_index(raw_index, column_names)
        if index["primary"]:
            expected = [primary_name] if primary_name else []
            if index["columns"] != expected:
                raise _invalid()
            continue

        signature = (tuple(index["columns"]), index["unique"])
        name = index["name"]
        if name is not None:
            previous = seen_index_name.get(name)
            if previous is not None and previous != signature:
                # 同名索引指向不同定义，无法安全重建。
                raise _invalid()
            seen_index_name[name] = signature
        if signature in seen_signature:
            # 完全等价的索引去重，避免重复建索引。
            continue
        seen_signature.add(signature)
        collected.append(index)

    _apply_index_flags(normalized_columns, collected)
    return normalized_columns, collected


def _varchar_length(type_args: Sequence[int] | None) -> int | None:
    if not type_args:
        return None
    return int(type_args[0])


def classify_type_change(
    current: Mapping[str, Any],
    target: Mapping[str, Any],
) -> str:
    """比较两列的类型，返回 same / widen / narrow / rebuild。

    只有明确不缩小可容纳范围才算放宽；整型与 varchar/text 之外的跨类型
    变更一律视为需要重建（``rebuild``），由调用方按 confirm 处理。
    """
    current_type = str(current.get("type") or "")
    target_type = str(target.get("type") or "")
    current_args = current.get("type_args") or []

    if current_type == target_type:
        if current_type == "varchar":
            current_length = _varchar_length(current_args)
            target_length = _varchar_length(target.get("type_args"))
            if current_length == target_length:
                return TYPE_CHANGE_SAME
            if target_length is None:
                return TYPE_CHANGE_WIDEN
            if current_length is None:
                return TYPE_CHANGE_NARROW
            if target_length > current_length:
                return TYPE_CHANGE_WIDEN
            return TYPE_CHANGE_NARROW

        if current_type == "numeric":
            current_pair = list(current_args)
            target_pair = list(target.get("type_args") or [])
            if current_pair == target_pair:
                return TYPE_CHANGE_SAME
            if len(current_pair) != 2 or len(target_pair) != 2:
                return TYPE_CHANGE_REBUILD
            wider = (
                target_pair[0] >= current_pair[0]
                and target_pair[1] >= current_pair[1]
            )
            return TYPE_CHANGE_WIDEN if wider else TYPE_CHANGE_NARROW

        return TYPE_CHANGE_SAME

    if current_type in _INTEGER_RANK and target_type in _INTEGER_RANK:
        if _INTEGER_RANK[target_type] > _INTEGER_RANK[current_type]:
            return TYPE_CHANGE_WIDEN
        return TYPE_CHANGE_NARROW

    if current_type == "varchar" and target_type == "text":
        return TYPE_CHANGE_WIDEN
    if current_type == "text" and target_type == "varchar":
        return TYPE_CHANGE_NARROW

    return TYPE_CHANGE_REBUILD


def describe_orm_type(sa_type: Any) -> tuple[str, list[int] | None] | None:
    """把 ORM 列类型翻译成白名单枚举；无法映射时返回 None。

    这里只用于「从 ORM 建议…」的草稿初值，不参与执行；映射不出来就
    不推荐该表，避免给出无法执行的结构。
    """
    from sqlalchemy import (
        BigInteger,
        Boolean,
        DateTime,
        Integer,
        Numeric,
        SmallInteger,
        String,
        Text,
    )

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


def normalize_orm_default(default: Any) -> str | None:
    """把 ORM 的 ``server_default`` 翻译成白名单默认值。

    ``func.now()``、``text("'0'")``、``true()`` 三种形态都要能识别；
    识别不了的返回 None，表示不推荐任何默认值，绝不猜。
    """
    if default is None:
        return None
    argument = getattr(default, "arg", default)
    compiled = getattr(argument, "text", None)
    if compiled is None:
        compiled = str(argument)
    try:
        return normalize_server_default(compiled)
    except KmvException:
        return None


def structure_fingerprint(
    columns: Sequence[Mapping[str, Any]],
    indexes: Sequence[Mapping[str, Any]],
) -> str:
    """由已规范化的结构生成稳定指纹，用于并发变更保护。

    列顺序参与计算（列顺序是结构事实），索引先排序再计算，因此索引在
    请求中的先后不影响结果。``comment`` 与列级 ``unique`` / ``indexed``
    不参与计算：前者不是结构约束，后者由索引派生。
    """
    column_payload = [
        [
            column.get("name"),
            column.get("type"),
            list(column.get("type_args") or []) or None,
            bool(column.get("nullable")),
            bool(column.get("primary_key")),
            bool(column.get("autoincrement")),
            column.get("server_default"),
        ]
        for column in columns
    ]
    index_payload = sorted(
        (
            str(index.get("name") or ""),
            list(index.get("columns") or []),
            bool(index.get("unique")),
        )
        for index in indexes
        if not index.get("primary")
    )
    serialized = json.dumps(
        {"columns": column_payload, "indexes": index_payload},
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return hashlib.sha256(serialized.encode("utf-8")).hexdigest()