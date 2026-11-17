from fastapi import APIRouter, Depends

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.admin_op_log import admin_op_log
from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from __PROJECT_NAME__.common.dto.admin.work_ticket import (
    AdminWorkTicketDetailReq,
    AdminWorkTicketListReq,
    AdminWorkTicketReplyReq,
    AdminWorkTicketUpdateStatusReq,
)
from __PROJECT_NAME__.core.main.service.admin.work_ticket import AdminWorkTicketService

router = APIRouter(prefix="/api/admin/work_ticket", tags=["admin_work_ticket"])


@router.post(
    path="/list",
    summary="工单分页列表",
    description="管理端分页查看工单，可按状态筛选，按最后消息时间倒序。",
    tags=["admin_work_ticket"],
)
@api_log
async def api_admin_work_ticket_list(
    req: AdminWorkTicketListReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminWorkTicketService.list_tickets(req)
    )


@router.post(
    path="/detail",
    summary="工单详情（含对话）",
    description="返回工单摘要及按时间升序的全部消息，用于会话上下文展示。",
    tags=["admin_work_ticket"],
)
@api_log
async def api_admin_work_ticket_detail(
    req: AdminWorkTicketDetailReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminWorkTicketService.get_ticket_detail(req)
    )


@router.post(
    path="/reply",
    summary="工单回复",
    description="管理员追加一条消息；可选同时更新状态。首次回复时若未分配跟进人，将自动记为当前管理员。",
    tags=["admin_work_ticket"],
)
@api_log
@admin_op_log
async def api_admin_work_ticket_reply(
    req: AdminWorkTicketReplyReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminWorkTicketService.reply_ticket(req, admin_user)
    )


@router.post(
    path="/status/update",
    summary="更新工单状态",
    description="仅更新工单状态，不追加消息。",
    tags=["admin_work_ticket"],
)
@api_log
@admin_op_log
async def api_admin_work_ticket_update_status(
    req: AdminWorkTicketUpdateStatusReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminWorkTicketService.update_status(req, admin_user)
    )
