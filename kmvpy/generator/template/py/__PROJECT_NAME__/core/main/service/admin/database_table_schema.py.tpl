# coding: utf-8
"""管理端表结构编辑服务。

只做三件事：取得配置声明的默认连接、按固定顺序调用 Hub、把结果映射成 DTO。
指纹比对、风险确认、方言能力判断等业务规则全部在
``DatabaseTableSchemaHub`` 内，本层不做任何业务分支。

默认连接由 ``DatabaseCatalogHub.default_storage()`` 统一提供：它只取应用已
初始化的单例并归一错误语义，不创建也不关闭资源，因此不接受任何连接参数，
也无法借此切换到配置文件之外的数据库。存储生命周期仍由应用启动与关闭管理。
"""

from typing import Any

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.common.dto.admin.database_table_schema import (
    AdminDatabaseTableSchemaApplyReq,
    AdminDatabaseTableSchemaApplyRes,
    AdminDatabaseTableSchemaCapabilitiesRes,
    AdminDatabaseTableSchemaColumnRes,
    AdminDatabaseTableSchemaIndexRes,
    AdminDatabaseTableSchemaManualPlanRes,
    AdminDatabaseTableSchemaPreviewReq,
    AdminDatabaseTableSchemaPreviewRes,
    AdminDatabaseTableSchemaReq,
    AdminDatabaseTableSchemaRes,
    AdminDatabaseTableSchemaRiskItemRes,
    AdminDatabaseTableSchemaSpecRes,
    AdminDatabaseTableSchemaStatementRes,
)
from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.core.main.hub.database_table_schema import DatabaseTableSchemaHub
from __PROJECT_NAME__.core.main.hub.database_catalog import DatabaseCatalogHub


class AdminDatabaseTableSchemaService:
    """表结构编辑的事务入口与 DTO 组装。"""

    @staticmethod
    def _column(raw: dict[str, Any]) -> AdminDatabaseTableSchemaColumnRes:
        return AdminDatabaseTableSchemaColumnRes(
            name=str(raw.get("name", "")),
            original_name=raw.get("original_name"),
            type=str(raw.get("type", "")),
            type_args=raw.get("type_args"),
            nullable=bool(raw.get("nullable", True)),
            primary_key=bool(raw.get("primary_key", False)),
            autoincrement=bool(raw.get("autoincrement", False)),
            server_default=raw.get("server_default"),
            unique=bool(raw.get("unique", False)),
            indexed=bool(raw.get("indexed", False)),
            comment=raw.get("comment"),
        )

    @staticmethod
    def _index(raw: dict[str, Any]) -> AdminDatabaseTableSchemaIndexRes:
        return AdminDatabaseTableSchemaIndexRes(
            name=raw.get("name"),
            columns=[str(name) for name in raw.get("columns") or []],
            unique=bool(raw.get("unique", False)),
            primary=bool(raw.get("primary", False)),
        )

    @staticmethod
    def _statement(raw: dict[str, Any]) -> AdminDatabaseTableSchemaStatementRes:
        return AdminDatabaseTableSchemaStatementRes(
            sql=str(raw.get("sql", "")),
            category=str(raw.get("category", "alter_table")),
            destructive=bool(raw.get("destructive", False)),
            statement_index=int(raw.get("statement_index", 0)),
        )

    @staticmethod
    def _statements(
        raw_items: list[dict[str, Any]],
    ) -> list[AdminDatabaseTableSchemaStatementRes]:
        return [
            AdminDatabaseTableSchemaService._statement(raw) for raw in raw_items
        ]

    @staticmethod
    def _risk(raw: dict[str, Any]) -> AdminDatabaseTableSchemaRiskItemRes:
        return AdminDatabaseTableSchemaRiskItemRes(
            code=str(raw.get("code", "")),
            level=str(raw.get("level", "info")),
            statement_index=raw.get("statement_index"),
            affected_rows=raw.get("affected_rows"),
        )

    @staticmethod
    def _spec(raw: dict[str, Any] | None) -> AdminDatabaseTableSchemaSpecRes | None:
        if not raw:
            return None
        return AdminDatabaseTableSchemaSpecRes(
            columns=[
                AdminDatabaseTableSchemaService._column(column)
                for column in raw.get("columns") or []
            ],
            indexes=[
                AdminDatabaseTableSchemaService._index(index)
                for index in raw.get("indexes") or []
            ],
        )

    @staticmethod
    async def describe_table(
        req: AdminDatabaseTableSchemaReq,
    ) -> AdminDatabaseTableSchemaRes:
        """读取当前结构、方言能力与 ORM 建议初值。"""
        storage = DatabaseCatalogHub.default_storage()
        try:
            data = await DatabaseTableSchemaHub.describe(storage, req.table_name)
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "读取表结构失败 table=%s: %s", req.table_name, exc, exc_info=exc
            )
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            ) from exc

        capabilities = data.get("capabilities") or {}
        return AdminDatabaseTableSchemaRes(
            table_name=str(data.get("table_name", req.table_name)),
            dialect=str(data.get("dialect", "")),
            table_exists=bool(data.get("table_exists", False)),
            registered=bool(data.get("registered", False)),
            row_count=data.get("row_count"),
            columns=[
                AdminDatabaseTableSchemaService._column(column)
                for column in data.get("columns") or []
            ],
            indexes=[
                AdminDatabaseTableSchemaService._index(index)
                for index in data.get("indexes") or []
            ],
            capabilities=AdminDatabaseTableSchemaCapabilitiesRes(
                atomic_ddl=bool(capabilities.get("atomic_ddl", False)),
                rename_column=bool(capabilities.get("rename_column", False)),
                alter_type=bool(capabilities.get("alter_type", False)),
                reorder_column=bool(capabilities.get("reorder_column", False)),
            ),
            structure_fingerprint=str(data.get("structure_fingerprint", "")),
            orm_suggestion=AdminDatabaseTableSchemaService._spec(
                data.get("orm_suggestion")
            ),
        )

    @staticmethod
    async def preview_schema(
        req: AdminDatabaseTableSchemaPreviewReq,
    ) -> AdminDatabaseTableSchemaPreviewRes:
        """权威复核目标结构，返回可自动执行或需手动处理的方案。"""
        storage = DatabaseCatalogHub.default_storage()
        try:
            data = await DatabaseTableSchemaHub.preview(
                storage,
                table_name=req.table_name,
                columns=[column.model_dump() for column in req.columns],
                indexes=[index.model_dump() for index in req.indexes],
                backup=req.backup,
            )
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "预览表结构变更失败 table=%s: %s",
                req.table_name,
                exc,
                exc_info=exc,
            )
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_OPERATION_FAILED_ERROR
            ) from exc

        manual = data.get("manual_plan")
        return AdminDatabaseTableSchemaPreviewRes(
            table_name=str(data.get("table_name", req.table_name)),
            mode=str(data.get("mode", "auto")),
            statements=AdminDatabaseTableSchemaService._statements(
                data.get("statements") or []
            ),
            manual_plan=(
                AdminDatabaseTableSchemaManualPlanRes(
                    precheck=AdminDatabaseTableSchemaService._statements(
                        manual.get("precheck") or []
                    ),
                    changes=AdminDatabaseTableSchemaService._statements(
                        manual.get("changes") or []
                    ),
                    rollback=AdminDatabaseTableSchemaService._statements(
                        manual.get("rollback") or []
                    ),
                )
                if manual
                else None
            ),
            risk_items=[
                AdminDatabaseTableSchemaService._risk(item)
                for item in data.get("risk_items") or []
            ],
            estimated_rows=data.get("estimated_rows"),
            plan_summary={
                str(key): int(value)
                for key, value in (data.get("plan_summary") or {}).items()
            },
            structure_fingerprint=str(data.get("structure_fingerprint", "")),
        )

    @staticmethod
    async def apply_schema(
        req: AdminDatabaseTableSchemaApplyReq,
    ) -> AdminDatabaseTableSchemaApplyRes:
        """执行结构变更；指纹不符、确认不完整或需手动处理时由 Hub 抛错。"""
        storage = DatabaseCatalogHub.default_storage()
        try:
            data = await DatabaseTableSchemaHub.apply(
                storage,
                table_name=req.table_name,
                confirm_table_name=req.confirm_table_name,
                expected_fingerprint=req.expected_fingerprint,
                columns=[column.model_dump() for column in req.columns],
                indexes=[index.model_dump() for index in req.indexes],
                backup=req.backup,
                acknowledged_risk_ids=list(req.acknowledged_risk_ids),
            )
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "执行表结构变更失败 table=%s: %s",
                req.table_name,
                exc,
                exc_info=exc,
            )
            raise KmvException(
                error=database_table_exc.SCHEMA_APPLY_FAILED_ERROR
            ) from exc

        return AdminDatabaseTableSchemaApplyRes(
            table_name=str(data.get("table_name", req.table_name)),
            success=bool(data.get("success", False)),
            executed_statements=[
                str(sql) for sql in data.get("executed_statements") or []
            ],
            backup_table=data.get("backup_table"),
            duration_ms=int(data.get("duration_ms", 0)),
        )