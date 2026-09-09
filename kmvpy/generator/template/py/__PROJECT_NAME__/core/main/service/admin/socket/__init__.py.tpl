from __future__ import annotations

import asyncio
import json
import time
from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any, Literal
from urllib.parse import parse_qs

from fastapi import HTTPException
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo

from __PROJECT_NAME__.core.main.hub.user_op import UserOpHub


@dataclass(frozen=True)
class AdminSocketSession:
    sid: str
    admin_kid: int
    access_expires_at: int = 0


class AdminSocketService:
    SOCKET_NAMESPACE = "/admin_ws"
    NOTICE_EVENT = "api_notice"
    _ADMIN_ROOM_PREFIX = "admin_socket:admin"

    _sid_to_session: dict[str, AdminSocketSession] = {}
    _admin_kid_to_sids: dict[int, set[str]] = {}
    _sid_expire_tasks: dict[str, asyncio.Task] = {}

    @staticmethod
    def _socketio():
        return getattr(kosmos, "socketio", None)

    @staticmethod
    def _raw_socketio_server():
        socket_manager = AdminSocketService._socketio()
        if socket_manager is None:
            return None
        return getattr(socket_manager, "_sio", socket_manager)

    @staticmethod
    def _normalize_token(token_or_header: str | None) -> str | None:
        raw_value = (token_or_header or "").strip()
        if not raw_value:
            return None
        if raw_value.lower().startswith("bearer "):
            return JwtService.extract_token_from_header(raw_value)
        return raw_value

    @staticmethod
    def _extract_token_from_auth(auth: Any) -> str | None:
        if isinstance(auth, dict):
            for key in ("token", "authorization", "Authorization"):
                token = AdminSocketService._normalize_token(auth.get(key))
                if token:
                    return token
        if isinstance(auth, str):
            try:
                parsed_auth = json.loads(auth)
            except json.JSONDecodeError:
                return AdminSocketService._normalize_token(auth)
            return AdminSocketService._extract_token_from_auth(parsed_auth)
        return None

    @staticmethod
    def _extract_token_from_environ(environ: dict[str, Any] | None) -> str | None:
        if not environ:
            return None
        token = AdminSocketService._normalize_token(environ.get("HTTP_AUTHORIZATION"))
        if token:
            return token

        query_params = parse_qs(str(environ.get("QUERY_STRING") or ""))
        for key in ("token", "authorization", "Authorization"):
            values = query_params.get(key)
            if not values:
                continue
            token = AdminSocketService._normalize_token(values[0])
            if token:
                return token
        return None

    @staticmethod
    async def _authenticate_socket_token(token: str) -> JwtUserInfo:
        payload = JwtService.decode_token(token, auth_role="admin")
        user_info = JwtService.payload_to_user_info(payload)
        if int(user_info.user_type) != UserOpHub.ADMIN_DB_USER_TYPE:
            raise HTTPException(status_code=401, detail="仅管理员可以建立管理端 socket")
        return user_info

    @staticmethod
    def _add_session(session: AdminSocketSession) -> None:
        AdminSocketService._sid_to_session[session.sid] = session
        AdminSocketService._admin_kid_to_sids.setdefault(session.admin_kid, set()).add(
            session.sid
        )

    @staticmethod
    def _remove_session(sid: str) -> AdminSocketSession | None:
        expire_task = AdminSocketService._sid_expire_tasks.pop(sid, None)
        if expire_task is not None:
            expire_task.cancel()

        session = AdminSocketService._sid_to_session.pop(sid, None)
        if session is None:
            return None

        admin_sids = AdminSocketService._admin_kid_to_sids.get(session.admin_kid)
        if admin_sids is not None:
            admin_sids.discard(sid)
            if not admin_sids:
                AdminSocketService._admin_kid_to_sids.pop(session.admin_kid, None)

        return session

    @staticmethod
    def _schedule_socket_token_expiry(session: AdminSocketSession) -> None:
        if session.access_expires_at <= 0:
            return

        async def _disconnect_when_access_token_expires() -> None:
            try:
                delay = max(0, session.access_expires_at - int(time.time()))
                if delay > 0:
                    await asyncio.sleep(delay)
                raw_server = AdminSocketService._raw_socketio_server()
                if raw_server is not None:
                    await raw_server.disconnect(
                        session.sid,
                        namespace=AdminSocketService.SOCKET_NAMESPACE,
                    )
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.warning(
                    "access token 过期断开管理端 socket 失败，sid=%s, admin_kid=%s",
                    session.sid,
                    session.admin_kid,
                    exc_info=exc,
                )

        previous_task = AdminSocketService._sid_expire_tasks.pop(session.sid, None)
        if previous_task is not None:
            previous_task.cancel()
        AdminSocketService._sid_expire_tasks[session.sid] = asyncio.create_task(
            _disconnect_when_access_token_expires()
        )

    @staticmethod
    def _admin_room(admin_kid: int) -> str:
        return f"{AdminSocketService._ADMIN_ROOM_PREFIX}:{int(admin_kid)}"

    @staticmethod
    async def _enter_admin_room(sid: str, admin_kid: int) -> None:
        socketio_server = AdminSocketService._socketio()
        if socketio_server is None:
            return
        try:
            await socketio_server.enter_room(
                sid=sid,
                room=AdminSocketService._admin_room(admin_kid),
                namespace=AdminSocketService.SOCKET_NAMESPACE,
            )
        except Exception as exc:
            logger.warning(
                "管理端 socket 加入 room 失败，sid=%s, admin_kid=%s",
                sid,
                admin_kid,
                exc_info=exc,
            )

    @staticmethod
    async def _leave_admin_room(sid: str, admin_kid: int) -> None:
        socketio_server = AdminSocketService._socketio()
        if socketio_server is None:
            return
        try:
            await socketio_server.leave_room(
                sid=sid,
                room=AdminSocketService._admin_room(admin_kid),
                namespace=AdminSocketService.SOCKET_NAMESPACE,
            )
        except Exception as exc:
            logger.warning(
                "管理端 socket 离开 room 失败，sid=%s, admin_kid=%s",
                sid,
                admin_kid,
                exc_info=exc,
            )

    @staticmethod
    def _build_api_notice_payload(
        *,
        api_uri: str,
        kid_for_api: int | None = None,
    ) -> dict[str, str | None]:
        return {
            "api_uri": api_uri,
            "kid_for_api": str(int(kid_for_api)) if kid_for_api is not None else None,
        }

    @staticmethod
    async def send_socket_message(
        admin_kids: Iterable[int],
        api_uri: str,
        kid_for_api: int | None = None,
    ) -> bool:
        """
        向指定管理员的在线 socket 发送固定格式 API 通知。

        管理端通知只作为实时刷新信号，不落离线补偿表。
        """
        if not isinstance(api_uri, str) or not api_uri or len(api_uri) > 255:
            raise ValueError("api_uri 必须是 1 到 255 个字符的字符串")

        target_admin_kids = tuple(dict.fromkeys(int(kid) for kid in admin_kids))
        if not target_admin_kids:
            return False

        socketio_server = AdminSocketService._socketio()
        if socketio_server is None:
            logger.warning("Socket.IO 尚未初始化，无法发送管理端消息")
            return False

        payload = AdminSocketService._build_api_notice_payload(
            api_uri=api_uri,
            kid_for_api=kid_for_api,
        )
        sent = False
        for admin_kid in target_admin_kids:
            try:
                await socketio_server.emit(
                    event=AdminSocketService.NOTICE_EVENT,
                    data=payload,
                    to=AdminSocketService._admin_room(admin_kid),
                    namespace=AdminSocketService.SOCKET_NAMESPACE,
                )
                sent = True
            except Exception as exc:
                logger.warning(
                    "管理端 socket 消息定向发送失败，admin_kid=%s",
                    admin_kid,
                    exc_info=exc,
                )
        return sent

    @staticmethod
    async def _handle_connect(sid: str, environ: dict[str, Any] | None, auth: Any = None) -> bool:
        token = (
            AdminSocketService._extract_token_from_auth(auth)
            or AdminSocketService._extract_token_from_environ(environ)
        )
        if not token:
            logger.warning("管理端 socket 连接缺少 token，sid=%s", sid)
            return False

        try:
            admin_info = await AdminSocketService._authenticate_socket_token(token)
        except Exception as exc:
            logger.warning("管理端 socket 鉴权失败，sid=%s", sid, exc_info=exc)
            return False

        session = AdminSocketSession(
            sid=sid,
            admin_kid=int(admin_info.kid),
            access_expires_at=int(getattr(admin_info, "expires_at", 0) or 0),
        )
        AdminSocketService._add_session(session)
        AdminSocketService._schedule_socket_token_expiry(session)
        await AdminSocketService._enter_admin_room(
            sid=sid,
            admin_kid=session.admin_kid,
        )
        logger.info("管理端 socket 鉴权成功，sid=%s, admin_kid=%s", sid, session.admin_kid)
        return True

    @staticmethod
    async def _handle_disconnect(sid: str) -> None:
        session = AdminSocketService._remove_session(sid)
        if session is None:
            logger.info("未知管理端 socket 断开，sid=%s", sid)
            return
        await AdminSocketService._leave_admin_room(
            sid=sid,
            admin_kid=session.admin_kid,
        )
        logger.info("管理端 socket 断开，sid=%s, admin_kid=%s", sid, session.admin_kid)

    @staticmethod
    async def handle_socket_connection(
        event: Literal["connect", "disconnect"],
        sid: str,
        environ: dict[str, Any] | None = None,
        auth: Any = None,
    ) -> bool | None:
        """
        处理管理端 Socket.IO 长连接生命周期事件。

        Router 只透传 socket.io 事件参数，鉴权、绑定与断开清理都收敛在 service 内部。
        """
        if event == "connect":
            return await AdminSocketService._handle_connect(sid=sid, environ=environ, auth=auth)
        if event == "disconnect":
            await AdminSocketService._handle_disconnect(sid=sid)
            return None
        raise ValueError(f"不支持的管理端 socket 事件: {event}")
