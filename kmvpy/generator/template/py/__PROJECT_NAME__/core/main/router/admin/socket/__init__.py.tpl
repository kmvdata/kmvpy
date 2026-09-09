from typing import Any

from fastapi import APIRouter
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.core.main.service.admin.socket import AdminSocketService

router = APIRouter(prefix="/api/admin/socket", tags=["admin_socket"])


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
