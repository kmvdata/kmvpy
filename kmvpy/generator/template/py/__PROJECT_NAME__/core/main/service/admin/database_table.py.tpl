# coding: utf-8
"""管理端数据库表维护服务。"""

from contextlib import asynccontextmanager
from typing import AsyncIterator, Any

from kmvpy.common.conf import DatabaseConfig
from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.tool.logger import logger
from sqlalchemy.engine import URL, make_url

from __PROJECT_NAME__.common.conf import get_app_config
from __PROJECT_NAME__.common.dto.admin.database_table import (
    AdminDatabaseConnectionReq,
    AdminDatabaseTableActionReq,
    AdminDatabaseTableActionRes,
    AdminDatabaseTableColumnRes,
    AdminDatabaseTableRes,
    AdminDatabaseTablesInitializeAllReq,
    AdminDatabaseTablesInitializeAllRes,
    AdminDatabaseTablesListReq,
    AdminDatabaseTablesListRes,
)
from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.orm import (
    drop_database_table,
    init_tables,
    inspect_database_tables,
    regenerate_database_table,
    registered_orm_model_by_table_name,
    registered_orm_models,
)
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage


class AdminDatabaseTableService:
    """管理端临时连接数据库并维护 ORM 注册表。"""

    _INIT_ALL_CONFIRM_TEXT = "INIT_ALL_TABLES"
    _DEFAULT_PORTS = {
        "postgresql": 5432,
        "mysql": 3306,
    }

    @staticmethod
    def _clean_text(value: str | None) -> str:
        return value.strip() if value else ""

    @staticmethod
    def _custom_database_config(req: AdminDatabaseConnectionReq) -> DatabaseConfig:
        driver = req.driver
        if driver == "sqlite":
            sqlite_path = AdminDatabaseTableService._clean_text(req.sqlite_path)
            if not sqlite_path:
                raise KmvException(
                    error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
                )
            url = URL.create(
                drivername="sqlite+aiosqlite",
                database=sqlite_path,
            ).render_as_string(hide_password=False)
            return DatabaseConfig(url=url, timeout=req.timeout, echo=False)

        if driver not in ("postgresql", "mysql"):
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            )

        host = AdminDatabaseTableService._clean_text(req.host)
        database = AdminDatabaseTableService._clean_text(req.database)
        username = AdminDatabaseTableService._clean_text(req.username)
        if not host or not database or not username:
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            )

        drivername = (
            "postgresql+asyncpg" if driver == "postgresql" else "mysql+aiomysql"
        )
        url = URL.create(
            drivername=drivername,
            username=username,
            password=req.password or None,
            host=host,
            port=req.port or AdminDatabaseTableService._DEFAULT_PORTS[driver],
            database=database,
        ).render_as_string(hide_password=False)
        return DatabaseConfig(
            url=url,
            timeout=req.timeout,
            echo=False,
            ssl=req.ssl,
            options=req.options or "",
        )

    @staticmethod
    @asynccontextmanager
    async def _storage_for_connection(
        req: AdminDatabaseConnectionReq,
    ) -> AsyncIterator[KOrmStorage]:
        if req.mode == "default":
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
            return

        config = get_app_config()
        timezone = getattr(
            getattr(config, "general", None),
            "timezone",
            "Asia/Shanghai",
        )
        storage = KOrmStorage(
            database_config=AdminDatabaseTableService._custom_database_config(req),
            redis_config=None,
            timezone=timezone,
        )
        try:
            storage.init_db_session()
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning("自定义数据库连接不可用: %s", exc, exc_info=exc)
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            ) from exc
        try:
            yield storage
        finally:
            await storage.dispose()

    @staticmethod
    def _connection_summary(
        req: AdminDatabaseConnectionReq,
        storage: KOrmStorage,
    ) -> str:
        if req.mode == "default":
            database_url = (
                storage.database_config.url if storage.database_config else ""
            )
            if not database_url:
                return "default"
            return make_url(database_url).render_as_string(hide_password=True)
        if req.driver == "sqlite":
            return (
                f"sqlite:///"
                f"{AdminDatabaseTableService._clean_text(req.sqlite_path)}"
            )
        host = AdminDatabaseTableService._clean_text(req.host)
        database = AdminDatabaseTableService._clean_text(req.database)
        username = AdminDatabaseTableService._clean_text(req.username)
        port = req.port or AdminDatabaseTableService._DEFAULT_PORTS.get(
            req.driver or "",
            0,
        )
        return f"{req.driver}://{username}@{host}:{port}/{database}"

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
        row_count = raw.get("row_count")
        return AdminDatabaseTableRes(
            table_name=str(raw.get("table_name", "")),
            registered=bool(raw.get("registered", False)),
            comment=raw.get("comment") if isinstance(raw.get("comment"), str) else None,
            row_count=row_count if isinstance(row_count, int) else None,
            column_count=len(columns),
            columns=columns,
        )

    @staticmethod
    def _ensure_confirmed(req: AdminDatabaseTableActionReq) -> None:
        if req.table_name.strip() != req.confirm_table_name.strip():
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_CONFIRM_MISMATCH_ERROR
            )

    @staticmethod
    def _ensure_initialize_all_confirmed(
        req: AdminDatabaseTablesInitializeAllReq,
    ) -> None:
        if req.confirm_text.strip() != AdminDatabaseTableService._INIT_ALL_CONFIRM_TEXT:
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_INITIALIZE_CONFIRM_MISMATCH_ERROR
            )

    @staticmethod
    async def list_tables(
        req: AdminDatabaseTablesListReq,
    ) -> AdminDatabaseTablesListRes:
        async with AdminDatabaseTableService._storage_for_connection(
            req.connection
        ) as storage:
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
                    req.connection,
                    storage,
                ),
                registered_table_count=len(registered_orm_models()),
            )

    @staticmethod
    async def drop_table(
        req: AdminDatabaseTableActionReq,
    ) -> AdminDatabaseTableActionRes:
        AdminDatabaseTableService._ensure_confirmed(req)
        table_name = req.table_name.strip()
        async with AdminDatabaseTableService._storage_for_connection(
            req.connection
        ) as storage:
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

        async with AdminDatabaseTableService._storage_for_connection(
            req.connection
        ) as storage:
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

    @staticmethod
    async def initialize_all_tables(
        req: AdminDatabaseTablesInitializeAllReq,
    ) -> AdminDatabaseTablesInitializeAllRes:
        AdminDatabaseTableService._ensure_initialize_all_confirmed(req)
        try:
            await init_tables()
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning("重新初始化全部 ORM 表失败: %s", exc, exc_info=exc)
            raise KmvException(
                error=database_table_exc.DATABASE_TABLE_OPERATION_FAILED_ERROR
            ) from exc

        return AdminDatabaseTablesInitializeAllRes(
            initialized_table_count=len(registered_orm_models()),
            success=True,
        )
