from contextlib import asynccontextmanager
from typing import Annotated, Optional

from fastapi import FastAPI
from kmvpy.core.main import get_config_path, init_asgi_app

from __PROJECT_NAME__.common.auth_session import install_kmvpy_auth_session_service
from __PROJECT_NAME__.common.conf import AppConfig
from __PROJECT_NAME__.common.infra.orm import init_default_admin_if_needed, init_tables
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.core.main.schedule import (
    register_app_schedule_jobs,
)
from __PROJECT_NAME__.core.main.router import routers
from __PROJECT_NAME__.core.main.router.admin.socket import register_admin_socket_handlers
from __PROJECT_NAME__.core.main.router.user.socket import register_user_socket_handlers
from __PROJECT_NAME__.core.main.service.user.socket import UserSocketService


def gen_asgi_app(config_path: Annotated[Optional[str], "工程配置对象或配置类路径"] = None) -> FastAPI:
    """生成 ASGI 应用。异常处理、中间件等由 kmvpy.init_asgi_app 统一提供。"""
    resolved_config_path = get_config_path(config_path)
    config = AppConfig.load_config(resolved_config_path)
    has_database = config.get_default_storage_database_config() is not None
    UserSocketService.require_redis_for_production(config)
    install_kmvpy_auth_session_service()
    default_storage = DefaultStorage.instance(config)
    app = init_asgi_app(config, routers, storage=default_storage)
    from __PROJECT_NAME__.common.infra.realtime_http import RealtimeHttpMetrics
    from starlette.middleware.cors import CORSMiddleware
    app.add_middleware(RealtimeHttpMetrics)
    # Extend the existing CORS contract, including the development regex variant.
    for middleware in app.user_middleware:
        if middleware.cls is CORSMiddleware:
            middleware.kwargs['expose_headers'] = list(dict.fromkeys([
                *middleware.kwargs.get('expose_headers', []), 'X-Auth-Error', 'X-Auth-Role', 'Retry-After']))
    # Socket.IO runs outside FastAPI's CORS middleware. Apply the same origin policy.
    raw_socket = UserSocketService._raw_socketio_server()
    if raw_socket is not None:
        origins = list(getattr(config.service, 'cors_allow_origins', None) or [])
        local_development = config.general.debug or config.general.env in ('dev', 'development', 'develop', 'local')
        if local_development:
            import re
            raw_socket.eio.cors_allowed_origins = lambda origin, environ=None: origin in origins or bool(
                re.fullmatch(r'https?://(localhost|127\.0\.0\.1)(:\d+)?', origin or ''))
        else:
            raw_socket.eio.cors_allowed_origins = origins or None
    UserSocketService.configure_distributed_socket_manager(config)
    register_user_socket_handlers()
    register_admin_socket_handlers()
    _existing_lifespan = app.router.lifespan_context

    @asynccontextmanager
    async def _lifespan(app_: FastAPI):
        async with _existing_lifespan(app_):
            if has_database:
                await init_tables()
                await init_default_admin_if_needed(config)
            register_app_schedule_jobs()
            try:
                yield
            finally:
                from __PROJECT_NAME__.core.main.service.common.realtime import RealtimeService
                from __PROJECT_NAME__.core.main.hub.realtime import RealtimeHub
                for domain, sid in list(RealtimeHub.sessions):
                    await RealtimeService.disconnect(domain, sid)

    app.router.lifespan_context = _lifespan
    return app
