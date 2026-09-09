from fastapi import APIRouter, Depends

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.auth import auth_user
from __PROJECT_NAME__.common.dto.user.work_ticket import (
    UserWorkTicketCreateReq,
    UserWorkTicketDetailReq,
    UserWorkTicketListReq,
    UserWorkTicketReplyReq,
)
from __PROJECT_NAME__.core.main.service.user.work_ticket import UserWorkTicketService

router = APIRouter(prefix="/api/user/work_ticket", tags=["user_work_ticket"])


@router.post(
    path="/create",
    summary="创建工单",
    description="创建工单并附带首条问题描述（进入会话上下文）。",
    tags=["user_work_ticket"],
)
@api_log
async def api_user_work_ticket_create(
    req: UserWorkTicketCreateReq,
    user_info: JwtUserInfo = Depends(auth_user),
):
    return ApiResponse.success_response(
        data=await UserWorkTicketService.create_ticket(req, user_info)
    )


@router.post(
    path="/list",
    summary="我的工单列表",
    description="分页返回当前用户发起的工单。",
    tags=["user_work_ticket"],
)
@api_log
async def api_user_work_ticket_list(
    req: UserWorkTicketListReq,
    user_info: JwtUserInfo = Depends(auth_user),
):
    return ApiResponse.success_response(
        data=await UserWorkTicketService.list_my_tickets(req, user_info)
    )


@router.post(
    path="/detail",
    summary="工单详情（含对话）",
    description="仅可查看本人发起的工单；消息按时间升序。",
    tags=["user_work_ticket"],
)
@api_log
async def api_user_work_ticket_detail(
    req: UserWorkTicketDetailReq,
    user_info: JwtUserInfo = Depends(auth_user),
):
    return ApiResponse.success_response(
        data=await UserWorkTicketService.get_ticket_detail(req, user_info)
    )


@router.post(
    path="/reply",
    summary="工单补充/回复",
    description="用户追加一条消息。",
    tags=["user_work_ticket"],
)
@api_log
async def api_user_work_ticket_reply(
    req: UserWorkTicketReplyReq,
    user_info: JwtUserInfo = Depends(auth_user),
):
    return ApiResponse.success_response(
        data=await UserWorkTicketService.reply_ticket(req, user_info)
    )
