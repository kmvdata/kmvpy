"""Socket.IO integration using the maintained python-socketio ASGI server."""
from __future__ import annotations

import asyncio
from typing import Any

from fastapi import FastAPI
import socketio


class SocketManager:
    """Mount Socket.IO while keeping the manager interface used by kmvpy apps.

    ``server`` and ``asgi_app`` expose the upstream objects for Redis managers
    and other advanced configuration. Socket.IO methods such as ``on``,
    ``emit`` and ``enter_room`` are delegated to the server.
    """

    def __init__(
        self,
        app: FastAPI,
        mount_location: str = "/ws",
        socketio_path: str = "/socket.io",
        cors_allowed_origins: str | list[str] | None = "*",
        async_mode: str = "asgi",
        **kwargs: Any,
    ) -> None:
        self.mount_location = "/" + mount_location.strip("/")
        endpoint = socketio_path.strip("/")
        if not endpoint:
            raise ValueError("socketio_path must identify a Socket.IO endpoint")
        self.socketio_path = self.mount_location.rstrip("/") + "/" + endpoint
        self.server = socketio.AsyncServer(
            async_mode=async_mode, cors_allowed_origins=cors_allowed_origins, **kwargs
        )
        self.asgi_app = socketio.ASGIApp(
            self.server, socketio_path=self.socketio_path
        )
        self._shutdown_task: asyncio.Task[None] | None = None
        # Existing generated applications may still access the old wrapper's
        # private objects. New code should use server/asgi_app instead.
        self._sio = self.server
        self._app = self.asgi_app
        app.mount(self.mount_location, self._mounted_app)
        app.sio = self.server
        app.state.socketio_manager = self

    async def _mounted_app(self, scope, receive, send) -> None:
        # Starlette versions differ in whether a mounted scope retains the
        # mount prefix in path. Also remove an outer deployment root_path so
        # Engine.IO sees the same path behind an ASGI proxy prefix.
        path = scope.get("path", "")
        root_path = scope.get("root_path", "").rstrip("/")
        mount = self.mount_location.rstrip("/")
        if root_path and (path == root_path or path.startswith(root_path + "/")):
            path = mount + "/" + path[len(root_path):].lstrip("/")
        elif mount and path != mount and not path.startswith(mount + "/"):
            path = mount + "/" + path.lstrip("/")
        await self.asgi_app({**scope, "path": path}, receive, send)

    def __getattr__(self, name: str) -> Any:
        return getattr(self.server, name)

    async def shutdown(self) -> None:
        """Share one cleanup operation across repeated or concurrent callers."""
        if self._shutdown_task is None:
            self._shutdown_task = asyncio.create_task(self._shutdown())
        await asyncio.shield(self._shutdown_task)

    async def _shutdown(self) -> None:
        """Stop Engine.IO and release an optional Redis manager's listener.

        python-socketio's shutdown stops Engine.IO's monitor but its Redis
        manager currently has no public shutdown hook of its own.
        """
        try:
            await self.server.shutdown()
        finally:
            manager = self.server.manager
            if isinstance(manager, socketio.AsyncRedisManager):
                listener = getattr(manager, "thread", None)
                if isinstance(listener, asyncio.Task):
                    listener.cancel()
                    await asyncio.gather(listener, return_exceptions=True)
                pubsub = getattr(manager, "pubsub", None)
                redis = getattr(manager, "redis", None)
                try:
                    if pubsub is not None:
                        await pubsub.aclose()
                finally:
                    if redis is not None:
                        await redis.aclose()
