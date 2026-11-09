# coding: utf-8
"""表结构编辑的阶段 1 单元测试：白名单、差异、风险与计划（纯逻辑）。

运行方式（在 __PY_PROJECT_NAME__ 下）：

    PYTHONPATH=. python -m unittest discover -s tests -p "test_database_table_schema*.py"

本模块不连接数据库：只验证 ``schema_spec`` 与 ``DatabaseTableSchemaHub`` 的
纯计算行为，DDL 渲染与真机执行在 ``test_database_table_schema_ddl.py`` 中。
"""

import unittest

from kmvpy.common.exception.kmv_exception import KmvException

from __PROJECT_NAME__.common.infra.orm import schema_spec
from __PROJECT_NAME__.core.main.hub.database_table_schema import (
    LEVEL_BLOCKING,
    LEVEL_CONFIRM,
    MODE_AUTO,
    MODE_MANUAL,
    PATH_ALTER,
    PATH_REBUILD,
    RISK_COLUMN_REORDER,
    RISK_DROP_COLUMN,
    RISK_IDENTIFIER_INVALID,
    RISK_NON_ATOMIC_DIALECT,
    RISK_NOT_NULL_WITH_NULLS,
    RISK_REBUILD_TABLE,
    RISK_TYPE_NARROWING,
    RISK_UNIQUE_WITH_DUPLICATES,
    DatabaseTableSchemaHub,
    backup_table_name,
    capabilities_of,
    decide_mode,
    probe_sequence,
    resolve_risk_probes,
)

TABLE = "work_ticket"


def _column(
    name,
    column_type="bigint",
    *,
    type_args=None,
    original_name=None,
    nullable=False,
    primary_key=False,
    autoincrement=False,
    server_default=None,
    comment=None,
):
    return {
        "name": name,
        "original_name": original_name,
        "type": column_type,
        "type_args": type_args,
        "nullable": nullable,
        "primary_key": primary_key,
        "autoincrement": autoincrement,
        "server_default": server_default,
        "unique": False,
        "indexed": False,
        "comment": comment,
    }


def _current(
    *,
    columns,
    indexes=(),
    table_name=TABLE,
    exists=True,
    row_count=0,
):
    return {
        "table_name": table_name,
        "exists": exists,
        "comment": None,
        "row_count": row_count,
        "columns": list(columns),
        "indexes": list(indexes),
    }


def _base_current_columns():
    """与 work_ticket 骨架一致的当前列。"""
    return [
        _column("id", "bigint", primary_key=True, autoincrement=True),
        _column("kid", "bigint"),
        _column("title", "varchar", type_args=[255]),
        _column("seq", "int", nullable=True, server_default="0"),
        _column("create_time", "datetime", server_default="now()"),
    ]


def _base_current_indexes():
    return [
        {"name": "kid_uq", "columns": ["kid"], "unique": True, "primary": False},
        {"name": "pk_work_ticket", "columns": ["id"], "unique": True, "primary": True},
    ]


def _target_from_current(columns=None, indexes=None):
    """把当前结构复制成目标结构（保持列级标记由索引反算）。"""
    source_columns = columns if columns is not None else _base_current_columns()
    source_indexes = (
        indexes if indexes is not None else _base_current_indexes()
    )
    normalized_columns, normalized_indexes = (
        DatabaseTableSchemaHub.normalize_spec(source_columns, source_indexes)
    )
    return normalized_columns, normalized_indexes


class SchemaSpecTests(unittest.TestCase):
    """标识符、类型参数与默认值白名单。"""

    def test_invalid_identifier_rejected(self):
        for bad in ["1abc", "UPPER", "a-b", "a b", "", "x" * 64, "表名"]:
            with self.subTest(bad=bad):
                with self.assertRaises(KmvException) as ctx:
                    schema_spec.normalize_identifier(bad)
                self.assertEqual(ctx.exception.error[0], 46008)

    def test_valid_identifier_accepted(self):
        self.assertEqual(schema_spec.normalize_identifier(" Kid_2 "), "kid_2")
        self.assertTrue(schema_spec.is_identifier_valid("a" * 63))

    def test_default_whitelist_normalization(self):
        cases = {
            None: None,
            "NULL": None,
            "now()": "now()",
            "CURRENT_TIMESTAMP": "now()",
            "TRUE": "true",
            "false": "false",
            "'0'": "0",
            "'+86'": "+86",
            "-12.5": "-12.5",
        }
        for raw, expected in cases.items():
            with self.subTest(raw=raw):
                self.assertEqual(schema_spec.normalize_server_default(raw), expected)

    def test_illegal_default_rejected(self):
        for bad in ["random()", "'a''b'", "1; DROP TABLE x", "'a\\b'", "(select 1)"]:
            with self.subTest(bad=bad):
                with self.assertRaises(KmvException) as ctx:
                    schema_spec.normalize_server_default(bad)
                self.assertEqual(ctx.exception.error[0], 46008)

    def test_type_args_rules(self):
        columns, _ = DatabaseTableSchemaHub.normalize_spec(
            [
                _column("a", "varchar", type_args=[64]),
                _column("b", "numeric", type_args=[18, 6], nullable=True),
                _column("c", "bigint"),
            ],
            [],
        )
        self.assertEqual(columns[0]["type_args"], [64])
        self.assertEqual(columns[1]["type_args"], [18, 6])
        self.assertIsNone(columns[2]["type_args"])

        for bad_column in [
            _column("a", "varchar", type_args=[0]),
            _column("a", "varchar", type_args=[1, 2]),
            _column("a", "numeric", type_args=[6, 18]),
            _column("a", "bigint", type_args=[3]),
            _column("a", "unknown"),
        ]:
            with self.subTest(column=bad_column):
                with self.assertRaises(KmvException):
                    DatabaseTableSchemaHub.normalize_spec([bad_column], [])

    def test_autoincrement_requires_primary_integer(self):
        with self.assertRaises(KmvException):
            DatabaseTableSchemaHub.normalize_spec(
                [_column("a", "bigint", autoincrement=True)], []
            )
        with self.assertRaises(KmvException):
            DatabaseTableSchemaHub.normalize_spec(
                [_column("a", "varchar", primary_key=True, autoincrement=True,
                         type_args=[8])],
                [],
            )

    def test_index_flags_derived_from_index_list(self):
        """列级 unique/indexed 由索引清单反算，两处不会互相冲突。"""
        columns, indexes = DatabaseTableSchemaHub.normalize_spec(
            [
                _column("kid", "bigint", nullable=True),
                _column("code", "varchar", type_args=[16], nullable=True),
            ],
            [
                {"name": "kid_uq", "columns": ["kid"], "unique": True, "primary": False},
                {"name": "code_ix", "columns": ["code"], "unique": False, "primary": False},
            ],
        )
        self.assertEqual(len(indexes), 2)
        self.assertTrue(columns[0]["unique"])
        self.assertTrue(columns[0]["indexed"])
        self.assertFalse(columns[1]["unique"])
        self.assertTrue(columns[1]["indexed"])

    def test_duplicate_index_signature_deduplicated(self):
        _, indexes = DatabaseTableSchemaHub.normalize_spec(
            [_column("kid", "bigint")],
            [
                {"name": "kid_uq", "columns": ["kid"], "unique": True, "primary": False},
                {"name": "kid_uq2", "columns": ["kid"], "unique": True, "primary": False},
            ],
        )
        self.assertEqual(len(indexes), 1)

    def test_index_referencing_unknown_column_rejected(self):
        with self.assertRaises(KmvException):
            DatabaseTableSchemaHub.normalize_spec(
                [_column("kid", "bigint")],
                [{"name": "x", "columns": ["missing"], "unique": False, "primary": False}],
            )

    def test_fingerprint_stable_and_order_insensitive(self):
        columns = [_column("id", "bigint", primary_key=True, autoincrement=True),
                   _column("kid", "bigint")]
        first = schema_spec.structure_fingerprint(
            columns,
            [
                {"name": "i1", "columns": ["kid"], "unique": True, "primary": False},
                {"name": "i2", "columns": ["id"], "unique": False, "primary": False},
            ],
        )
        second = schema_spec.structure_fingerprint(
            columns,
            [
                {"name": "i2", "columns": ["id"], "unique": False, "primary": False},
                {"name": "i1", "columns": ["kid"], "unique": True, "primary": False},
            ],
        )
        self.assertEqual(first, second)

    def test_fingerprint_ignores_comment_and_derived_flags(self):
        base = [_column("kid", "bigint", comment=None)]
        changed = [_column("kid", "bigint", comment="说明")]
        changed[0]["unique"] = True
        self.assertEqual(
            schema_spec.structure_fingerprint(base, []),
            schema_spec.structure_fingerprint(changed, []),
        )

    def test_fingerprint_changes_on_structural_edit(self):
        base = [_column("kid", "bigint")]
        widened = [_column("kid", "bigint", nullable=True)]
        self.assertNotEqual(
            schema_spec.structure_fingerprint(base, []),
            schema_spec.structure_fingerprint(widened, []),
        )


class DiffTests(unittest.TestCase):
    """差异判定：改名、增删列与路径选择。"""

    def test_rename_is_not_drop_plus_add(self):
        columns = _base_current_columns()
        columns[3] = _column(
            "seq_no", "int", original_name="seq", nullable=True, server_default="0"
        )
        targets, indexes = _target_from_current(columns=columns)
        diff = DatabaseTableSchemaHub.build_diff(
            _current(columns=_base_current_columns(), indexes=_base_current_indexes()),
            targets,
            indexes,
            "postgresql",
        )
        self.assertEqual(len(diff["renamed_columns"]), 1)
        self.assertEqual(diff["dropped_columns"], [])
        self.assertEqual(diff["added_columns"], [])
        self.assertEqual(diff["renamed_columns"][0]["from_name"], "seq")
        self.assertEqual(diff["renamed_columns"][0]["to_name"], "seq_no")
        self.assertEqual(diff["path"], PATH_ALTER)

    def test_identical_structure_has_no_changes(self):
        targets, indexes = _target_from_current()
        diff = DatabaseTableSchemaHub.build_diff(
            _current(columns=_base_current_columns(), indexes=_base_current_indexes()),
            targets,
            indexes,
            "postgresql",
        )
        self.assertFalse(diff["has_changes"])
        self.assertEqual(diff["plan_summary"]["total"], 0)
        self.assertEqual(diff["path"], PATH_ALTER)

    def test_column_order_change_detected_as_reorder(self):
        columns = _base_current_columns()
        columns[2], columns[3] = columns[3], columns[2]
        targets, indexes = _target_from_current(columns=columns)
        diff = DatabaseTableSchemaHub.build_diff(
            _current(columns=_base_current_columns(), indexes=_base_current_indexes()),
            targets,
            indexes,
            "postgresql",
        )
        self.assertTrue(diff["reorder_required"])
        risks = DatabaseTableSchemaHub.assess_risk(
            _current(columns=_base_current_columns(), indexes=_base_current_indexes()),
            targets,
            "postgresql",
            diff,
            0,
        )
        self.assertIn(RISK_COLUMN_REORDER, [item["code"] for item in risks])
        self.assertEqual(decide_mode(risks), MODE_MANUAL)

    def test_index_rename_only_is_ignored(self):
        """仅索引改名、列集合与唯一性不变时视为未变更，避免无谓重建。"""
        indexes = _base_current_indexes()
        indexes[0] = {"name": "kid_uq_new", "columns": ["kid"], "unique": True,
                      "primary": False}
        targets, target_indexes = _target_from_current(indexes=indexes)
        diff = DatabaseTableSchemaHub.build_diff(
            _current(columns=_base_current_columns(), indexes=_base_current_indexes()),
            targets,
            target_indexes,
            "postgresql",
        )
        self.assertFalse(diff["has_changes"])
        self.assertEqual(diff["added_indexes"], [])
        self.assertEqual(diff["dropped_indexes"], [])


class RiskTests(unittest.TestCase):
    """风险分级：auto / confirm / manual。"""

    def _diff_and_risk(self, columns, indexes, dialect="postgresql", row_count=0):
        current = _current(
            columns=_base_current_columns(),
            indexes=_base_current_indexes(),
            row_count=row_count,
        )
        targets, target_indexes = _target_from_current(
            columns=columns, indexes=indexes
        )
        diff = DatabaseTableSchemaHub.build_diff(
            current, targets, target_indexes, dialect
        )
        risks = DatabaseTableSchemaHub.assess_risk(
            current, targets, dialect, diff, row_count
        )
        return diff, risks

    def test_widening_varchar_is_auto(self):
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[512])
        diff, risks = self._diff_and_risk(
            columns, _base_current_indexes(), row_count=10
        )
        self.assertEqual(diff["path"], PATH_ALTER)
        self.assertNotIn(RISK_TYPE_NARROWING, [item["code"] for item in risks])
        self.assertEqual(decide_mode(risks), MODE_AUTO)

    def test_narrowing_varchar_is_confirm(self):
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[64])
        _, risks = self._diff_and_risk(columns, _base_current_indexes())
        narrowing = [item for item in risks if item["code"] == RISK_TYPE_NARROWING]
        self.assertEqual(len(narrowing), 1)
        self.assertEqual(narrowing[0]["level"], LEVEL_CONFIRM)
        self.assertEqual(decide_mode(risks), MODE_AUTO)

    def test_narrowing_integer_is_confirm(self):
        columns = _base_current_columns()
        columns[0] = _column("id", "smallint", primary_key=True, autoincrement=True)
        _, risks = self._diff_and_risk(columns, _base_current_indexes())
        self.assertIn(RISK_TYPE_NARROWING, [item["code"] for item in risks])

    def test_widening_integer_is_rebuild_without_confirmation(self):
        columns = _base_current_columns()
        columns[3] = _column("seq", "bigint", nullable=True, server_default="0")
        diff, risks = self._diff_and_risk(columns, _base_current_indexes())
        self.assertEqual(diff["path"], PATH_REBUILD)
        codes = [item["code"] for item in risks]
        self.assertIn(RISK_REBUILD_TABLE, codes)
        self.assertNotIn(RISK_TYPE_NARROWING, codes)
        self.assertEqual(decide_mode(risks), MODE_AUTO)

    def test_primary_key_change_goes_rebuild(self):
        columns = _base_current_columns()
        columns[1] = _column("kid", "bigint", primary_key=True)
        columns[0] = _column("id", "bigint", autoincrement=False, nullable=False)
        diff, risks = self._diff_and_risk(columns, _base_current_indexes())
        self.assertTrue(diff["primary_changed"])
        self.assertEqual(diff["path"], PATH_REBUILD)
        self.assertEqual(decide_mode(risks), MODE_AUTO)

    def test_sqlite_column_change_goes_rebuild(self):
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[512])
        diff, _ = self._diff_and_risk(
            columns, _base_current_indexes(), dialect="sqlite"
        )
        self.assertEqual(diff["path"], PATH_REBUILD)

    def test_mysql_is_manual(self):
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[512])
        _, risks = self._diff_and_risk(
            columns, _base_current_indexes(), dialect="mysql"
        )
        codes = [item["code"] for item in risks]
        self.assertIn(RISK_NON_ATOMIC_DIALECT, codes)
        self.assertEqual(decide_mode(risks), MODE_MANUAL)
        self.assertTrue(
            any(item["level"] == LEVEL_BLOCKING for item in risks)
        )

    def test_drop_column_is_confirm(self):
        columns = _base_current_columns()[:4] + [_base_current_columns()[4]]
        del columns[3]
        _, risks = self._diff_and_risk(columns, _base_current_indexes(), row_count=42)
        dropped = [item for item in risks if item["code"] == RISK_DROP_COLUMN]
        self.assertEqual(len(dropped), 1)
        self.assertEqual(dropped[0]["affected_rows"], 42)
        self.assertEqual(decide_mode(risks), MODE_AUTO)

    def test_added_not_null_column_without_default_is_confirm(self):
        columns = _base_current_columns() + [_column("owner_kid", "bigint")]
        _, risks = self._diff_and_risk(columns, _base_current_indexes(), row_count=7)
        item = [i for i in risks if i["code"] == RISK_NOT_NULL_WITH_NULLS]
        self.assertEqual(len(item), 1)
        self.assertEqual(item[0]["affected_rows"], 7)

    def test_unique_index_has_probe(self):
        indexes = _base_current_indexes() + [
            {"name": "title_uq", "columns": ["title"], "unique": True, "primary": False}
        ]
        _, risks = self._diff_and_risk(_base_current_columns(), indexes)
        item = [i for i in risks if i["code"] == RISK_UNIQUE_WITH_DUPLICATES]
        self.assertEqual(len(item), 1)
        self.assertIsNone(item[0]["affected_rows"])
        probes = probe_sequence(risks)
        self.assertEqual(probes[0]["kind"], "duplicates")
        self.assertEqual(probes[0]["columns"], ["title"])

    def test_probe_with_zero_hits_removes_confirmation(self):
        indexes = _base_current_indexes() + [
            {"name": "title_uq", "columns": ["title"], "unique": True, "primary": False}
        ]
        _, risks = self._diff_and_risk(_base_current_columns(), indexes)
        resolved = resolve_risk_probes(risks, {0: 0})
        self.assertNotIn(
            RISK_UNIQUE_WITH_DUPLICATES, [item["code"] for item in resolved]
        )

    def test_probe_with_hits_fills_affected_rows(self):
        indexes = _base_current_indexes() + [
            {"name": "title_uq", "columns": ["title"], "unique": True, "primary": False}
        ]
        _, risks = self._diff_and_risk(_base_current_columns(), indexes)
        resolved = resolve_risk_probes(risks, {0: 3})
        item = [i for i in resolved if i["code"] == RISK_UNIQUE_WITH_DUPLICATES][0]
        self.assertEqual(item["affected_rows"], 3)
        self.assertNotIn("_probe", item)

    def test_large_table_lock_hint(self):
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[512])
        _, risks = self._diff_and_risk(
            columns, _base_current_indexes(), row_count=1_000_001
        )
        self.assertIn("LARGE_TABLE_LOCK", [item["code"] for item in risks])

    def test_identifier_invalid_from_database_is_blocking(self):
        current = _current(
            columns=[_column("Bad-Name", "bigint")],
            indexes=[],
        )
        targets, target_indexes = DatabaseTableSchemaHub.normalize_spec(
            [_column("bad_name", "bigint")], []
        )
        diff = DatabaseTableSchemaHub.build_diff(
            current, targets, target_indexes, "postgresql"
        )
        risks = DatabaseTableSchemaHub.assess_risk(
            current, targets, "postgresql", diff, 0
        )
        self.assertIn(RISK_IDENTIFIER_INVALID, [item["code"] for item in risks])
        self.assertEqual(decide_mode(risks), MODE_MANUAL)


class PlanTests(unittest.TestCase):
    """列映射与计划元数据。"""

    def test_column_mapping_covers_rename_add_and_drop(self):
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[255])
        columns[3] = _column(
            "seq_no", "int", original_name="seq", nullable=True, server_default="0"
        )
        columns.append(_column("owner_kid", "bigint", nullable=True))
        targets, indexes = _target_from_current(columns=columns, indexes=[])
        current = _current(columns=_base_current_columns(), indexes=_base_current_indexes())
        diff = DatabaseTableSchemaHub.build_diff(
            current, targets, indexes, "postgresql"
        )
        plan = DatabaseTableSchemaHub.build_plan(
            TABLE, current, targets, indexes, diff, "postgresql", True, "20250101000000"
        )
        mapping = {item["target"]: item["source"] for item in plan["column_mapping"]}
        self.assertEqual(mapping["seq_no"], "seq")
        self.assertEqual(mapping["owner_kid"], None)
        self.assertEqual(mapping["title"], "title")
        self.assertEqual(plan["backup_table"], "work_ticket__bak_20250101000000")
        self.assertEqual(plan["path"], PATH_REBUILD)

    def test_rebuild_always_has_backup_table(self):
        current = _current(columns=_base_current_columns(), indexes=_base_current_indexes())
        columns = _base_current_columns()
        columns[2] = _column("title", "varchar", type_args=[64])
        targets, indexes = _target_from_current(columns=columns)
        diff = DatabaseTableSchemaHub.build_diff(
            current, targets, indexes, "postgresql"
        )
        plan = DatabaseTableSchemaHub.build_plan(
            TABLE, current, targets, indexes, diff, "postgresql", False,
            "20250101000000",
        )
        self.assertEqual(plan["path"], PATH_REBUILD)
        self.assertEqual(plan["backup_table"], "work_ticket__bak_20250101000000")

    def test_backup_name_fits_identifier_limit(self):
        long_name = "t" * 63
        name = backup_table_name(long_name, "20250101000000")
        self.assertLessEqual(len(name), 63)
        self.assertTrue(name.endswith("__bak_20250101000000"))

    def test_capabilities_per_dialect(self):
        self.assertTrue(capabilities_of("postgresql")["atomic_ddl"])
        self.assertTrue(capabilities_of("sqlite")["atomic_ddl"])
        self.assertFalse(capabilities_of("mysql")["atomic_ddl"])
        for dialect in ("postgresql", "sqlite", "mysql"):
            self.assertFalse(capabilities_of(dialect)["reorder_column"])


if __name__ == "__main__":
    unittest.main()