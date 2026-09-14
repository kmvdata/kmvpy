from fastapi import APIRouter, Depends, Request

from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import api_log
from kmvpy.core.main.service.jwt_service import JwtService
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.auth_session import AuthSessionService
from __PROJECT_NAME__.common.dependencies.auth import auth_user
from __PROJECT_NAME__.common.dependencies.client import ClientRequestInfo, client_request_info
from __PROJECT_NAME__.common.dto.user.user_op import (
    AccountLoginReq,
    EmailCaptchaReq,
    EmailLoginReq,
    EmailRegisterReq,
    PhoneLoginReq,
    UpdateUserProfileReq,
    UsernameLoginReq,
)
from __PROJECT_NAME__.core.main.service.user.user_op import UserOpService

router = APIRouter(prefix="/api/user", tags=["user_op"])


def _user_auth_success_response(auth_res):
    response = ApiResponse.success_response(data=auth_res)
    AuthSessionService.attach_session_cookie(
        response,
        auth_role="user",
        cookie_value=auth_res.session_cookie_value,
        max_age=auth_res.session_cookie_max_age,
    )
    return response


@router.post(
    path="/email/verify-code",
    summary="获取邮箱验证码",
    description="发送邮箱验证码。当前联调环境下该请求固定成功，并返回可用于注册的测试验证码。",
    tags=["user_op"],
)
@api_log
async def api_send_email_verify_code(req: EmailCaptchaReq):
    return ApiResponse.success_response(data=await UserOpService.send_email_captcha(req))


@router.post(
    path="/email/register",
    summary="邮箱注册",
    description="使用邮箱、验证码、密码完成注册；可选传入邀请码建立上下级关系。当前联调环境固定使用 666666 作为验证码，注册成功后会直接返回登录 token。前端请尽量在请求头中传递 X-Device-Type、X-Device-Model、X-OS-Version、X-App-Version、X-Device-ID、X-Network、X-Brand；获取不到时可留空。",
    tags=["user_op"],
)
@api_log
async def api_email_register(
    req: EmailRegisterReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await UserOpService.email_register(req, client_info)
    return _user_auth_success_response(auth_res)


@router.post(
    path="/email/login",
    summary="邮箱登录",
    description="使用邮箱和密码登录，返回 Bearer Token 与当前用户信息。前端请尽量在请求头中传递 X-Device-Type、X-Device-Model、X-OS-Version、X-App-Version、X-Device-ID、X-Network、X-Brand；获取不到时可留空。",
    tags=["user_op"],
)
@api_log
async def api_email_login(
    req: EmailLoginReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await UserOpService.email_login(req, client_info)
    return _user_auth_success_response(auth_res)


@router.post(
    path="/username/login",
    summary="用户用户名登录",
    description="使用用户名与密码登录（仅按 user_base.username 匹配，含 @ 也视为用户名本身，不按邮箱解析）。返回与邮箱登录相同结构。",
    tags=["user_op"],
)
@api_log
async def api_username_login(
    req: UsernameLoginReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await UserOpService.username_login(req, client_info)
    return _user_auth_success_response(auth_res)


@router.post(
    path="/phone/login",
    summary="用户手机号登录",
    description="使用手机号和密码登录，仅匹配 user_base.phone 字段。返回与邮箱登录相同结构。前端请尽量在请求头中传递设备信息头；获取不到时可留空。",
    tags=["user_op"],
)
@api_log
async def api_phone_login(
    req: PhoneLoginReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await UserOpService.phone_login(req, client_info)
    return _user_auth_success_response(auth_res)


@router.post(
    path="/account/login",
    summary="用户统一账号登录",
    description="支持邮箱、手机号或用户名（字母开头）自动识别登录：邮箱按 email 字段；手机号按 phone 字段；用户名按 username 字段。返回与邮箱登录相同结构。",
    tags=["user_op"],
)
@api_log
async def api_account_login(
    req: AccountLoginReq,
    client_info: ClientRequestInfo = Depends(client_request_info),
):
    auth_res = await UserOpService.account_login(req, client_info)
    return _user_auth_success_response(auth_res)


@router.post(
    path="/logout",
    summary="用户退出登录",
    description="注销当前普通用户 Token，使当前会话立即失效。",
    tags=["user_op"],
)
@api_log
async def api_user_logout(
    request: Request,
    _user_info: JwtUserInfo = Depends(auth_user),
):
    token = JwtService.extract_token_from_header(
        request.headers.get("Authorization", "")
    )
    response = ApiResponse.success_response(data=True)
    await AuthSessionService.revoke_token(
        token,
        auth_role="user",
        request=request,
        response=response,
    )
    return response


@router.post(
    path="/profile",
    summary="获取用户信息",
    description="获取当前登录用户信息，需在请求头中携带 Bearer Token。",
    tags=["user_op"],
)
@api_log
async def api_get_user_profile(user_info: JwtUserInfo = Depends(auth_user)):
    return ApiResponse.success_response(data=await UserOpService.get_user_info(user_info.kid))


@router.post(
    path="/profile/update",
    summary="编辑用户信息",
    description="编辑当前登录用户的昵称、个性签名、联系方式。每个字段默认可为 None，表示维持原值不变；若传空字符串则表示清空该字段。",
    tags=["user_op"],
)
@api_log
async def api_update_user_profile(
    req: UpdateUserProfileReq,
    user_info: JwtUserInfo = Depends(auth_user),
):
    return ApiResponse.success_response(data=await UserOpService.update_user_profile(req, user_info))
