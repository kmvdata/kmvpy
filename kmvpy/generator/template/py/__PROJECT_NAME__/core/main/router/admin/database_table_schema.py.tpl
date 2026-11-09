# coding: utf-8
"""管理端表结构编辑 HTTP 接口。

三个端点都只使用配置声明的数据库：请求不接受任何连接参数。
``describe`` / ``preview`` 是只读接口，``apply`` 是写操作并记录审计日志。
"""

from fastapi import APIRouter, Depends

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.admin_op_log import admin_op_log
from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from __PROJECT_NAME__.common.dto.admin.database_table_schema import (
    AdminDatabaseTableSchemaApplyReq,
    AdminDatabaseTableSchemaPreviewReq,
    AdminDatabaseTableSchemaReq,
)
from __PROJECT_NAME__.core.main.service.admin.database_table_schema import (
    AdminDatabaseTableSchemaService,
)

router = APIRouter(
    prefix="/api/admin/database_table",
    tags=["admin_database_table"],
)


@router.post(
    path="/schema/describe",
    summary="读取数据表结构",
    description=(
        "读取配置库中指定表的列、索引与默认值，并返回结构指纹与 ORM 建议初值。"
        "只读接口，不修改任何结构。"
    ),
    tags=["admin_database_table"],
)
@api_log
async def api_admin_database_table_schema_describe(
    req: AdminDatabaseTableSchemaReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminDatabaseTableSchemaService.describe_table(req)
    )


@router.post(
    path="/schema/preview",
    summary="预览数据表结构变更",
    description=(
        "按提交的目标结构重新读取当前表并计算差异与风险，返回可执行的语句"
        "或需人工处理的三段 SQL。只读接口，不会执行任何 DDL。"
    ),
    tags=["admin_database_table"],
)
@api_log
async def api_admin_database_table_schema_preview(
    req: AdminDatabaseTableSchemaPreviewReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminDatabaseTableSchemaService.preview_schema(req)
    )


@router.post(
    path="/schema/apply",
    summary="执行数据表结构变更",
    description=(
        "在单个事务内执行结构变更；表名确认、结构指纹与风险确认任一不满足"
        "时不会执行任何 DDL。"
    ),
    tags=["admin_database_table"],
)
@api_log
@admin_op_log
async def api_admin_database_table_schema_apply(
    req: AdminDatabaseTableSchemaApplyReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    _ = admin_user
    return ApiResponse.success_response(
        data=await AdminDatabaseTableSchemaService.apply_schema(req)
    )