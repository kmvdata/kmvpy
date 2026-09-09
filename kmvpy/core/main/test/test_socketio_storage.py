import asyncio

from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.core.main.router.socketio import socketio_bind_router


def test_disconnect_uses_explicit_storage_redis_client() -> None:
    handlers = {}
    redis_calls: list[tuple] = []

    class FakeSocketio:
        def on(self, event, namespace):
            def register(handler):
                handlers[(event, namespace)] = handler
                return handler

            return register

    class FakeRedis:
        async def hget(self, *, name, key):
            redis_calls.append(("hget", name, key))
            return b"user-1"

        async def hdel(self, name, key):
            redis_calls.append(("hdel", name, key))

    storage = KOrmStorage()
    storage.set_redis_client(FakeRedis())
    socketio_bind_router(FakeSocketio(), storage=storage)

    disconnect = handlers[("disconnect", "/ws")]
    asyncio.run(disconnect("socket-1"))

    assert redis_calls == [
        ("hget", "socketio:user_kid", "socket-1"),
        ("hdel", "user_kid:socketio", b"user-1"),
        ("hdel", "socketio:user_kid", "socket-1"),
    ]
