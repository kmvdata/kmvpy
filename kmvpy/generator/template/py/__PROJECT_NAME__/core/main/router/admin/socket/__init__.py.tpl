from typing import Any

from fastapi import APIRouter, Depends
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.common.dependencies.auth import auth_admin
from kmvpy.core.main.service.jwt_service import JwtUserInfo
from __PROJECT_NAME__.core.main.service.admin.socket import AdminSocketService

from __PROJECT_NAME__.core.main.service.common.realtime import RealtimeService

router = APIRouter(prefix="/api/admin/socket", tags=["admin_socket"])


@router.post('/session', summary='校验当前登录会话；续签由现有 HTTP 中间件返回')
async def api_validate_session(info: JwtUserInfo = Depends(auth_admin)):
    from kmvpy.common.response import ApiResponse
    return ApiResponse.success_response(data={'valid': True})


def register_admin_socket_handlers(socketio: Any | None = None) -> None:
    """
    注册管理端 Socket.IO 事件。

    客户端连接地址复用 /ws/socket.io，namespace=/admin_ws。
    连接时需通过 auth.authorization、Authorization header 或 query authorization 传入管理端 JWT。
    """
    socket_manager = socketio or getattr(kosmos, "socketio", None)
    if socket_manager is None:
        logger.warning("Socket.IO 尚未初始化，跳过管理端 socket 事件注册")
        return

    if getattr(socket_manager, "___PROJECT_NAME___admin_socket_registered", False):
        return
    setattr(socket_manager, "___PROJECT_NAME___admin_socket_registered", True)

    @socket_manager.on(event="connect", namespace=AdminSocketService.SOCKET_NAMESPACE)
    async def connect(sid: str, environ: dict[str, Any], auth: Any = None):
        return await AdminSocketService.handle_socket_connection(
            event="connect",
            sid=sid,
            environ=environ,
            auth=auth,
        )

    @socket_manager.on(event="disconnect", namespace=AdminSocketService.SOCKET_NAMESPACE)
    async def disconnect(sid: str):
        await AdminSocketService.handle_socket_connection(event="disconnect", sid=sid)

    @socket_manager.on(event='auth_update', namespace=AdminSocketService.SOCKET_NAMESPACE)
    async def auth_update(sid: str, data):
        return await AdminSocketService.update_authorization(sid, data)

    @socket_manager.on(event='subscription', namespace=AdminSocketService.SOCKET_NAMESPACE)
    async def subscription(sid: str, data):
        return await RealtimeService.subscription('admin', sid, data)
