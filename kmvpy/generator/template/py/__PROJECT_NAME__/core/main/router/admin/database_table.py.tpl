# coding: utf-8
"""管理端数据库表维护 HTTP 接口。"""

from fastapi import APIRouter, Depends

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.admin_op_log import admin_op_log
from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from __PROJECT_NAME__.common.dto.admin.database_table import (
    AdminDatabaseTableActionReq,
    AdminDatabaseTablesListReq,
)
from __PROJECT_NAME__.core.main.service.admin.database_table import (
    AdminDatabaseTableService,
)

router = APIRouter(
    prefix="/api/admin/database_table",
    tags=["admin_database_table"],
)


@router.post(
    path="/list",
    summary="数据库表列表",
    description="查看配置文件指定数据库的全部表结构；不接受任何连接参数。",
    tags=["admin_database_table"],
)
@api_log
async def api_admin_database_table_list(
    req: AdminDatabaseTablesListReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    _ = req
    return ApiResponse.success_response(
        data=await AdminDatabaseTableService.list_tables()
    )


@router.post(
    path="/drop",
    summary="删除数据库表",
    description="删除配置库中的指定数据表。需管理员登录态并提供完全一致的确认表名。",
    tags=["admin_database_table"],
)
@api_log
@admin_op_log
async def api_admin_database_table_drop(
    req: AdminDatabaseTableActionReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    _ = admin_user
    return ApiResponse.success_response(
        data=await AdminDatabaseTableService.drop_table(req)
    )


@router.post(
    path="/regenerate",
    summary="重建数据库表",
    description="按 common.infra.orm.__init__ 中注册的 ORM 模型同步指定表结构。",
    tags=["admin_database_table"],
)
@api_log
@admin_op_log
async def api_admin_database_table_regenerate(
    req: AdminDatabaseTableActionReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    _ = admin_user
    return ApiResponse.success_response(
        data=await AdminDatabaseTableService.regenerate_table(req)
    )