"""
KMVPy ASGI 应用入口（FastAPI）与生命周期管理。

本模块主要提供：
- `get_config_path`：按“显式参数 > 命令行参数 > 当前目录 config.yaml”解析配置文件路径
- `init_asgi_app`：基于配置创建 FastAPI，并初始化日志、i18n、Socket.IO、路由与异常处理
- 应用 lifespan：在应用启动/关闭阶段初始化与释放显式传入的 Storage（DB/Redis 连接池等）

## 工程侧：启动时初始化数据库表结构（可选）

KMVPy 默认会在 `lifespan` 里通过 infra/storage 层初始化数据库连接池，
但**不会**自动创建/同步表结构。若你希望服务启动时根据 ORM 模型自动建表/同步结构，
可以在工程中调用 `kmvpy.common.infra.init_tables_by_orms` 并把它挂到 FastAPI lifespan 中。

### `init_tables_by_orms` 的入参约束

- `db_config.url` 必须使用 SQLAlchemy **异步** driver（与 `DatabaseConfig.init_db_session` 一致），例如：
  - PostgreSQL：`postgresql+asyncpg://...`
  - MySQL：`mysql+aiomysql://...`
  - SQLite：`sqlite+aiosqlite:///...`
- `orm_package_or_models` 仅支持传入 ORM 模型类列表（工程侧需显式把要初始化的表结构交给 kmvpy）

### 不同数据库方言的行为差异（重要）

- **MySQL**：会尝试对已存在表做列级 diff/ALTER（包含添加列、修改列）并同步新增索引；
  生产环境请谨慎评估（更推荐用 Alembic 迁移）。
- **非 MySQL**（PostgreSQL/SQLite 等）：表不存在时自动建表；检测到 ORM 新增字段时自动补列，
  并尽量保留 ORM 声明的默认值；检测到数据库中存在 ORM 未声明字段时仅输出明确告警，不自动删除。

### 推荐的工程组织方式（可直接照抄）

1) 在工程里提供一个薄封装 `init_tables`，把 `orm_package_or_models` 固定为模型列表；
2) 在 app 工厂函数（例如 `gen_asgi_app`）里将 `init_tables` 挂到 FastAPI lifespan 中，
   确保服务开始接收请求前只执行一次表结构初始化。

示例（工程侧 `my_app/core/main/__init__.py`）：

```python
import contextlib
from typing import Optional

from fastapi import FastAPI

from kmvpy.common.infra import init_tables_by_orms
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.conf import BaseConfig
from kmvpy.core.main import get_config_path, init_asgi_app


async def init_tables(storage: KOrmStorage) -> None:
    # 显式传入要初始化的 ORM 模型
    await init_tables_by_orms(storage, [User, UserProfile])


def gen_asgi_app(config_path: Optional[str] = None) -> FastAPI:
    # 1) 读取配置（你也可以用自己的 BaseConfig 子类）
    config = BaseConfig.load_config(get_config_path(config_path))

    # 2) 显式创建 Storage，并交给 KMVPy 管理 startup/shutdown
    database_config = config.get_default_storage_database_config()
    if database_config:
        storage = KOrmStorage(
            database_config=database_config,
            redis_config=config.get_default_storage_redis_config(),
            timezone=config.timezone,
        )
        app = init_asgi_app(config, routers=[...], storage=storage)
        _existing_lifespan = app.router.lifespan_context

        @contextlib.asynccontextmanager
        async def _lifespan(app_: FastAPI):
            async with _existing_lifespan(app_):
                await init_tables(storage)
                yield

        app.router.lifespan_context = _lifespan
    else:
        app = init_asgi_app(config, routers=[...])

    return app
```

启动方式（uvicorn 工厂模式）：
`uvicorn my_app.core.main:gen_asgi_app --factory --host 0.0.0.0 --port 8000`
"""

import argparse
import contextlib
from datetime import datetime
from pathlib import Path
from typing import Annotated, Optional

import i18n
from fastapi import FastAPI, Request, APIRouter, HTTPException
from fastapi.exceptions import RequestValidationError
from starlette.responses import JSONResponse
from starlette.middleware.cors import CORSMiddleware

from kmvpy.common.conf import BaseConfig
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.kmv import kosmos
from kmvpy.common.response import ApiResponse
from kmvpy.common.tool.logger import init_logger, logger
from kmvpy.core.main.router.socketio import socketio_bind_router
from kmvpy.core.main.service.auth_session_service import AuthSessionService

with contextlib.suppress(Exception):
    from fastapi_socketio import SocketManager


def _build_lifespan(storage: KOrmStorage):
    @contextlib.asynccontextmanager
    async def lifespan(app: FastAPI):
        """
        初始化并释放当前 FastAPI 应用显式持有的 Storage。
        """
        schedule_manager = None
        if storage.database_config and not storage.has_db_session():
            storage.init_db_session()
        if storage.redis_config and not storage.has_redis_client():
            storage.init_redis_client()

        # 初始化定时任务调度器。调度配置现在直接由各个 Schedule 子类声明。
        try:
            from kmvpy.common.schedule import ScheduleManager

            schedule_manager = ScheduleManager
            await schedule_manager.start()
            kosmos.schedule_manager = schedule_manager
            logger.info('定时任务调度器已启动')
        except Exception as e:
            logger.error(f'初始化定时任务调度器失败: {e}')

        try:
            yield
        finally:
            # 应用退出：先停后台任务，再释放连接，避免任务继续占用会话/连接。
            with contextlib.suppress(Exception):
                if schedule_manager is not None:
                    await schedule_manager.shutdown()
                    logger.info('定时任务调度器已关闭')
            with contextlib.suppress(Exception):
                await storage.dispose()

    return lifespan


def get_config_path(config_path: Optional[str] = None):
    """
    获取配置文件路径的函数，采用多层级查找策略

    查找逻辑如下：
    1. 直接参数优先级：如果传入了config_path参数（非None），则使用这个参数，如果参数对应的文件名不存在要直接抛出异常
    2. 命令行参数次优先级：如果没有传入参数（None），再获取命令行参数传入的地址
    3. 当前工作目录最后：如果命令行没有传入地址，就获取执行启动命令时终端所在地址的config.yaml文件作为地址

    Args:
        config_path: 直接传入的配置文件路径，默认为None

    Returns:
        Path: 配置文件的路径对象

    Raises:
        FileNotFoundError: 当指定的所有路径都不存在时抛出此异常
    """
    # 多层级配置文件路径获取策略
    _config_path = None

    # 1. 直接参数优先级：如果传入了config_path参数（非None），则使用这个参数
    if config_path is not None:
        _config_path = Path(config_path)
        # 检查配置文件是否存在
        if not _config_path.exists():
            raise FileNotFoundError(f"配置文件不存在: {_config_path}")
        return _config_path
    else:
        # 2. 命令行参数次优先级：如果没有传入参数（None），再获取命令行参数传入的地址
        # 创建命令行参数解析器
        parser = argparse.ArgumentParser(description='启动应用服务')
        parser.add_argument('--config', '-c', type=str, help='配置文件路径')
        args = parser.parse_args()

        if args.config:
            _config_path = Path(args.config)
            # 检查配置文件是否存在
            if not _config_path.exists():
                raise FileNotFoundError(f"配置文件不存在: {_config_path}")
            return _config_path
        else:
            # 3. 当前工作目录最后：如果命令行没有传入地址，就获取执行启动命令时终端所在地址的config.yaml文件作为地址
            _config_path = Path.cwd() / "config.yaml"

            # 检查配置文件是否存在
            if not _config_path.exists():
                raise FileNotFoundError(f"配置文件不存在: {_config_path}")

            return _config_path


def init_asgi_app(
    config: Annotated[BaseConfig, '工程配置对象'],
    routers: Annotated[list[APIRouter], '路由列表'] = None,
    storage: Annotated[KOrmStorage | None, '由应用持有的 Storage 实例'] = None,
) -> FastAPI:
    resolved_storage = storage or KOrmStorage(
        database_config=config.get_default_storage_database_config(),
        redis_config=config.get_default_storage_redis_config(),
        timezone=config.timezone,
    )
    app = FastAPI(
        debug=config.general.debug,
        lifespan=_build_lifespan(resolved_storage),
    )

    # 保存全局配置到全局变量
    kosmos.config = config
    # 日志
    init_logger(debug=config.general.debug,
                level=config.logging.level,
                logger_path=config.logging.path,
                _format=config.logging.format,
                max_bytes=config.logging.max_bytes,
                backup_count=config.logging.backup_count)

    """
    国际化i18n
    """
    i18n.load_path.append(config.i18n.path)
    i18n.set('file_format', 'json')
    i18n.set('enable_memoization', True)
    # i18n.set('filename_format', '{locale}.{format}')
    i18n.set('skip_locale_root_data', True)
    i18n.set('locale', config.i18n.locale)

    # 初始化socketio
    try:
        socketio = SocketManager(
            app=app, mount_location='/ws', socketio_path='/socket.io', cors_allowed_origins=[])
        kosmos.socketio = socketio
        socketio_bind_router(socketio=socketio, storage=resolved_storage)
    except Exception as e:
        logger.error(e)

    # 绑定路由
    if routers:
        for __router in routers:
            app.include_router(__router)

    # 使用配置的 CORS 允许来源列表（如 https://sucai.tuta.icu），不设则不添加
    if config.service and config.service.cors_allow_origins:
        if "*" in config.service.cors_allow_origins:
            raise ValueError("带凭证请求的 CORS allow_origins 不能使用通配 origin")
        app.add_middleware(
            CORSMiddleware,
            allow_origins=config.service.cors_allow_origins,
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
            expose_headers=["X-Auth-Token", "X-Auth-Token-Type", "X-Auth-Expires-At"],
        )
    # debug/dev 模式下支持跨域访问（仅允许本地源，且支持带凭证请求）
    if config.general.debug or config.general.env in ("dev", "development"):
        """
        Cross-Origin Resource Sharing（仅用于 debug/dev 环境）
        跨域访问：使用正则匹配本地开发源，以便在开启 credentials 时符合 CORS 规范。
        """
        # 使用 allow_origin_regex 匹配本地开发源（任意端口），既支持凭证又避免生产环境误开。
        app.add_middleware(
            CORSMiddleware,
            allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
            allow_credentials=True,
            allow_methods=["*"],
            allow_headers=["*"],
            expose_headers=["X-Auth-Token", "X-Auth-Token-Type", "X-Auth-Expires-At"],
        )

    @app.exception_handler(KmvException)
    async def _handle_kmv_exception(request: Request, exc: KmvException):
        # 业务异常属于“可预期错误”，默认不打印（避免污染日志/误报）。
        # 如需排查，可将日志级别调到 DEBUG 观察该类异常的请求上下文。
        logger.info(
            "[KmvException] %s %s - %s", request.method, request.url.path, exc
        )
        return ApiResponse.error_response(exc)

    @app.exception_handler(RequestValidationError)
    async def _handle_validation_error(request: Request, exc: RequestValidationError):
        logger.warning(
            f"[ValidationError] {request.method} {request.url.path} - {exc}")
        return ApiResponse.error_response(
            KmvException([10400, "参数校验失败", ""], more_msg=str(exc))
        )

    # HTTPException 不在此处理，直接由 FastAPI/Starlette 按默认行为返回对应 HTTP 状态与 body，
    # 便于前端根据状态码做特殊响应（如 401 跳转登录页）。

    @app.exception_handler(Exception)
    async def _handle_unhandled_exception(request: Request, exc: Exception):
        logger.exception(
            f"[UnhandledException] {request.method} {request.url.path} - {exc}")
        return ApiResponse.error_response(exc)

    # 常见的扫描/攻击路径，用于中间件过滤 404 日志
    _suspicious_paths = frozenset({
        '/.env', '/.git/config', '/.git/HEAD', '/.git/index', '/.git/logs', '/.git/refs', '/.git/objects',
        '/.svn/entries', '/.DS_Store', '/wp-admin', '/wp-login.php', '/phpmyadmin', '/admin',
        '/.htaccess', '/.htpasswd', '/config.php', '/web.config', '/.idea', '/.vscode',
    })

    @app.middleware("http")
    async def _middleware(request: Request, call_next):
        """请求访问日志；对默认可疑路径的 404 请求不记录日志。"""
        start_time = datetime.now()
        _response = await call_next(request)
        try:
            await AuthSessionService.renew_from_request_state(request, _response)
        except HTTPException as exc:
            error_response = JSONResponse(
                status_code=exc.status_code,
                content={"detail": exc.detail},
                headers=exc.headers,
            )
            candidate = getattr(request.state, "auth_renew_candidate", {})
            auth_role = candidate.get("auth_role") if isinstance(candidate, dict) else None
            if auth_role in {"user", "admin"}:
                AuthSessionService._clear_session_cookie(error_response, auth_role=auth_role)
            _response = error_response
        end_time = datetime.now()
        client_host = request.client.host if request.client else "unknown"
        path = request.url.path
        is_suspicious = any(path.startswith(p) or path ==
                            p for p in _suspicious_paths)
        if is_suspicious and _response.status_code == 404:
            pass  # 不记录可疑 404 请求日志
        else:
            logger.info(
                f"{_response.status_code} {client_host} {request.method} {request.url} {end_time - start_time}"
            )
        return _response

    return app
