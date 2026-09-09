import contextlib
import inspect
import shlex
import weakref
from datetime import datetime
from typing import Any, AsyncIterator, Awaitable, Callable, Iterable, Literal, Sequence, TypeVar, cast
from zoneinfo import ZoneInfo

from sqlalchemy import func, select
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql import ColumnElement

from kmvpy.common.conf import DatabaseConfig, RedisConfig
from kmvpy.common.infra.korm_base import KOrmBase
from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.exception.kmv_error import KmvError
from kmvpy.common.tool.logger import logger

ModelT = TypeVar("ModelT", bound=KOrmBase)
ResultT = TypeVar("ResultT")
SortDir = Literal["asc", "desc"]
_POSTGRES_TIMEZONE_OPTION = "timezone="

try:
    from sqlalchemy.ext.asyncio import AsyncEngine
    from sqlalchemy.ext.asyncio import async_sessionmaker as AsyncSessionMaker

    SQLAlchemySessionType = AsyncSessionMaker[AsyncSession]
    SQLAlchemyEngineType = AsyncEngine
except ImportError:
    SQLAlchemySessionType = Any
    SQLAlchemyEngineType = Any

try:
    from redis.asyncio import Redis as AsyncRedis

    RedisClientType = AsyncRedis
except ImportError:
    RedisClientType = Any


def _get_order_by_whitelist(model: type[ModelT]) -> set[str]:
    """
    获取排序白名单字段集合。

    约定：
    - 若 model 显式定义 `__order_by_whitelist__`（可迭代字符串），则使用它；
    - 否则默认放行该 model 的所有列名（来自 `__table__.columns.keys()`），作为“自动白名单”。
      这样既能防注入（不拼接 SQL 文本），又避免强制要求每个 model 都显式声明。
    """
    explicit = getattr(model, "__order_by_whitelist__", None)
    if explicit:
        try:
            return set(cast(Iterable[str], explicit))
        except Exception:
            # 显式配置格式异常，降级为自动白名单
            pass

    try:
        return set(cast(Any, model).__table__.columns.keys())
    except Exception:
        # 极端情况下 model 非标准 declarative model
        return {"id"}


def _build_order_by_exprs(
    model: type[ModelT],
    sort: Sequence[tuple[str, SortDir]] | None,
    *,
    default_sort: Sequence[tuple[str, SortDir]] = (("id", "desc"),),
) -> list[ColumnElement[Any]]:
    """
    将结构化 sort 转换为 SQLAlchemy order_by 表达式列表（安全，不使用 text()）。

    - sort: [("field", "asc"|"desc"), ...]
    - default_sort: sort 为空时使用的默认排序
    """
    spec = sort if sort else default_sort
    whitelist = _get_order_by_whitelist(model)

    exprs: list[ColumnElement[Any]] = []
    for field, direction in spec:
        if field not in whitelist:
            raise KmvException(error=KmvError.PARAMETER_ERROR)
        col = getattr(model, field, None)
        if col is None:
            raise KmvException(error=KmvError.PARAMETER_ERROR)

        if direction == "asc":
            exprs.append(col.asc())
        elif direction == "desc":
            exprs.append(col.desc())
        else:
            raise KmvException(error=KmvError.PARAMETER_ERROR)
    return exprs


def _maybe_decode_redis_value(val: Any) -> str | None:
    if val is None:
        return None
    if isinstance(val, bytes):
        return val.decode("utf-8")
    if isinstance(val, str):
        return val
    return str(val)


def _normalize_instances(instances: Iterable[ModelT] | None) -> list[ModelT]:
    """
    将传入的 instances 归一化为 list，且过滤掉 None（更宽容，避免上游拼装列表时误塞入 None）。
    """
    if not instances:
        return []
    return [x for x in instances if x is not None]


def _parse_postgresql_server_settings(options: str) -> dict[str, str]:
    if not options:
        return {}

    server_settings: dict[str, str] = {}
    tokens = shlex.split(options)
    index = 0

    while index < len(tokens):
        token = tokens[index]
        setting = ""

        if token == "-c" and index + 1 < len(tokens):
            setting = tokens[index + 1]
            index += 2
        elif token.startswith("-c") and len(token) > 2:
            setting = token[2:]
            index += 1
        else:
            index += 1
            continue

        key, sep, value = setting.partition("=")
        if sep and key:
            server_settings[key.strip()] = value.strip()

    return server_settings


def _build_postgresql_options(options: str, timezone: str) -> str:
    timezone_setting = f"{_POSTGRES_TIMEZONE_OPTION}{timezone}"
    if not options:
        return f"-c {timezone_setting}"

    tokens = shlex.split(options)
    normalized_tokens: list[str] = []
    timezone_applied = False
    index = 0

    while index < len(tokens):
        token = tokens[index]

        if token == "-c" and index + 1 < len(tokens):
            setting = tokens[index + 1]
            normalized_tokens.append(token)
            if setting.startswith(_POSTGRES_TIMEZONE_OPTION):
                normalized_tokens.append(timezone_setting)
                timezone_applied = True
            else:
                normalized_tokens.append(setting)
            index += 2
            continue

        if token.startswith(f"-c{_POSTGRES_TIMEZONE_OPTION}"):
            normalized_tokens.append(f"-c{timezone_setting}")
            timezone_applied = True
            index += 1
            continue

        normalized_tokens.append(token)
        index += 1

    if not timezone_applied:
        normalized_tokens.extend(["-c", timezone_setting])

    return " ".join(shlex.quote(token) for token in normalized_tokens)


def _build_postgresql_connect_args(
    database_config: DatabaseConfig,
    driver_name: str,
    timezone: str,
) -> dict[str, Any]:
    connect_args: dict[str, Any] = {"timeout": database_config.timeout}

    if database_config.ssl:
        connect_args["ssl"] = database_config.ssl

    if driver_name == "asyncpg":
        server_settings = _parse_postgresql_server_settings(database_config.options)
        server_settings["timezone"] = timezone
        connect_args["server_settings"] = server_settings
    else:
        connect_args["options"] = _build_postgresql_options(
            database_config.options,
            timezone,
        )

    return connect_args


def _build_mysql_connect_args(
    database_config: DatabaseConfig,
    timezone_name: str,
) -> dict[str, Any]:
    connect_args: dict[str, Any] = {
        "connect_timeout": database_config.timeout,
    }

    timezone = ZoneInfo(timezone_name)
    offset = datetime.now(timezone).utcoffset()
    if offset is None:
        return connect_args

    total_minutes = int(offset.total_seconds() // 60)
    sign = "+" if total_minutes >= 0 else "-"
    abs_minutes = abs(total_minutes)
    hours, minutes = divmod(abs_minutes, 60)
    # MySQL 使用 UTC offset 避免依赖服务端加载 named time zone tables。
    connect_args["init_command"] = (
        f"SET time_zone = '{sign}{hours:02d}:{minutes:02d}'"
    )

    return connect_args


class KOrmStorage:
    """
    可实例化的通用 Storage 基类。

    通过显式注入数据库与缓存配置，支持为不同数据库构建不同的 Storage 实例。
    多数据库场景下，可为每个数据库创建独立的 KOrmStorage 实例。
    """

    def __init__(
        self,
        database_config: DatabaseConfig | None = None,
        redis_config: RedisConfig | None = None,
        timezone: str = "Asia/Shanghai",
    ) -> None:
        self.database_config = database_config
        self.redis_config = redis_config
        self.timezone = timezone
        self._db_session: SQLAlchemySessionType | None = None
        self._engine: SQLAlchemyEngineType | None = None
        self._tracked_sessions: weakref.WeakSet[Any] = weakref.WeakSet()
        self._redis_client_instance: RedisClientType | None = None

    def has_db_session(self) -> bool:
        return self._db_session is not None

    @property
    def engine(self) -> SQLAlchemyEngineType:
        if self._engine is None:
            raise RuntimeError(
                "Database engine is not initialized. Please initialize it during app startup."
            )
        return self._engine

    @property
    def db_session(self) -> SQLAlchemySessionType:
        if self._db_session is None:
            raise RuntimeError(
                "Database session is not initialized. Please initialize it during app startup."
            )
        return self._db_session

    def set_db_session(self, db_session: SQLAlchemySessionType) -> None:
        def _tracked_session_factory():
            session = db_session()
            self._tracked_sessions.add(session)
            return session

        self._db_session = _tracked_session_factory

    def init_db_session(self) -> SQLAlchemySessionType:
        if self._db_session is not None:
            return self._db_session
        if self.database_config is None:
            raise RuntimeError("Database config is not initialized.")

        try:
            from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

            sqlalchemy_url = make_url(self.database_config.url)
            backend_name = sqlalchemy_url.get_backend_name().lower()
            driver_name = sqlalchemy_url.get_driver_name().lower()
            engine_kwargs: dict[str, Any] = {
                "echo": self.database_config.echo,
            }
            connect_args: dict[str, Any] = {}

            if backend_name == "postgresql":
                engine_kwargs.update(
                    pool_size=self.database_config.pool_size,
                    max_overflow=self.database_config.max_overflow,
                    pool_recycle=self.database_config.pool_recycle,
                    pool_pre_ping=self.database_config.pool_pre_ping,
                )
                connect_args.update(
                    _build_postgresql_connect_args(
                        self.database_config,
                        driver_name,
                        self.timezone,
                    )
                )
            elif backend_name == "mysql":
                engine_kwargs.update(
                    pool_size=self.database_config.pool_size,
                    max_overflow=self.database_config.max_overflow,
                    pool_recycle=self.database_config.pool_recycle,
                    pool_pre_ping=self.database_config.pool_pre_ping,
                )
                connect_args.update(
                    _build_mysql_connect_args(self.database_config, self.timezone)
                )
            elif backend_name == "sqlite":
                from sqlalchemy.pool import StaticPool

                connect_args["timeout"] = self.database_config.timeout
                if (sqlalchemy_url.database or "").strip().lower() == ":memory:":
                    engine_kwargs["poolclass"] = StaticPool
            else:
                engine_kwargs.update(
                    pool_size=self.database_config.pool_size,
                    max_overflow=self.database_config.max_overflow,
                    pool_recycle=self.database_config.pool_recycle,
                    pool_pre_ping=self.database_config.pool_pre_ping,
                )

            if connect_args:
                engine_kwargs["connect_args"] = connect_args

            self._engine = create_async_engine(
                self.database_config.url, **engine_kwargs)

            session_factory = async_sessionmaker(
                bind=self._engine,
                expire_on_commit=False,
                class_=AsyncSession,
            )
            self.set_db_session(session_factory)
            return self.db_session
        except (NameError, ModuleNotFoundError, ImportError) as e:
            logger.error(e)
            raise RuntimeError("SQLAlchemy is not installed") from e

    async def _close_tracked_sessions(self) -> None:
        tracked_sessions = list(self._tracked_sessions)
        self._tracked_sessions = weakref.WeakSet()
        for session in tracked_sessions:
            close_fn = getattr(session, "aclose", None) or getattr(
                session, "close", None)
            if close_fn is None:
                continue
            try:
                res = close_fn()
                if inspect.isawaitable(res):
                    await res
            except Exception as e:
                logger.warning("关闭数据库会话失败: %s", e, exc_info=e)

    async def dispose(self) -> None:
        if self._engine is not None:
            await self._close_tracked_sessions()
            await self._engine.dispose()
            self._engine = None

        self._db_session = None
        self._tracked_sessions = weakref.WeakSet()
        await self.dispose_redis()

    def has_redis_client(self) -> bool:
        return self._redis_client_instance is not None

    @property
    def redis_client(self) -> RedisClientType:
        if self._redis_client_instance is None:
            raise RuntimeError(
                "Redis client is not initialized. Please initialize it during app startup."
            )
        return self._redis_client_instance

    def set_redis_client(self, redis_client: RedisClientType) -> None:
        self._redis_client_instance = redis_client

    def init_redis_client(self) -> RedisClientType:
        if self._redis_client_instance is not None:
            return self._redis_client_instance
        if self.redis_config is None:
            raise RuntimeError("Redis config is not initialized.")

        try:
            import redis.asyncio as redis

            self._redis_client_instance = redis.Redis(**self.redis_config.model_dump())
            return self._redis_client_instance
        except (NameError, ModuleNotFoundError, ImportError) as e:
            logger.error(e)
            raise RuntimeError("Redis is not installed") from e

    async def dispose_redis(self) -> None:
        if self._redis_client_instance is None:
            return

        client = self._redis_client_instance
        self._redis_client_instance = None

        close_fn = getattr(client, "aclose", None) or getattr(client, "close", None)
        if close_fn:
            res = close_fn()
            if inspect.isawaitable(res):
                await res

        pool = getattr(client, "connection_pool", None)
        disconnect = getattr(pool, "disconnect", None) if pool is not None else None
        if disconnect:
            res = disconnect()
            if inspect.isawaitable(res):
                await res

    @contextlib.asynccontextmanager
    async def session_scope(self) -> AsyncIterator[AsyncSession]:
        async with self.db_session() as session:
            async with session.begin():
                yield cast(AsyncSession, session)

    async def _run_with_session(
        self,
        runner: Callable[[AsyncSession], Awaitable[ResultT]],
        session: AsyncSession | None = None,
    ) -> ResultT:
        if session is not None:
            return await runner(session)

        async with self.session_scope() as sess:
            return await runner(sess)

    def _default_cache_name(self, model: type[ModelT]) -> str:
        return f"{self.__class__.__name__}.{model.__tablename__}"

    def _redis_client(self) -> Any | None:
        if not self.has_redis_client():
            return None
        return self.redis_client

    async def cache_hget(
        self,
        model: type[ModelT],
        key: Any,
        *,
        name: str | None = None,
    ) -> ModelT | None:
        redis_client = self._redis_client()
        if redis_client is None:
            return None

        cached = await redis_client.hget(
            name=name or self._default_cache_name(model),
            key=key,
        )
        cached_text = _maybe_decode_redis_value(cached)
        if cached_text is None:
            return None

        try:
            return cast(ModelT, model.from_json(cached_text))
        except Exception as e:
            logger.error(f"缓存脏数据: {cached_text}", exc_info=e)
            raise

    async def cache_hset(
        self,
        model: type[ModelT],
        key: Any,
        value: ModelT,
        *,
        name: str | None = None,
    ) -> Any:
        redis_client = self._redis_client()
        if redis_client is None:
            return None

        return await redis_client.hset(
            name=name or self._default_cache_name(model),
            key=key,
            value=value.to_json(),
        )

    async def cache_hdel(
        self,
        model: type[ModelT],
        key: Any,
        *,
        name: str | None = None,
    ) -> Any:
        redis_client = self._redis_client()
        if redis_client is None:
            return None

        return await redis_client.hdel(
            name=name or self._default_cache_name(model),
            key=key,
        )

    async def _cache_put_instance(self, instance: ModelT, *, use_cache: bool) -> None:
        if not use_cache:
            return
        if getattr(instance, "kid", None):
            await self.cache_hset(
                model=type(instance),
                key=instance.kid,
                value=instance,
            )

    async def _cache_put_instance_if_has_kid(
        self,
        instance: ModelT,
        *,
        use_cache: bool,
    ) -> None:
        if not use_cache:
            return
        if hasattr(instance, "kid") and getattr(instance, "kid", None) is not None:
            await self.cache_hset(
                model=type(instance),
                key=instance.kid,
                value=instance,
            )

    async def _cache_del_instance(self, instance: ModelT, *, use_cache: bool) -> None:
        if not use_cache:
            return
        if hasattr(instance, "kid") and getattr(instance, "kid", None):
            await self.cache_hdel(
                model=type(instance),
                key=instance.kid,
            )

    async def get(
        self,
        model: type[ModelT],
        id: Any,
        with_for_update: bool = False,
        session: AsyncSession | None = None,
    ) -> ModelT | None:
        if id is None:
            return None
        if isinstance(id, tuple):
            id, = id

        async def _run(sess: AsyncSession) -> ModelT | None:
            stmt = select(model).filter_by(id=id)
            if with_for_update:
                stmt = stmt.with_for_update()
            return (await sess.execute(stmt)).scalars().first()

        return await self._run_with_session(_run, session)

    async def get_by_kid(
        self,
        model: type[ModelT],
        kid: Any,
        with_for_update: bool = False,
        use_cache: bool = False,
        session: AsyncSession | None = None,
    ) -> ModelT | None:
        if kid is None:
            return None
        if isinstance(kid, tuple):
            kid, = kid

        if use_cache:
            cached = await self.cache_hget(model=model, key=kid)
            if cached is not None:
                return cached

        async def _run(sess: AsyncSession) -> ModelT | None:
            stmt = select(model).filter_by(kid=kid)
            if with_for_update:
                stmt = stmt.with_for_update()
            obj = (await sess.execute(stmt)).scalars().first()
            if obj:
                try:
                    await self.cache_hset(
                        model=model,
                        key=kid,
                        value=cast(ModelT, obj),
                    )
                except Exception as e:
                    # 缓存写失败不影响主流程
                    logger.error(f"缓存写失败: {kid}", exc_info=e)
                    raise
            return cast(ModelT, obj)

        return await self._run_with_session(_run, session)

    async def get_by_condition(
        self,
        model: type[ModelT],
        with_for_update: bool = False,
        sort: Sequence[tuple[str, SortDir]] | None = None,
        session: AsyncSession | None = None,
        **condition: Any,
    ) -> ModelT | None:
        """
        按等值条件（kwargs）查询单条记录（取排序后的第一条）。

        说明：
        - 该方法是便捷入口，适合简单的 `field=value` 组合过滤；
        - 排序使用统一的安全 sort 机制（白名单 + asc/desc 映射），不接受原始 SQL 文本。
        """
        if condition is None or not isinstance(condition, dict):
            return None

        order_by_exprs = _build_order_by_exprs(model, sort)

        async def _run(sess: AsyncSession) -> ModelT | None:
            stmt = select(model).filter_by(**condition).order_by(*order_by_exprs)
            if with_for_update:
                stmt = stmt.with_for_update()
            return (await sess.execute(stmt)).scalars().first()

        return await self._run_with_session(_run, session)

    async def get_by_filters(
        self,
        model: type[ModelT],
        filters: tuple,
        with_for_update: bool = False,
        sort: Sequence[tuple[str, SortDir]] | None = None,
        session: AsyncSession | None = None,
    ) -> ModelT | None:
        """
        按 SQLAlchemy 表达式 filters 查询单条记录（取排序后的第一条）。

        说明：
        - 与 `gets_by_filters` 保持一致：filters 为 tuple，内部通过 `.filter(*filters)` 应用。
        """
        if filters is None:
            return None

        order_by_exprs = _build_order_by_exprs(model, sort)

        async def _run(sess: AsyncSession) -> ModelT | None:
            stmt = select(model).filter(*filters).order_by(*order_by_exprs)
            if with_for_update:
                stmt = stmt.with_for_update()
            return (await sess.execute(stmt)).scalars().first()

        return await self._run_with_session(_run, session)

    async def gets_in_ids(
        self,
        model: type[ModelT],
        ids: list,
        sort: Sequence[tuple[str, SortDir]] | None = None,
        session: AsyncSession | None = None,
    ) -> list[ModelT] | None:
        if ids is None:
            return None
        order_by_exprs = _build_order_by_exprs(model, sort)

        async def _run(sess: AsyncSession) -> list[ModelT]:
            stmt = (
                select(model)
                .filter(getattr(model, "id").in_(ids))
                .order_by(*order_by_exprs)
            )
            return cast(list[ModelT], (await sess.execute(stmt)).scalars().all())

        return await self._run_with_session(_run, session)

    async def gets_in_kids(
        self,
        model: type[ModelT],
        kids: list,
        sort: Sequence[tuple[str, SortDir]] | None = None,
        session: AsyncSession | None = None,
    ) -> list[ModelT] | None:
        if kids is None:
            return None
        order_by_exprs = _build_order_by_exprs(model, sort)

        async def _run(sess: AsyncSession) -> list[ModelT]:
            stmt = (
                select(model)
                .filter(getattr(model, "kid").in_(kids))
                .order_by(*order_by_exprs)
            )
            return cast(list[ModelT], (await sess.execute(stmt)).scalars().all())

        return await self._run_with_session(_run, session)

    async def gets_by_filters(
        self,
        model: type[ModelT],
        filters: tuple,
        page: int,
        size: int,
        sort: Sequence[tuple[str, SortDir]] | None = None,
        session: AsyncSession | None = None,
    ) -> tuple[list[ModelT], int] | None:
        if filters is None:
            return None
        order_by_exprs = _build_order_by_exprs(model, sort)
        offset = max(page - 1, 0) * size

        async def _run(sess: AsyncSession) -> tuple[list[ModelT], int]:
            stmt = (
                select(model)
                .filter(*filters)
                .order_by(*order_by_exprs)
                .offset(offset)
                .limit(size)
            )
            items = (await sess.execute(stmt)).scalars().all()
            total_stmt = select(func.count(getattr(model, "id"))).filter(*filters)
            total = await sess.scalar(total_stmt)
            return cast(list[ModelT], items), int(total or 0)

        return await self._run_with_session(_run, session)

    async def get_sums(
        self,
        fields: list,
        filters: tuple,
        session: AsyncSession | None = None,
    ) -> list | None:
        if filters is None:
            return None

        async def _run(sess: AsyncSession) -> list:
            stmt = select(*[func.sum(x) for x in fields]).filter(*filters)
            return list((await sess.execute(stmt)).all())

        return await self._run_with_session(_run, session)

    async def delete_by_kid(
        self,
        model: type[ModelT],
        kid: str,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        if not kid:
            raise KmvException(error=KmvError.PARAMETER_ERROR)
        instance = await self.get_by_kid(
            model=model,
            kid=kid,
            session=session,
            use_cache=False,
        )
        if instance is None:
            return
        await self.delete(instance=instance, use_cache=use_cache, session=session)

    async def save(
        self,
        instance: ModelT,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        instance.del_kid_if_none()

        async def _run(sess: AsyncSession) -> None:
            await sess.merge(instance)
            await self._cache_put_instance(instance, use_cache=use_cache)

        await self._run_with_session(_run, session)

    async def add(
        self,
        instance: ModelT,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        instance.del_kid_if_none()

        async def _run(sess: AsyncSession) -> None:
            sess.add(instance)
            await self._cache_put_instance_if_has_kid(instance, use_cache=use_cache)

        await self._run_with_session(_run, session)

    async def delete(
        self,
        instance: ModelT,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        instance.del_kid_if_none()

        async def _run(sess: AsyncSession) -> None:
            await sess.delete(instance)
            await self._cache_del_instance(instance, use_cache=use_cache)

        await self._run_with_session(_run, session)

    async def save_many(
        self,
        instances: Iterable[ModelT] | None,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        """
        批量“保存”（merge/upsert）多个 ORM 实例。

        说明：
        - `instances` 允许混合不同 `KOrmBase` 子类；SQLAlchemy 会自动路由到各自的表。
        - 参数与单体版 `save(instance, use_cache, session)` 保持一致。
        """
        items = _normalize_instances(instances)
        if not items:
            return

        for inst in items:
            inst.del_kid_if_none()

        async def _run(sess: AsyncSession) -> None:
            for inst in items:
                await sess.merge(inst)
                await self._cache_put_instance(inst, use_cache=use_cache)

        await self._run_with_session(_run, session)

    async def add_many(
        self,
        instances: Iterable[ModelT] | None,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        """
        批量“新增”多个 ORM 实例（等价于对每个元素执行 `sess.add()`）。

        说明：
        - `instances` 允许混合不同 `KOrmBase` 子类；SQLAlchemy 会自动路由到各自的表。
        - 参数与单体版 `add(instance, use_cache, session)` 保持一致。
        """
        items = _normalize_instances(instances)
        if not items:
            return

        for inst in items:
            inst.del_kid_if_none()

        async def _run(sess: AsyncSession) -> None:
            sess.add_all(items)
            for inst in items:
                await self._cache_put_instance_if_has_kid(inst, use_cache=use_cache)

        await self._run_with_session(_run, session)

    async def delete_many(
        self,
        instances: Iterable[ModelT] | None,
        use_cache: bool = True,
        session: AsyncSession | None = None,
    ) -> None:
        """
        批量删除多个 ORM 实例（等价于对每个元素执行 `await sess.delete()`）。

        说明：
        - `instances` 允许混合不同 `KOrmBase` 子类；SQLAlchemy 会自动路由到各自的表。
        - 参数与单体版 `delete(instance, use_cache, session)` 保持一致。
        """
        items = _normalize_instances(instances)
        if not items:
            return

        for inst in items:
            inst.del_kid_if_none()

        async def _run(sess: AsyncSession) -> None:
            for inst in items:
                await sess.delete(inst)
                await self._cache_del_instance(inst, use_cache=use_cache)

        await self._run_with_session(_run, session)


# 兼容历史错误拼写，避免旧工程导入失败。
KOrmDoamin = KOrmStorage
