from typing import Any

from fastapi import APIRouter, Depends, Query
from kmvpy.common.response import ApiResponse
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import api_log, logger
from kmvpy.core.main.service.jwt_service import JwtUserInfo

from __PROJECT_NAME__.common.dependencies.auth import auth_user
from __PROJECT_NAME__.core.main.service.user.socket import UserSocketService

from __PROJECT_NAME__.core.main.service.common.realtime import RealtimeService

router = APIRouter(prefix="/api/user/socket", tags=["user_socket"])


@router.post(
    path="/messages/pull",
    summary="补偿拉取用户 socket 未读消息",
    description="客户端主动拉取尚未推送至自身 socket 通道的滞留消息。",
    tags=["user_socket"],
)
@api_log
async def api_pull_pending_socket_messages(
    page: int = Query(default=1, ge=1, description="页码"),
    size: int = Query(default=1000, ge=1, description="每页数量"),
    user_info: JwtUserInfo = Depends(auth_user),
):
    messages, total = await UserSocketService.pull_pending_socket_messages(
        user_kid=int(user_info.kid),
        page=page,
        size=size,
    )
    return ApiResponse.success_response(
        data=messages,
        total=total,
        page=page,
        size=size,
    )


@router.post('/session', summary='校验当前登录会话；续签由现有 HTTP 中间件返回')
async def api_validate_session(info: JwtUserInfo = Depends(auth_user)):
    from kmvpy.common.response import ApiResponse
    return ApiResponse.success_response(data={'valid': True})


def register_user_socket_handlers(socketio: Any | None = None) -> None:
    """
    注册用户端 Socket.IO 事件。

    客户端连接地址沿用 kmvpy 默认挂载：/ws/socket.io，namespace=/ws。
    连接时需通过 auth.token、auth.Authorization、Authorization header 或 query token 传入用户端 JWT。
    """
    socket_manager = socketio or getattr(kosmos, "socketio", None)
    if socket_manager is None:
        logger.warning("Socket.IO 尚未初始化，跳过用户 socket 事件注册")
        return

    if getattr(socket_manager, "___PROJECT_NAME___user_socket_registered", False):
        return
    setattr(socket_manager, "___PROJECT_NAME___user_socket_registered", True)

    @socket_manager.on(event="connect", namespace=UserSocketService.SOCKET_NAMESPACE)
    async def connect(sid: str, environ: dict[str, Any], auth: Any = None):
        return await UserSocketService.handle_socket_connection(
            event="connect",
            sid=sid,
            environ=environ,
            auth=auth,
        )

    @socket_manager.on(event="disconnect", namespace=UserSocketService.SOCKET_NAMESPACE)
    async def disconnect(sid: str):
        await UserSocketService.handle_socket_connection(event="disconnect", sid=sid)

    @socket_manager.on(event='auth_update', namespace=UserSocketService.SOCKET_NAMESPACE)
    async def auth_update(sid: str, data):
        return await UserSocketService.update_authorization(sid, data)

    @socket_manager.on(event='subscription', namespace=UserSocketService.SOCKET_NAMESPACE)
    async def subscription(sid: str, data):
        return await RealtimeService.subscription('user', sid, data)
