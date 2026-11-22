"""Uvicorn integration: real loopback when permitted, plus SansIO ASGI routing."""
import asyncio
from contextlib import asynccontextmanager, suppress
import socket

import aiohttp
from fastapi import FastAPI
import pytest
import socketio
import uvicorn
import websockets

from kmvpy.common.socketio import SocketManager


@pytest.mark.parametrize("root_path", ["", "/api"])
def test_uvicorn_websocket_auth_room_messages_and_shutdown(root_path, record_property) -> None:
    async def run() -> None:
        lifecycle_closed = asyncio.Event()
        client_closed = asyncio.Event()
        messages = asyncio.Queue()

        @asynccontextmanager
        async def lifespan(app):
            try:
                yield
            finally:
                await manager.shutdown()
                lifecycle_closed.set()

        app = FastAPI(root_path=root_path, lifespan=lifespan)
        manager = SocketManager(app, cors_allowed_origins=[])

        @manager.on("connect", namespace="/ws")
        async def connect(sid, environ, auth):
            if auth != {"token": "accepted"}:
                return False
            await manager.enter_room(sid, "account:42", namespace="/ws")

        @manager.on("inspect_rooms", namespace="/ws")
        async def inspect_rooms(sid):
            return {"rooms": manager.rooms(sid, namespace="/ws")}

        client = socketio.AsyncClient(reconnection=False)
        rejected_client = socketio.AsyncClient(reconnection=False)

        @client.on("account_update", namespace="/ws")
        async def account_update(data):
            await messages.put(data)

        @client.on("disconnect", namespace="/ws")
        async def disconnect(reason):
            client_closed.set()

        listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        try:
            listener.bind(("127.0.0.1", 0))
        except PermissionError:
            listener.close()
            pytest.skip("This environment prohibits binding a local loopback socket")
        listener.listen()
        listener.setblocking(False)
        port = listener.getsockname()[1]
        config = uvicorn.Config(
            app, host="127.0.0.1", port=port, loop="asyncio", ws="auto",
            lifespan="on", root_path=root_path, log_level="warning",
            timeout_graceful_shutdown=2,
        )
        config.load()
        protocol = config.ws_protocol_class.__name__
        record_property("uvicorn_version", uvicorn.__version__)
        record_property("aiohttp_version", aiohttp.__version__)
        record_property("websockets_version", websockets.__version__)
        record_property("websocket_protocol", protocol)
        if tuple(map(int, uvicorn.__version__.split(".")[:2])) >= (0, 54):
            assert protocol == "WebSocketsSansIOProtocol"
        server = uvicorn.Server(config)
        serving = asyncio.create_task(server.serve(sockets=[listener]))
        try:
            async with asyncio.timeout(5):
                while not server.started:
                    if serving.done():
                        await serving
                        pytest.fail("Uvicorn exited before startup completed")
                    await asyncio.sleep(0.01)

            url = f"http://127.0.0.1:{port}"
            options = {"transports": ["websocket"], "socketio_path": "ws/socket.io",
                       "namespaces": ["/ws"], "wait_timeout": 2}
            with pytest.raises(socketio.exceptions.ConnectionError):
                await rejected_client.connect(url, auth={"token": "rejected"}, **options)
            assert not rejected_client.connected

            await client.connect(url, auth={"token": "accepted"}, **options)
            assert client.transport() == "websocket"
            assert "/ws" in client.namespaces
            rooms = await client.call("inspect_rooms", namespace="/ws", timeout=2)
            assert "account:42" in rooms["rooms"]
            await manager.emit("account_update", {"value": 7}, room="account:42", namespace="/ws")
            assert await asyncio.wait_for(messages.get(), timeout=2) == {"value": 7}

            # Stop with a live client: Uvicorn must close the WebSocket before
            # running the application's Socket.IO shutdown hook.
            server.should_exit = True
            await asyncio.wait_for(serving, timeout=5)
            await asyncio.wait_for(client_closed.wait(), timeout=2)
            assert lifecycle_closed.is_set()
            assert not client.connected
            assert manager.server.eio.service_task_handle is None
        finally:
            for active_client in (client, rejected_client):
                with suppress(Exception):
                    await asyncio.wait_for(active_client.disconnect(), timeout=2)
            server.should_exit = True
            if not serving.done():
                try:
                    await asyncio.wait_for(asyncio.shield(serving), timeout=5)
                except TimeoutError:
                    server.force_exit = True
                    serving.cancel()
                    await asyncio.gather(serving, return_exceptions=True)
            listener.close()
            if not lifecycle_closed.is_set():
                await manager.shutdown()

    asyncio.run(run())


@pytest.mark.parametrize("root_path", ["", "/api"])
def test_uvicorn_sansio_routes_socketio_frames_and_closes_app(root_path, record_property) -> None:
    """Exercise Uvicorn's real framing and mounted kmvpy app without binding TCP."""
    from uvicorn.server import ServerState
    from websockets.client import ClientProtocol
    from websockets.frames import Frame, Opcode
    from websockets.http11 import Response
    from websockets.uri import parse_uri

    async def run() -> None:
        app = FastAPI(root_path=root_path)
        manager = SocketManager(app, cors_allowed_origins=[])
        authenticated = []

        @manager.on("connect", namespace="/ws")
        async def connect(sid, environ, auth):
            authenticated.append(auth)
            await manager.enter_room(sid, "account:42", namespace="/ws")

        config = uvicorn.Config(app, ws="auto", root_path=root_path, log_level="warning")
        config.load()
        record_property("uvicorn_version", uvicorn.__version__)
        record_property("aiohttp_version", aiohttp.__version__)
        record_property("websockets_version", websockets.__version__)
        record_property("websocket_protocol", config.ws_protocol_class.__name__)
        assert config.ws_protocol_class.__name__ == "WebSocketsSansIOProtocol"
        state = ServerState()
        protocol = config.ws_protocol_class(config, state, {})
        client = ClientProtocol(parse_uri("ws://test/ws/socket.io/?EIO=4&transport=websocket"))
        events = asyncio.Queue()

        class MemoryTransport(asyncio.Transport):
            closing = False

            def get_extra_info(self, name, default=None):
                return {"peername": ("127.0.0.1", 55000), "sockname": ("127.0.0.1", 8000)}.get(name, default)

            def write(self, data):
                client.receive_data(data)
                for event in client.events_received():
                    events.put_nowait(event)

            def close(self):
                if not self.closing:
                    self.closing = True
                    asyncio.get_running_loop().call_soon(protocol.connection_lost, None)

            def is_closing(self):
                return self.closing

            def pause_reading(self):
                pass

            def resume_reading(self):
                pass

        async def receive_text():
            async with asyncio.timeout(2):
                while True:
                    event = await events.get()
                    if isinstance(event, Response):
                        assert event.status_code == 101
                    elif isinstance(event, Frame) and event.opcode == Opcode.TEXT:
                        return event.data.decode()

        transport = MemoryTransport()
        protocol.connection_made(transport)
        try:
            client.send_request(client.connect())
            protocol.data_received(b"".join(client.data_to_send()))
            assert (await receive_text()).startswith("0")
            client.send_text(b'40/ws,{"token":"accepted"}')
            protocol.data_received(b"".join(client.data_to_send()))
            assert (await receive_text()).startswith("40/ws,")
            assert authenticated == [{"token": "accepted"}]
            await manager.emit("account_update", {"value": 7}, room="account:42", namespace="/ws")
            assert await receive_text() == '42/ws,["account_update",{"value":7}]'
            protocol.shutdown()
            await asyncio.wait_for(asyncio.gather(*state.tasks), timeout=2)
            assert transport.is_closing()
            assert not state.connections
        finally:
            transport.close()
            if state.tasks:
                await asyncio.wait_for(asyncio.gather(*state.tasks), timeout=2)
            await manager.shutdown()
        assert manager.server.eio.service_task_handle is None

    asyncio.run(run())
