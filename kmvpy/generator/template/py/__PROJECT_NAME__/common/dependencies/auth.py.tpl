from enum import IntEnum
from typing import Annotated, NoReturn

from fastapi import HTTPException, Request, Response, status

from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo

from __PROJECT_NAME__.common.auth_session import AuthRole, AuthSessionService


class UserType(IntEnum):
    """JWT / 业务中的用户类型。"""

    USER = 0  # 普通用户
    ADMIN = 100  # 管理员

def _extract_user_kid_from_jwt_payload(jwt_payload) -> int | None:
    """兼容对象 / 字典两种 JWT 载荷结构，尽量提取当前登录用户 kid。"""
    if jwt_payload is None:
        return None

    candidate_keys = ("kid", "user_kid")
    for key in candidate_keys:
        kid = jwt_payload.get(key) if isinstance(
            jwt_payload, dict) else getattr(jwt_payload, key, None)
        if isinstance(kid, int):
            return kid
        if isinstance(kid, str):
            normalized_kid = kid.strip()
            if not normalized_kid:
                continue
            try:
                return int(normalized_kid)
            except ValueError:
                continue
    return None


def _extract_jwt_user_info_from_payload(jwt_payload) -> JwtUserInfo | None:
    """兼容对象 / 字典两种 JWT 载荷结构，提取 `JwtUserInfo`。"""
    user_kid = _extract_user_kid_from_jwt_payload(jwt_payload)
    if user_kid is None:
        return None
    user_type = None
    for key in ("user_type", "type"):
        candidate_user_type = jwt_payload.get(key) if isinstance(
            jwt_payload, dict) else getattr(jwt_payload, key, None)
        if isinstance(candidate_user_type, int):
            user_type = candidate_user_type
            break
        if isinstance(candidate_user_type, str):
            normalized_user_type = candidate_user_type.strip()
            if not normalized_user_type:
                continue
            try:
                user_type = int(normalized_user_type)
                break
            except ValueError:
                continue
    if user_type is None:
        return None
    return JwtUserInfo(kid=user_kid, user_type=user_type)


def _authorization_invalid_detail() -> dict[str, int | str]:
    from __PROJECT_NAME__.common.exception.user_op_errors import AUTHORIZATION_INVALID_ERROR

    error_code, error_msg, error_more_msg = AUTHORIZATION_INVALID_ERROR
    return {
        "code": error_code,
        "msg": error_more_msg or error_msg,
        "error": error_msg,
    }


def _raise_authorization_invalid(auth_role: str) -> NoReturn:
    # 鉴权失败属于 HTTP 协议层状态；业务异常仍通过 ApiResponse.code 表达。
    headers = {"WWW-Authenticate": "Bearer", "X-Auth-Role": auth_role}
    raise HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=_authorization_invalid_detail(),
        headers=headers,
    )


async def _auth_jwt(
    request: Request,
    response: Response,
    auth_role: AuthRole,
    expected_user_type: UserType,
) -> JwtUserInfo:
    """按用户类型选择独立 JWT 配置解析登录态。"""
    request_state = getattr(request, "state", None)
    if request_state is not None:
        for state_attr in ("jwt_user_info", "user_info", "current_user", "user"):
            user_info = getattr(request_state, state_attr, None)
            normalized_user_info = _extract_jwt_user_info_from_payload(user_info)
            if (
                normalized_user_info is not None
                and normalized_user_info.user_type == int(expected_user_type)
            ):
                return normalized_user_info

    authorization = request.headers.get("Authorization", "").strip()
    if not authorization:
        _raise_authorization_invalid(auth_role)

    token_type, _, token = authorization.partition(" ")
    if token_type.lower() != "bearer" or not token.strip():
        _raise_authorization_invalid(auth_role)

    normalized_token = token.strip()
    try:
        payload = await AuthSessionService.authenticate_access_token(
            request,
            auth_role=auth_role,
            token=normalized_token,
        )
    except HTTPException:
        try:
            recovered = await AuthSessionService.recover_expired_access_token(
                request,
                response,
                auth_role=auth_role,
                token=normalized_token,
            )
            if recovered is None:
                _raise_authorization_invalid(auth_role)
            candidate = getattr(request.state, "auth_renew_candidate", None)
            if not isinstance(candidate, dict):
                _raise_authorization_invalid(auth_role)
            payload = candidate["payload"]
        except Exception as exc:
            logger.warning(
                "恢复过期登录信息失败，auth_role=%s",
                auth_role,
                exc_info=exc,
            )
            _raise_authorization_invalid(auth_role)

    try:
        user_info = JwtService.payload_to_user_info(payload)
        request.state.jwt_user_info = user_info
    except Exception as exc:
        logger.warning(
            "解析登录信息失败，auth_role=%s",
            auth_role,
            exc_info=exc,
        )
        _raise_authorization_invalid(auth_role)

    if user_info.user_type == int(expected_user_type):
        return user_info
    _raise_authorization_invalid(auth_role)


async def auth_user(
    request: Annotated[Request, "JWT鉴权"],
    response: Response,
) -> JwtUserInfo:
    """路由层统一登录态依赖，负责从请求中解析当前普通用户信息。"""
    return await _auth_jwt(
        request,
        response,
        auth_role="user",
        expected_user_type=UserType.USER,
    )


async def auth_admin(
    request: Annotated[Request, "JWT鉴权"],
    response: Response,
) -> JwtUserInfo:
    """路由层统一登录态依赖，负责从请求中解析当前管理员信息。"""
    return await _auth_jwt(
        request,
        response,
        auth_role="admin",
        expected_user_type=UserType.ADMIN,
    )
