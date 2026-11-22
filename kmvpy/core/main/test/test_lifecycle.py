import asyncio

from kmvpy.common.conf import BaseConfig, DatabaseConfig, RedisConfig
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.schedule import ScheduleManager
from kmvpy.core.main import init_asgi_app


def test_init_asgi_app_does_not_eagerly_open_database_connections():
    config = BaseConfig.model_validate(
        {
            "general": {"debug": True, "env": "test"},
            "logging": {"level": "INFO"},
            "i18n": {"path": ".", "locale": "zh-CN"},
            "default_storage": {
                "database": {"url": "sqlite+aiosqlite:///:memory:"},
            },
        }
    )

    init_asgi_app(config, routers=[])

    database_config = config.get_default_storage_database_config()
    redis_config = config.get_default_storage_redis_config()
    assert database_config is not None
    assert not hasattr(database_config, "has_db_session")
    assert redis_config is None or not hasattr(redis_config, "has_redis_client")


def test_lifespan_initializes_and_disposes_explicit_storage(monkeypatch):
    events: list[str] = []

    class RecordingStorage(KOrmStorage):
        def init_db_session(self):
            events.append("db_init")
            self._db_session = lambda: None
            return self._db_session

        def init_redis_client(self):
            events.append("redis_init")
            self._redis_client_instance = object()
            return self._redis_client_instance

        async def dispose(self) -> None:
            events.append("storage_dispose")

    async def fake_schedule_start(cls) -> None:
        events.append("schedule_start")

    async def fake_schedule_shutdown(cls) -> None:
        events.append("schedule_shutdown")

    monkeypatch.setattr(ScheduleManager, "start", classmethod(fake_schedule_start))
    monkeypatch.setattr(
        ScheduleManager,
        "shutdown",
        classmethod(fake_schedule_shutdown),
    )

    config = BaseConfig.model_validate(
        {
            "general": {"debug": True, "env": "test"},
            "logging": {"level": "INFO"},
            "i18n": {"path": ".", "locale": "zh-CN"},
            "default_storage": {
                "database": {"url": "sqlite+aiosqlite:///:memory:"},
                "redis": {
                    "host": "127.0.0.1",
                    "port": 6379,
                    "db": 0,
                    "password": "",
                },
            },
        }
    )
    storage = RecordingStorage(
        database_config=config.get_default_storage_database_config(),
        redis_config=config.get_default_storage_redis_config(),
    )
    app = init_asgi_app(config, routers=[], storage=storage)

    async def run_lifespan() -> None:
        async with app.router.lifespan_context(app):
            assert storage.has_db_session()
            assert storage.has_redis_client()

    asyncio.run(run_lifespan())

    assert events == [
        "db_init",
        "redis_init",
        "schedule_start",
        "schedule_shutdown",
        "storage_dispose",
    ]


def test_database_dispose_closes_tracked_sessions(monkeypatch):
    closed_sessions: list[str] = []

    class FakeEngine:
        def __init__(self) -> None:
            self.disposed = False

        async def dispose(self) -> None:
            self.disposed = True

    class FakeSession:
        def __init__(self, name: str) -> None:
            self.name = name

        async def aclose(self) -> None:
            closed_sessions.append(self.name)

    fake_engine = FakeEngine()
    session_index = {"value": 0}

    def fake_create_async_engine(url, **kwargs):
        return fake_engine

    def fake_async_sessionmaker(**kwargs):
        def _factory():
            session_index["value"] += 1
            return FakeSession(f"s{session_index['value']}")

        return _factory

    monkeypatch.setattr(
        "sqlalchemy.ext.asyncio.create_async_engine",
        fake_create_async_engine,
    )
    monkeypatch.setattr(
        "sqlalchemy.ext.asyncio.async_sessionmaker",
        fake_async_sessionmaker,
    )

    database_config = DatabaseConfig(url="sqlite+aiosqlite:///:memory:")
    storage = KOrmStorage(database_config=database_config)
    storage.init_db_session()

    session_1 = storage.db_session()
    session_2 = storage.db_session()

    assert session_1 is not session_2

    asyncio.run(storage.dispose())

    assert sorted(closed_sessions) == ["s1", "s2"]
    assert fake_engine.disposed is True
    assert storage.has_db_session() is False


def test_storage_dispose_closes_redis_client() -> None:
    closed_events: list[str] = []

    class FakePool:
        async def disconnect(self) -> None:
            closed_events.append("disconnect")

    class FakeRedis:
        def __init__(self) -> None:
            self.connection_pool = FakePool()

        async def aclose(self) -> None:
            closed_events.append("close")

    storage = KOrmStorage(redis_config=RedisConfig(
        host="127.0.0.1",
        port=6379,
        db=0,
        password="",
    ))
    storage.set_redis_client(FakeRedis())

    asyncio.run(storage.dispose())

    assert closed_events == ["close", "disconnect"]
    assert storage.has_redis_client() is False
