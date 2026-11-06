# coding: utf-8
"""管理端数据库表维护服务。

只使用配置声明的默认连接：不再接受自定义连接配置，也不提供跨库切换。
库名合法性判断统一由 DatabaseCatalogHub 承担。
"""

from contextlib import asynccontextmanager
from typing import Any, AsyncIterator

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.tool.logger import logger
from sqlalchemy.engine import make_url

from __PROJECT_NAME__.common.dto.admin.database_table import (
    AdminDatabaseTableActionReq,
    AdminDatabaseTableActionRes,
    AdminDatabaseTableColumnRes,
    AdminDatabaseTableIndexRes,
    AdminDatabaseTableRes,
    AdminDatabaseTablesListRes,
)
from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.database_connection import database_name_of
from __PROJECT_NAME__.common.infra.orm import (
    drop_database_table,
    inspect_database_tables,
    regenerate_database_table,
    registered_orm_model_by_table_name,
    registered_orm_models,
)
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.core.main.hub.database_catalog import DatabaseCatalogHub


class AdminDatabaseTableService:
    """在配置声明的数据库上查看与维护 ORM 注册表。"""

    @staticmethod
    @asynccontextmanager
    async def _default_storage() -> AsyncIterator[KOrmStorage]:
        """只暴露默认连接，不接受任何自定义连接或跨库切换。"""
        DatabaseCatalogHub.ensure_allowed_database(None)
        try:
            storage = DefaultStorage.instance()
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning("默认数据库连接不可用: %s", exc, exc_info=exc)
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            ) from exc
        yield storage

    @staticmethod
    def _connection_summary(storage: KOrmStorage) -> str:
        database_url = storage.database_config.url if storage.database_config else ""
        if not database_url:
            return ""
        return make_url(database_url).render_as_string(hide_password=True)

    @staticmethod
    def _table_from_raw(raw: dict[str, Any]) -> AdminDatabaseTableRes:
        columns = [
            AdminDatabaseTableColumnRes(
                name=str(column.get("name", "")),
                type=str(column.get("type", "")),
                nullable=bool(column.get("nullable", True)),
                primary_key=bool(column.get("primary_key", False)),
                indexed=bool(column.get("indexed", False)),
                unique=bool(column.get("unique", False)),
            )
            for column in raw.get("columns", [])
            if isinstance(column, dict)
        ]
        indexes = [
            AdminDatabaseTableIndexRes(
                name=str(index.get("name", "")),
                columns=[
                    str(name) for name in index.get("columns") or [] if name
                ],
                unique=bool(index.get("unique", False)),
                primary=bool(index.get("primary", False)),
            )
            for index in raw.get("indexes", [])
            if isinstance(index, dict)
        ]
        row_count = raw.get("row_count")
        return AdminDatabaseTableRes(
            table_name=str(raw.get("table_name", "")),
            registered=bool(raw.get("registered", False)),
            comment=(
                raw.get("comment") if isinstance(raw.get("comment"), str) else None
            ),
            row_count=row_count if isinstance(row_count, int) else None,
            column_count=len(columns),
            columns=columns,
            indexes=indexes,
        )

    @staticmethod
    def _ensure_confirmed(req: AdminDatabaseTableActionReq) -> None:
        if req.table_name.strip() != req.confirm_table_name.strip():
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_CONFIRM_MISMATCH_ERROR
            )

    @staticmethod
    async def list_tables() -> AdminDatabaseTablesListRes:
        async with AdminDatabaseTableService._default_storage() as storage:
            try:
                raw_tables = await inspect_database_tables(storage)
            except KmvException:
                raise
            except Exception as exc:  # noqa: BLE001
                logger.warning("读取数据库表失败: %s", exc, exc_info=exc)
                raise KmvException(
                    error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
                ) from exc

            items = [
                AdminDatabaseTableService._table_from_raw(raw) for raw in raw_tables
            ]
            return AdminDatabaseTablesListRes(
                items=items,
                total=len(items),
                dialect=storage.engine.dialect.name,
                connection_summary=AdminDatabaseTableService._connection_summary(
                    storage
                ),
                database_name=database_name_of(storage.database_config),
                registered_table_count=len(registered_orm_models()),
            )

    @staticmethod
    async def drop_table(
        req: AdminDatabaseTableActionReq,
    ) -> AdminDatabaseTableActionRes:
        AdminDatabaseTableService._ensure_confirmed(req)
        table_name = req.table_name.strip()
        async with AdminDatabaseTableService._default_storage() as storage:
            try:
                dropped = await drop_database_table(table_name, storage)
            except KmvException:
                raise
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "删除数据库表失败 table=%s: %s",
                    table_name,
                    exc,
                    exc_info=exc,
                )
                raise KmvException(
                    error=database_table_exc.DATABASE_TABLE_OPERATION_FAILED_ERROR
                ) from exc
        if not dropped:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_NOT_FOUND_ERROR
            )
        return AdminDatabaseTableActionRes(table_name=table_name, success=True)

    @staticmethod
    async def regenerate_table(
        req: AdminDatabaseTableActionReq,
    ) -> AdminDatabaseTableActionRes:
        AdminDatabaseTableService._ensure_confirmed(req)
        table_name = req.table_name.strip()
        if registered_orm_model_by_table_name(table_name) is None:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_REGENERATE_UNREGISTERED_ERROR
            )

        async with AdminDatabaseTableService._default_storage() as storage:
            try:
                regenerated = await regenerate_database_table(table_name, storage)
            except KmvException:
                raise
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "重建数据库表失败 table=%s: %s",
                    table_name,
                    exc,
                    exc_info=exc,
                )
                raise KmvException(
                    error=database_table_exc.DATABASE_TABLE_OPERATION_FAILED_ERROR
                ) from exc
        if not regenerated:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_REGENERATE_UNREGISTERED_ERROR
            )
        return AdminDatabaseTableActionRes(table_name=table_name, success=True)