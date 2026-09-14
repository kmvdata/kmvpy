from fastapi import APIRouter, Depends, Request

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtService
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.auth_session import AuthSessionService
from __PROJECT_NAME__.common.dependencies.admin_op_log import admin_op_log
from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from __PROJECT_NAME__.common.dependencies.client import ClientRequestInfo, client_request_info
from __PROJECT_NAME__.common.dto.admin.admin_op import (
    AdminCreateReviewerReq,
    AdminCreateUserReq,
    AdminDeleteUserReq,
    AdminLoginReq,
    AdminResetUserPasswordReq,
    AdminUpdateUserRoleReq,
    AdminUpdateUserStateReq,
    AdminUserListReq,
    AdminUsernameLoginReq,
)
from __PROJECT_NAME__.common.dto.user.user_op import UpdateUserProfileReq
from __PROJECT_NAME__.core.main.service.admin.admin_op import AdminOpService

router = APIRouter(prefix="/api/admin", tags=["admin_op"])


def _admin_auth_success_response(auth_res):
    response = ApiResponse.success_response(data=auth_res)
    AuthSessionService.attach_session_cookie(
        response,
        auth_role="admin",
        cookie_value=auth_res.session_cookie_value,
        max_age=auth_res.session_cookie_max_age,
    )
    return response


@router.post(
    path="/email/login",
    summary="管理员登录",
    description="使用邮箱或用户名和密码登录管理员账号，返回 Bearer Token 与当前用户信息。前端请尽量在请求头中传递 X-Device-Type、X-Device-Model、X-OS-Version、X-App-Version、X-Device-ID、X-Network、X-Brand；获取不到时可留空。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_email_login(
    req: AdminLoginReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await AdminOpService.admin_login(req, client_info)
    return _admin_auth_success_response(auth_res)


@router.post(
    path="/username/login",
    summary="管理员用户名登录",
    description="使用用户名和密码登录管理员账号（仅按 user_base.username 匹配，含 @ 也视为用户名本身，不按邮箱解析）。返回与普通管理员登录相同的 Token。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_username_login(
    req: AdminUsernameLoginReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await AdminOpService.admin_login_by_username(req, client_info)
    return _admin_auth_success_response(auth_res)


@router.post(
    path="/logout",
    summary="管理员退出登录",
    description="注销当前管理员 Token，使当前管理端会话立即失效。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_admin_logout(
    request: Request,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    token = JwtService.extract_token_from_header(
        request.headers.get("Authorization", "")
    )
    response = ApiResponse.success_response(data=True)
    await AuthSessionService.revoke_token(
        token,
        auth_role="admin",
        request=request,
        response=response,
    )
    return response


@router.post(
    path="/profile",
    summary="获取管理员信息",
    description="获取当前登录管理员信息，需在请求头中携带 Bearer Token。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_get_user_profile(user_info: JwtUserInfo = Depends(auth_admin)):
    return ApiResponse.success_response(data=await AdminOpService.get_user_info(user_info.kid))


@router.post(
    path="/profile/update",
    summary="编辑管理员信息",
    description="编辑当前登录管理员的昵称、个性签名、联系方式。每个字段默认可为 None，表示维持原值不变；若传空字符串则表示清空该字段。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_update_user_profile(
    req: UpdateUserProfileReq,
    user_info: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(data=await AdminOpService.update_user_profile(req, user_info))


@router.post(
    path="/user/list",
    summary="用户列表",
    description="分页查询未软删除的用户基础信息，需管理员登录态。",
    tags=["admin_op"],
)
@api_log
async def api_admin_user_list(
    req: AdminUserListReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(data=await AdminOpService.list_users(req))


@router.post(
    path="/user/create",
    summary="创建用户",
    description="按用户名、密码、用户类型创建用户（未绑定邮箱），需管理员登录态。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_create_user(
    req: AdminCreateUserReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(data=await AdminOpService.create_user(req))


@router.post(
    path="/user/password/reset",
    summary="重置用户密码",
    description="为指定用户设置新密码（重新生成盐值与哈希），需管理员登录态。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_reset_user_password(
    req: AdminResetUserPasswordReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminOpService.reset_user_password(req, admin_user)
    )


@router.post(
    path="/user/delete",
    summary="删除用户",
    description="软删除指定用户（写入 delete_at），需管理员登录态。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_delete_user(
    req: AdminDeleteUserReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(data=await AdminOpService.delete_user(req, admin_user))


@router.post(
    path="/reviewer/create",
    summary="创建审核员",
    description="创建审核员账号，需管理员登录态。审核员可审核监控任务有效性、查看商标监控状态/通知记录、处理监控异常反馈。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_create_reviewer(
    req: AdminCreateReviewerReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(data=await AdminOpService.create_reviewer(req))


@router.post(
    path="/user/role/update",
    summary="更新用户角色",
    description="更新指定用户的角色类型(普通用户/管理员/审核员)，需管理员登录态。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_update_user_role(
    req: AdminUpdateUserRoleReq,
    _admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(data=await AdminOpService.update_user_role(req))


@router.post(
    path="/user/state/update",
    summary="更新用户状态",
    description="启用或禁用指定用户账号，需管理员登录态。",
    tags=["admin_op"],
)
@api_log
@admin_op_log
async def api_update_user_state(
    req: AdminUpdateUserStateReq,
    admin_user: JwtUserInfo = Depends(auth_admin),
):
    return ApiResponse.success_response(
        data=await AdminOpService.update_user_state(req, admin_user)
    )
