# coding: utf-8
"""管理端数据库目录 HTTP 接口。"""

from fastapi import APIRouter, Depends

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from __PROJECT_NAME__.common.dto.admin.database_catalog import (
    AdminDatabaseCatalogReq,
    AdminDatabaseCatalogTablesReq,
)
from __PROJECT_NAME__.core.main.service.admin.database_catalog import (
    AdminDatabaseCatalogService,
)

router = APIRouter(
    prefix="/api/admin/database_catalog",
    tags=["admin_database_catalog"],
)


@router.post(
    path="/list",
    summary="数据库目录",
    description="返回配置文件声明的数据库；不枚举数据库服务上的其它数据库。",
    tags=["admin_database_catalog"],
)
@api_log
async def api_admin_database_catalog_list(
    req: AdminDatabaseCatalogReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    _ = req
    return ApiResponse.success_response(
        data=await AdminDatabaseCatalogService.list_databases()
    )


@router.post(
    path="/tables",
    summary="数据库表名清单",
    description="按数据库名称只读取该库的表名清单；库名必须与配置一致。",
    tags=["admin_database_catalog"],
)
@api_log
async def api_admin_database_catalog_tables(
    req: AdminDatabaseCatalogTablesReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminDatabaseCatalogService.list_tables(req)
    )