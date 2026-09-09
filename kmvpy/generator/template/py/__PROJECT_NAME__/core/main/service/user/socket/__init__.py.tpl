from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass
from typing import Any, Literal
from urllib.parse import parse_qs, quote

from fastapi import HTTPException
import socketio
from redis.asyncio import Redis
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.object_to_dict import object2dict
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo
from sqlalchemy import func, select

from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage
from __PROJECT_NAME__.common.infra.orm.user_socket_message import UserSocketMessage
from __PROJECT_NAME__.core.main.hub.user_op import UserOpHub


@dataclass(frozen=True)
class UserSocketSession:
    sid: str
    user_kid: int
    access_expires_at: int = 0


class UserSocketService:
    SOCKET_NAMESPACE = "/ws"
    NOTICE_EVENT = "api_notice"
    _DISTRIBUTED_CHANNEL = "__PROJECT_NAME__:user_socket"
    _USER_ROOM_PREFIX = "user_socket:user"
    _USER_PRESENCE_KEY_PREFIX = "socket:user:online"
    _SID_PRESENCE_KEY_PREFIX = "socket:sid:online"
    _PRESENCE_TTL_SECONDS = 90
    _PRESENCE_REFRESH_SECONDS = 30
    _MAX_PENDING_MESSAGES_ON_CONNECT = 100

    _sid_to_session: dict[str, UserSocketSession] = {}
    _user_kid_to_sids: dict[int, set[str]] = {}
    _sid_expire_tasks: dict[str, asyncio.Task] = {}
    _user_socket_redis_client: Any | None = None
    _user_socket_redis_client_key: tuple[str, int, int, str | None, bool] | None = None
    _presence_refresh_task: asyncio.Task[None] | None = None


    @staticmethod
    async def pull_pending_socket_messages(
        user_kid: int,
        page: int = 1,
        size: int = 1000,
    ) -> tuple[list[dict[str, Any]], int]:
        """
        HTTP 补偿拉取当前用户尚未通过 socket 推送成功的滞留消息。
        """
        normalized_page = max(1, int(page))
        normalized_size = max(1, int(size))
        offset = (normalized_page - 1) * normalized_size
        db = DefaultStorage.instance()
        messages: list[dict[str, Any]] = []
        async with db.session_scope() as session:
            total_result = await session.execute(
                select(func.count())
                .select_from(UserSocketMessage)
                .where(UserSocketMessage.user_kid == int(user_kid))
            )
            total = int(total_result.scalar_one() or 0)
            result = await session.execute(
                select(UserSocketMessage)
                .where(UserSocketMessage.user_kid == int(user_kid))
                .order_by(UserSocketMessage.id.asc())
                .offset(offset)
                .limit(normalized_size)
            )
            orm_messages = list(result.scalars().all())
            for message in orm_messages:
                messages.append(UserSocketService._message_to_payload(message))
                await session.delete(message)
            if orm_messages:
                await session.flush()
        return messages, total

    @staticmethod
    async def send_socket_message(
        user_kid: int,
        api_uri: str,
        kid_for_api: int | None = None,
    ) -> bool:
        """
        给指定用户的在线 socket 发送固定格式 API 通知。

        返回 True 表示至少一个在线 socket 已收到；用户不在线时写入离线消息表并返回 False。
        """
        if not isinstance(api_uri, str) or not api_uri or len(api_uri) > 255:
            raise ValueError("api_uri 必须是 1 到 255 个字符的字符串")
        message = UserSocketMessage(
            kid=UserSocketMessage.gen_kid(),
            user_kid=int(user_kid),
            api_uri=api_uri,
            kid_for_api=int(kid_for_api) if kid_for_api is not None else None,
        )
        sent = await UserSocketService._emit_to_user(message)
        if sent:
            return True
        await UserSocketService._cache_message(message)
        return False

    @staticmethod
    def _socketio():
        return getattr(kosmos, "socketio", None)

    @staticmethod
    def _raw_socketio_server():
        socket_manager = UserSocketService._socketio()
        if socket_manager is None:
            return None
        return getattr(socket_manager, "_sio", socket_manager)

    @staticmethod
    def _user_redis_config(config: Any | None = None):
        app_config = config or getattr(kosmos, "config", None)
        auth_config = getattr(app_config, "auth_config", None)
        user_config = getattr(auth_config, "user", None) if auth_config is not None else None
        return getattr(user_config, "redis", None) if user_config is not None else None

    @staticmethod
    def _uses_distributed_socket_cluster() -> bool:
        return UserSocketService._user_redis_config() is not None

    @staticmethod
    def require_redis_for_production(config: Any) -> None:
        redis_config = UserSocketService._user_redis_config(config)
        service_config = getattr(config, "service", None)
        workers = int(getattr(service_config, "workers", 1) or 1)
        general_config = getattr(config, "general", None)
        env = str(getattr(general_config, "env", "") or "").lower()
        debug = bool(getattr(general_config, "debug", False))
        is_local_dev = debug or env in {"dev", "debug", "development", "local"}
        if redis_config is None and (workers > 1 or not is_local_dev):
            raise RuntimeError("生产或多进程用户 Socket.IO 必须配置 auth_config.user.redis")

    @staticmethod
    def _user_redis_client() -> Any | None:
        redis_config = UserSocketService._user_redis_config()
        if redis_config is None:
            return None

        client_key = (
            str(getattr(redis_config, "host")),
            int(getattr(redis_config, "port")),
            int(getattr(redis_config, "db")),
            getattr(redis_config, "password", None),
            bool(getattr(redis_config, "decode_responses", True)),
        )
        if (
            UserSocketService._user_socket_redis_client is not None
            and UserSocketService._user_socket_redis_client_key == client_key
        ):
            return UserSocketService._user_socket_redis_client

        UserSocketService._user_socket_redis_client = Redis(
            host=client_key[0],
            port=client_key[1],
            db=client_key[2],
            password=client_key[3],
            decode_responses=client_key[4],
        )
        UserSocketService._user_socket_redis_client_key = client_key
        return UserSocketService._user_socket_redis_client

    @staticmethod
    def _redis_url(redis_config: Any) -> str:
        password = getattr(redis_config, "password", None)
        auth_part = f":{quote(str(password), safe='')}@" if password else ""
        host = getattr(redis_config, "host")
        port = int(getattr(redis_config, "port"))
        db = int(getattr(redis_config, "db"))
        return f"redis://{auth_part}{host}:{port}/{db}"

    @staticmethod
    def configure_distributed_socket_manager(config: Any | None = None) -> None:
        """
        在用户 Redis 已配置时启用 python-socketio 官方 Redis pub/sub manager。

        kmvpy 负责创建 SocketManager；这里在连接建立前替换底层 client_manager，
        让后续 room emit 能通过 Redis 转发到其他服务实例。
        """
        redis_config = UserSocketService._user_redis_config(config)
        if redis_config is None:
            return

        raw_server = UserSocketService._raw_socketio_server()
        if raw_server is None:
            logger.warning("Socket.IO 尚未初始化，无法启用用户 socket 分布式转发")
            return

        redis_url = UserSocketService._redis_url(redis_config)
        current_manager = getattr(raw_server, "manager", None)
        if (
            isinstance(current_manager, socketio.AsyncRedisManager)
            and getattr(current_manager, "redis_url", None) == redis_url
            and getattr(current_manager, "channel", None) == UserSocketService._DISTRIBUTED_CHANNEL
        ):
            return

        manager = socketio.AsyncRedisManager(
            redis_url,
            channel=UserSocketService._DISTRIBUTED_CHANNEL,
        )
        raw_server.manager = manager
        raw_server.manager.set_server(raw_server)
        raw_server.manager_initialized = False
        logger.info("用户 socket 已启用 Redis 分布式转发，channel=%s", UserSocketService._DISTRIBUTED_CHANNEL)

    @staticmethod
    def _user_room(user_kid: int) -> str:
        return f"{UserSocketService._USER_ROOM_PREFIX}:{int(user_kid)}"

    @staticmethod
    def _user_presence_key(user_kid: int) -> str:
        return f"{UserSocketService._USER_PRESENCE_KEY_PREFIX}:{int(user_kid)}"

    @staticmethod
    def _sid_presence_key(sid: str) -> str:
        return f"{UserSocketService._SID_PRESENCE_KEY_PREFIX}:{sid}"

    @staticmethod
    def _redis_text(value: Any) -> str:
        if isinstance(value, bytes):
            return value.decode("utf-8")
        return str(value)

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
                token = UserSocketService._normalize_token(auth.get(key))
                if token:
                    return token
        if isinstance(auth, str):
            try:
                parsed_auth = json.loads(auth)
            except json.JSONDecodeError:
                return UserSocketService._normalize_token(auth)
            return UserSocketService._extract_token_from_auth(parsed_auth)
        return None

    @staticmethod
    def _extract_token_from_environ(environ: dict[str, Any] | None) -> str | None:
        if not environ:
            return None
        token = UserSocketService._normalize_token(environ.get("HTTP_AUTHORIZATION"))
        if token:
            return token

        query_params = parse_qs(str(environ.get("QUERY_STRING") or ""))
        for key in ("token", "authorization", "Authorization"):
            values = query_params.get(key)
            if not values:
                continue
            token = UserSocketService._normalize_token(values[0])
            if token:
                return token
        return None

    @staticmethod
    async def _authenticate_socket_token(token: str) -> JwtUserInfo:
        payload = JwtService.decode_token(token, auth_role="user")
        user_info = JwtService.payload_to_user_info(payload)
        if not UserOpHub.is_regular_user(user_info.user_type):
            raise HTTPException(status_code=401, detail="仅普通用户可以建立用户端 socket")
        return user_info

    @staticmethod
    def _add_session(session: UserSocketSession) -> None:
        UserSocketService._sid_to_session[session.sid] = session
        UserSocketService._user_kid_to_sids.setdefault(session.user_kid, set()).add(session.sid)

    @staticmethod
    def _remove_session(sid: str) -> UserSocketSession | None:
        expire_task = UserSocketService._sid_expire_tasks.pop(sid, None)
        if expire_task is not None:
            expire_task.cancel()

        session = UserSocketService._sid_to_session.pop(sid, None)
        if session is None:
            return None

        user_sids = UserSocketService._user_kid_to_sids.get(session.user_kid)
        if user_sids is not None:
            user_sids.discard(sid)
            if not user_sids:
                UserSocketService._user_kid_to_sids.pop(session.user_kid, None)

        return session

    @staticmethod
    def _schedule_socket_token_expiry(session: UserSocketSession) -> None:
        if session.access_expires_at <= 0:
            return

        async def _disconnect_when_access_token_expires() -> None:
            try:
                delay = max(0, session.access_expires_at - int(time.time()))
                if delay > 0:
                    await asyncio.sleep(delay)
                raw_server = UserSocketService._raw_socketio_server()
                if raw_server is not None:
                    await raw_server.disconnect(
                        session.sid,
                        namespace=UserSocketService.SOCKET_NAMESPACE,
                    )
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.warning(
                    "access token 过期断开用户 socket 失败，sid=%s, user_kid=%s",
                    session.sid,
                    session.user_kid,
                    exc_info=exc,
                )

        previous_task = UserSocketService._sid_expire_tasks.pop(session.sid, None)
        if previous_task is not None:
            previous_task.cancel()
        UserSocketService._sid_expire_tasks[session.sid] = asyncio.create_task(
            _disconnect_when_access_token_expires()
        )

    @staticmethod
    def _message_to_payload(message: UserSocketMessage) -> dict[str, Any]:
        # 复用 ApiResponse 的对象转换路径，确保 ORM BigInt 字段在 socket 发包前转为字符串。
        payload = json.loads(json.dumps(object2dict(message), ensure_ascii=False))
        return payload if isinstance(payload, dict) else {"data": payload}

    @staticmethod
    async def _enter_user_room(sid: str, user_kid: int) -> None:
        socketio_server = UserSocketService._socketio()
        if socketio_server is None:
            return
        try:
            await socketio_server.enter_room(
                sid=sid,
                room=UserSocketService._user_room(user_kid),
                namespace=UserSocketService.SOCKET_NAMESPACE,
            )
        except Exception as exc:
            logger.warning("用户 socket 加入 room 失败，sid=%s, user_kid=%s", sid, user_kid, exc_info=exc)

    @staticmethod
    async def _leave_user_room(sid: str, user_kid: int) -> None:
        socketio_server = UserSocketService._socketio()
        if socketio_server is None:
            return
        try:
            await socketio_server.leave_room(
                sid=sid,
                room=UserSocketService._user_room(user_kid),
                namespace=UserSocketService.SOCKET_NAMESPACE,
            )
        except Exception as exc:
            logger.warning("用户 socket 离开 room 失败，sid=%s, user_kid=%s", sid, user_kid, exc_info=exc)

    @staticmethod
    async def _mark_user_socket_online(session: UserSocketSession) -> None:
        if not UserSocketService._uses_distributed_socket_cluster():
            return
        try:
            redis_client = UserSocketService._user_redis_client()
            if redis_client is None:
                return
            await redis_client.sadd(
                UserSocketService._user_presence_key(session.user_kid),
                session.sid,
            )
            await redis_client.set(
                UserSocketService._sid_presence_key(session.sid),
                str(session.user_kid),
                ex=UserSocketService._PRESENCE_TTL_SECONDS,
            )
            UserSocketService._ensure_presence_refresh_task()
        except Exception as exc:
            logger.warning(
                "记录用户 socket 在线状态失败，sid=%s, user_kid=%s",
                session.sid,
                session.user_kid,
                exc_info=exc,
            )

    @staticmethod
    async def _mark_user_socket_offline(session: UserSocketSession) -> None:
        if not UserSocketService._uses_distributed_socket_cluster():
            return
        try:
            redis_client = UserSocketService._user_redis_client()
            if redis_client is None:
                return
            presence_key = UserSocketService._user_presence_key(session.user_kid)
            await redis_client.srem(presence_key, session.sid)
            await redis_client.delete(UserSocketService._sid_presence_key(session.sid))
            if int(await redis_client.scard(presence_key) or 0) == 0:
                await redis_client.delete(presence_key)
        except Exception as exc:
            logger.warning(
                "清理用户 socket 在线状态失败，sid=%s, user_kid=%s",
                session.sid,
                session.user_kid,
                exc_info=exc,
            )

    @staticmethod
    async def _has_online_user_socket(user_kid: int) -> bool:
        if UserSocketService._user_kid_to_sids.get(int(user_kid)):
            return True
        if not UserSocketService._uses_distributed_socket_cluster():
            return False
        try:
            redis_client = UserSocketService._user_redis_client()
            if redis_client is None:
                return False
            presence_key = UserSocketService._user_presence_key(user_kid)
            sids = await redis_client.smembers(presence_key)
            stale_sids: list[str] = []
            for sid_value in sids:
                sid = UserSocketService._redis_text(sid_value)
                if await redis_client.exists(UserSocketService._sid_presence_key(sid)):
                    return True
                stale_sids.append(sid)
            if stale_sids:
                await redis_client.srem(presence_key, *stale_sids)
            if int(await redis_client.scard(presence_key) or 0) == 0:
                await redis_client.delete(presence_key)
            return False
        except Exception as exc:
            logger.warning("查询用户 socket 在线状态失败，user_kid=%s", user_kid, exc_info=exc)
            return False

    @staticmethod
    def _ensure_presence_refresh_task() -> None:
        task = UserSocketService._presence_refresh_task
        if task is not None and not task.done():
            return
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            return
        UserSocketService._presence_refresh_task = loop.create_task(
            UserSocketService._refresh_local_presence_loop()
        )

    @staticmethod
    async def _refresh_local_presence_loop() -> None:
        while True:
            await asyncio.sleep(UserSocketService._PRESENCE_REFRESH_SECONDS)
            redis_client = UserSocketService._user_redis_client()
            if redis_client is None:
                return

            sessions = list(UserSocketService._sid_to_session.values())
            if not sessions:
                return

            for session in sessions:
                try:
                    await redis_client.sadd(
                        UserSocketService._user_presence_key(session.user_kid),
                        session.sid,
                    )
                    await redis_client.set(
                        UserSocketService._sid_presence_key(session.sid),
                        str(session.user_kid),
                        ex=UserSocketService._PRESENCE_TTL_SECONDS,
                    )
                except Exception as exc:
                    logger.warning(
                        "续期用户 socket 在线状态失败，sid=%s, user_kid=%s",
                        session.sid,
                        session.user_kid,
                        exc_info=exc,
                    )

    @staticmethod
    async def _handle_connect(sid: str, environ: dict[str, Any] | None, auth: Any = None) -> bool:
        token = (
            UserSocketService._extract_token_from_auth(auth)
            or UserSocketService._extract_token_from_environ(environ)
        )
        if not token:
            logger.warning("用户 socket 连接缺少 token，sid=%s", sid)
            return False

        try:
            user_info = await UserSocketService._authenticate_socket_token(token)
        except Exception as exc:
            logger.warning("用户 socket 鉴权失败，sid=%s", sid, exc_info=exc)
            return False

        session = UserSocketSession(
            sid=sid,
            user_kid=int(user_info.kid),
            access_expires_at=int(getattr(user_info, "expires_at", 0) or 0),
        )
        UserSocketService._add_session(session)
        UserSocketService._schedule_socket_token_expiry(session)
        await UserSocketService._enter_user_room(sid=sid, user_kid=session.user_kid)
        await UserSocketService._mark_user_socket_online(session)
        logger.info("用户 socket 鉴权成功，sid=%s, user_kid=%s", sid, session.user_kid)
        await UserSocketService._on_user_socket_authenticated(
            user_kid=session.user_kid,
            sid=sid,
        )
        return True

    @staticmethod
    async def _handle_disconnect(sid: str) -> None:
        session = UserSocketService._remove_session(sid)
        if session is None:
            logger.info("未知用户 socket 断开，sid=%s", sid)
            return
        await UserSocketService._leave_user_room(sid=sid, user_kid=session.user_kid)
        await UserSocketService._mark_user_socket_offline(session)
        logger.info("用户 socket 断开，sid=%s, user_kid=%s", sid, session.user_kid)

    @staticmethod
    async def _on_user_socket_authenticated(
        user_kid: int,
        sid: str,
    ) -> None:
        """
        用户 socket 鉴权成功后的预留扩展点。

        当前默认补发该用户离线期间缓存的 API 通知；后续可在这里追加主动推送逻辑。
        """
        _ = sid
        await UserSocketService._flush_pending_messages_to_online_socket(user_kid=user_kid)

    @staticmethod
    async def _emit_to_sid(sid: str, message: UserSocketMessage) -> bool:
        socketio = UserSocketService._socketio()
        if socketio is None:
            logger.warning("Socket.IO 尚未初始化，无法发送消息，sid=%s", sid)
            return False
        try:
            await socketio.emit(
                event=UserSocketService.NOTICE_EVENT,
                data=UserSocketService._message_to_payload(message),
                to=sid,
                namespace=UserSocketService.SOCKET_NAMESPACE,
            )
            return True
        except Exception as exc:
            logger.warning("用户 socket 消息发送失败，sid=%s", sid, exc_info=exc)
            return False

    @staticmethod
    async def _emit_to_user_room(message: UserSocketMessage) -> bool:
        socketio_server = UserSocketService._socketio()
        user_kid = int(getattr(message, "user_kid"))
        if socketio_server is None:
            logger.warning("Socket.IO 尚未初始化，无法发送消息，user_kid=%s", user_kid)
            return False
        try:
            await socketio_server.emit(
                event=UserSocketService.NOTICE_EVENT,
                data=UserSocketService._message_to_payload(message),
                to=UserSocketService._user_room(user_kid),
                namespace=UserSocketService.SOCKET_NAMESPACE,
            )
            return True
        except Exception as exc:
            logger.warning("用户 socket room 消息发送失败，user_kid=%s", user_kid, exc_info=exc)
            return False

    @staticmethod
    async def _emit_to_online_user(message: UserSocketMessage) -> bool:
        user_kid = int(getattr(message, "user_kid"))
        sids = set(UserSocketService._user_kid_to_sids.get(user_kid, set()))
        if not sids:
            return False

        has_success = False
        failed_sids: list[str] = []
        for sid in sids:
            if await UserSocketService._emit_to_sid(sid, message):
                has_success = True
            else:
                failed_sids.append(sid)

        for sid in failed_sids:
            failed_session = UserSocketService._remove_session(sid)
            if failed_session is not None:
                await UserSocketService._leave_user_room(sid=sid, user_kid=failed_session.user_kid)
                await UserSocketService._mark_user_socket_offline(failed_session)
        return has_success

    @staticmethod
    async def _emit_to_user(message: UserSocketMessage) -> bool:
        if not UserSocketService._uses_distributed_socket_cluster():
            return await UserSocketService._emit_to_online_user(message)

        if not await UserSocketService._has_online_user_socket(int(getattr(message, "user_kid"))):
            return False

        # AsyncRedisManager 通过 room 广播到所有实例；presence 负责判断是否应缓存离线消息。
        if await UserSocketService._emit_to_user_room(message):
            return True
        return await UserSocketService._emit_to_online_user(message)

    @staticmethod
    async def _cache_message(message: UserSocketMessage) -> None:
        db = DefaultStorage.instance()
        async with db.session_scope() as session:
            session.add(
                UserSocketMessage(
                    kid=int(getattr(message, "kid")),
                    user_kid=int(getattr(message, "user_kid")),
                    api_uri=str(getattr(message, "api_uri")),
                    kid_for_api=getattr(message, "kid_for_api"),
                )
            )
            await session.flush()

    @staticmethod
    async def handle_socket_connection(
        event: Literal["connect", "disconnect"],
        sid: str,
        environ: dict[str, Any] | None = None,
        auth: Any = None,
    ) -> bool | None:
        """
        处理用户端 Socket.IO 长连接生命周期事件。

        Router 只透传 socket.io 事件参数，鉴权、绑定与断开清理都收敛在 service 内部。
        """
        if event == "connect":
            return await UserSocketService._handle_connect(sid=sid, environ=environ, auth=auth)
        if event == "disconnect":
            await UserSocketService._handle_disconnect(sid=sid)
            return None
        raise ValueError(f"不支持的用户 socket 事件: {event}")

    @staticmethod
    async def _flush_pending_messages_to_online_socket(user_kid: int) -> int:
        if not UserSocketService._user_kid_to_sids.get(int(user_kid)):
            return 0

        db = DefaultStorage.instance()
        sent_count = 0
        async with db.session_scope() as session:
            result = await session.execute(
                select(UserSocketMessage)
                .where(UserSocketMessage.user_kid == int(user_kid))
                .order_by(UserSocketMessage.id.asc())
                .limit(UserSocketService._MAX_PENDING_MESSAGES_ON_CONNECT)
            )
            messages = list(result.scalars().all())
            for message in messages:
                if await UserSocketService._emit_to_online_user(message):
                    await session.delete(message)
                    sent_count += 1
            if sent_count:
                await session.flush()
        return sent_count
