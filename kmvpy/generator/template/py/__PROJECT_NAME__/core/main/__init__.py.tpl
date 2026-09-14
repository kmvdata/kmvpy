from contextlib import asynccontextmanager
from typing import Annotated, Optional

from fastapi import FastAPI
from kmvpy.common.kmv import kosmos

from kmvpy.core.main import get_config_path, init_asgi_app

from __PROJECT_NAME__.common.auth_session import install_kmvpy_auth_session_service
from __PROJECT_NAME__.common.conf import AppConfig
from __PROJECT_NAME__.common.infra.orm import init_default_admin_if_needed, init_tables
from __PROJECT_NAME__.core.main.schedule import (
    register_app_schedule_jobs,
)
from __PROJECT_NAME__.core.main.router import routers
from __PROJECT_NAME__.core.main.router.admin.socket import register_admin_socket_handlers
from __PROJECT_NAME__.core.main.router.user.socket import register_user_socket_handlers
from __PROJECT_NAME__.core.main.service.user.socket import UserSocketService


def _align_socketio_engineio_path_with_mount() -> None:
    """
    Starlette Mount 子应用收到的 scope['path'] 仍是完整路径（含挂载前缀），
    而 fastapi_socketio 默认 engineio_path 为 /socket.io/，与 /ws/socket.io 不一致，
    会走 Engine.IO not_found 并对 WebSocket 发送 HTTP 404，触发 ASGI RuntimeError。

    kmvpy 默认 mount_location=/ws、socketio_path=/socket.io，对外 URL 为 /ws/socket.io；
    将底层 ASGIApp.engineio_path 改为与该完整路径一致即可。
    """
    socket_manager = getattr(kosmos, "socketio", None)
    if socket_manager is None:
        return
    sio_asgi = getattr(socket_manager, "_app", None)
    if sio_asgi is None or not hasattr(sio_asgi, "engineio_path"):
        return
    # 与 kmvpy init_asgi_app 中 SocketManager 默认挂载及前端 path=/ws/socket.io 对齐
    sio_asgi.engineio_path = "/ws/socket.io/"


def gen_asgi_app(config_path: Annotated[Optional[str], "工程配置对象或配置类路径"] = None) -> FastAPI:
    """生成 ASGI 应用。异常处理、中间件等由 kmvpy.init_asgi_app 统一提供。"""
    resolved_config_path = get_config_path(config_path)
    config = AppConfig.load_config(resolved_config_path)
    has_database = config.get_default_storage_database_config() is not None
    UserSocketService.require_redis_for_production(config)
    install_kmvpy_auth_session_service()
    app = init_asgi_app(config, routers)
    _align_socketio_engineio_path_with_mount()
    UserSocketService.configure_distributed_socket_manager(config)
    register_user_socket_handlers()
    register_admin_socket_handlers()
    _existing_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def _lifespan(app_: FastAPI):
        if has_database:
            await init_tables()
            await init_default_admin_if_needed(config)
        async with _existing_lifespan(app_):
            register_app_schedule_jobs()
            yield

    app.router.lifespan_context = _lifespan
    return app
