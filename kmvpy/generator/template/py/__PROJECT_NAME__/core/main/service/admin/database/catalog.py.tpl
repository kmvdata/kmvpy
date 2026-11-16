# coding: utf-8
"""管理端数据库目录服务。"""

from __PROJECT_NAME__.common.dto.admin.database_catalog import (
    AdminDatabaseCatalogItemRes,
    AdminDatabaseCatalogRes,
    AdminDatabaseCatalogTableItemRes,
    AdminDatabaseCatalogTablesReq,
    AdminDatabaseCatalogTablesRes,
    AdminDatabaseServerRes,
)
from __PROJECT_NAME__.core.main.hub.database_catalog import DatabaseCatalogHub


class AdminDatabaseCatalogService:
    """读取配置声明的数据库目录与表名清单。"""

    @staticmethod
    async def list_databases() -> AdminDatabaseCatalogRes:
        catalog = await DatabaseCatalogHub.build_catalog()
        return AdminDatabaseCatalogRes(
            server=AdminDatabaseServerRes(**catalog["server"]),
            items=[
                AdminDatabaseCatalogItemRes(**item) for item in catalog["items"]
            ],
            total=int(catalog["total"]),
            business_total=int(catalog["business_total"]),
        )

    @staticmethod
    async def list_tables(
        req: AdminDatabaseCatalogTablesReq,
    ) -> AdminDatabaseCatalogTablesRes:
        """读取指定数据库的表名清单（不做表结构内省）。"""
        payload = await DatabaseCatalogHub.list_table_names(req.database)
        return AdminDatabaseCatalogTablesRes(
            database=str(payload["database"]),
            items=[
                AdminDatabaseCatalogTableItemRes(**item)
                for item in payload["items"]
            ],
            total=int(payload["total"]),
        )