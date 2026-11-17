import asyncio
import json

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
import socketio

from kmvpy.common.conf import BaseConfig, ServiceConfig
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.socketio import SocketManager
from kmvpy.core.main import init_asgi_app


def test_polling_namespace_auth_rooms_and_emit_use_mounted_endpoint() -> None:
    async def run() -> None:
        app = FastAPI()
        manager = SocketManager(app, cors_allowed_origins=[])
        connected = []

        @manager.on("connect", namespace="/ws")
        async def connect(sid, environ, auth):
            connected.append((sid, auth))
            await manager.enter_room(sid, "account:42", namespace="/ws")

        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            opened = await client.get("/ws/socket.io/?EIO=4&transport=polling")
            assert opened.status_code == 200
            engine_sid = json.loads(opened.text[1:])["sid"]
            url = f"/ws/socket.io/?EIO=4&transport=polling&sid={engine_sid}"
            try:
                response = await client.post(url, content='40/ws,{"token":"accepted"}')
                assert response.status_code == 200
                joined = await client.get(url)
                assert joined.text.startswith("40/ws,")
                sid, auth = connected[0]
                assert auth == {"token": "accepted"}
                assert "account:42" in manager.rooms(sid, namespace="/ws")
                await manager.emit("update", {"value": 7}, room="account:42", namespace="/ws")
                message = await client.get(url)
                assert message.text == '42/ws,["update",{"value":7}]'
                assert manager.server is app.sio
                assert manager.server is manager._sio
                assert manager.asgi_app is manager._app
                assert app.state.socketio_manager is manager
            finally:
                # Client close drains the polling queue without waiting for a
                # future poll during server teardown.
                await client.post(url, content="1")
                await asyncio.gather(manager.shutdown(), manager.shutdown())
                await manager.shutdown()
        assert manager.server.eio.service_task_handle is None

    asyncio.run(run())


def test_websocket_transport_and_deployment_root_path() -> None:
    app = FastAPI(root_path="/api")
    manager = SocketManager(app, cors_allowed_origins=[])

    with TestClient(app) as client:
        with client.websocket_connect(
            "/api/ws/socket.io/?EIO=4&transport=websocket", headers={"upgrade": "websocket"}
        ) as ws:
            opening = ws.receive_text()
            assert opening.startswith("0")
            assert json.loads(opening[1:])["sid"]
            ws.send_text("40")
            assert ws.receive_text().startswith("40")
            ws.send_text("1")
        client.portal.call(manager.shutdown)


@pytest.mark.parametrize("mount,endpoint", [
    ("/events", "/transport"), ("/ws", "/ws/socket.io"), ("/", "/socket.io"),
])
def test_service_config_honors_custom_mount_and_origin_policy(mount, endpoint) -> None:
    async def run() -> None:
        app = FastAPI()
        service = ServiceConfig.model_validate({"socketio_config": {
            "mount_location": mount, "socketio_path": endpoint,
            "cors_allowed_origins": ["https://allowed.example"],
        }})
        manager = service.gen_socket_manager(app)
        assert manager is not None
        path = f"{mount.rstrip('/')}/{endpoint.strip('/')}"
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app=app), base_url="http://test"
        ) as client:
            rejected = await client.get(
                f"{path}/?EIO=4&transport=polling",
                headers={"origin": "https://blocked.example"},
            )
            assert rejected.status_code == 400
            response = await client.get(
                f"{path}/?EIO=4&transport=polling",
                headers={"origin": "https://allowed.example"},
            )
            assert response.status_code == 200
            sid = json.loads(response.text[1:])["sid"]
            await client.post(f"{path}/?EIO=4&transport=polling&sid={sid}", content="1")
            assert (await client.get("/ws/socket.io/?EIO=4&transport=polling")).status_code == 404
            await manager.shutdown()

    assert ServiceConfig().gen_socket_manager(FastAPI()) is None
    asyncio.run(run())


def test_application_lifespan_shuts_down_its_socket_server(monkeypatch) -> None:
    events = []

    async def shutdown(self):
        events.append("socket_shutdown")

    monkeypatch.setattr(SocketManager, "shutdown", shutdown)
    config = BaseConfig.model_validate({
        "general": {"debug": True, "env": "test"},
        "logging": {"level": "INFO"},
        "i18n": {"path": ".", "locale": "en"},
    })
    app = init_asgi_app(config, routers=[], storage=KOrmStorage())

    async def run() -> None:
        async with app.router.lifespan_context(app):
            assert app.sio is app.state.socketio_manager.server

    asyncio.run(run())
    assert events == ["socket_shutdown"]


def test_redis_manager_listener_and_connections_are_closed_on_shutdown() -> None:
    async def run() -> None:
        events = []

        class RedisResource:
            def __init__(self, name):
                self.name = name

            async def aclose(self):
                events.append(self.name)

        redis_manager = socketio.AsyncRedisManager("redis://127.0.0.1:6379/0")
        manager = SocketManager(FastAPI(), client_manager=redis_manager)
        redis_manager.thread = asyncio.create_task(asyncio.Event().wait())
        redis_manager.pubsub = RedisResource("pubsub_close")
        redis_manager.redis = RedisResource("redis_close")
        await asyncio.gather(manager.shutdown(), manager.shutdown())
        await manager.shutdown()
        assert redis_manager.thread.cancelled()
        assert events == ["pubsub_close", "redis_close"]
        assert manager.server.manager is redis_manager

    asyncio.run(run())
