# coding: utf-8
"""管理端系统维护 HTTP 接口。"""

from fastapi import APIRouter, Depends

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.admin_op_log import admin_op_log
from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from __PROJECT_NAME__.common.dto.admin.system import AdminServiceRestartReq
from __PROJECT_NAME__.core.main.service.admin.system import AdminSystemService

router = APIRouter(
    prefix="/api/admin/system",
    tags=["admin_system"],
)


@router.post(
    path="/service/restart",
    summary="重启后台服务",
    description="通过当前发布目录 deploy.sh 触发后台 Python 服务重启。",
    tags=["admin_system"],
)
@api_log
@admin_op_log
async def api_admin_system_service_restart(
    req: AdminServiceRestartReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    _ = admin_user
    return ApiResponse.success_response(
        data=await AdminSystemService.restart_service(req)
    )
