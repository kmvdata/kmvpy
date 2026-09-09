import hashlib
import hmac
import json
import secrets
import time
from dataclasses import dataclass
from typing import Any, Literal, Optional

from fastapi import HTTPException, Request, Response, status
from redis.asyncio import Redis

from kmvpy.common.conf import AuthJwtConfig, RedisConfig
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo

AuthRole = Literal["user", "admin"]

ACCESS_TOKEN_RENEW_WINDOW_SECONDS = 60
SESSION_COOKIE_SAMESITE_USER = "lax"
SESSION_COOKIE_SAMESITE_ADMIN = "strict"
SESSION_COOKIE_PATH = "/"
SESSION_COOKIE_NAMES = {
    "user": "__Host-kmvpy-user-session",
    "admin": "__Host-kmvpy-admin-session",
}


@dataclass(frozen=True)
class AuthToken:
    token: str
    token_type: str
    expire_hours: float
    expires_at: int
    sid: str
    jti: str
    session_cookie_value: str = ""
    session_cookie_max_age: int = 0


class AuthSessionService:
    """Redis login session + short access JWT boundary service."""

    _redis_clients: dict[str, Redis] = {}

    @classmethod
    def _raise_unauthorized(cls) -> None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="未登录或登录已失效",
            headers={"WWW-Authenticate": "Bearer"},
        )

    @classmethod
    def _role_config(cls, auth_role: str) -> AuthJwtConfig:
        auth_config = getattr(getattr(kosmos, "config", None), "auth_config", None)
        role_config = getattr(auth_config, auth_role, None) if auth_config is not None else None
        if role_config is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="鉴权失败：认证配置缺失",
            )
        return role_config

    @classmethod
    def _redis_config(cls, auth_role: str) -> Optional[RedisConfig]:
        return cls._role_config(auth_role).redis

    @classmethod
    def _redis(cls, auth_role: str) -> Redis | None:
        redis_config = cls._redis_config(auth_role)
        if redis_config is None:
            return None

        client = cls._redis_clients.get(auth_role)
        if client is not None:
            return client

        client = Redis(
            host=redis_config.host,
            port=redis_config.port,
            db=redis_config.db,
            username=redis_config.username,
            password=redis_config.password,
            decode_responses=redis_config.decode_responses,
        )
        cls._redis_clients[auth_role] = client
        return client

    @staticmethod
    def _session_key(auth_role: str, sid: str) -> str:
        return f"auth:{auth_role}:session:{sid}"

    @staticmethod
    def _session_family_key(auth_role: str, session_family_id: str) -> str:
        return f"auth:{auth_role}:session_family:{session_family_id}"

    @staticmethod
    def _user_sessions_key(auth_role: str, kid: int) -> str:
        return f"auth:{auth_role}:user_sessions:{kid}"

    @staticmethod
    def _now_ts() -> int:
        return int(time.time())

    @staticmethod
    def _secret_hash(session_secret: str) -> str:
        return hashlib.sha256(session_secret.encode("utf-8")).hexdigest()

    @staticmethod
    def _constant_time_equal(left: str, right: str) -> bool:
        return hmac.compare_digest(str(left or ""), str(right or ""))

    @staticmethod
    def _redis_text(value: Any) -> str:
        if isinstance(value, bytes):
            return value.decode("utf-8")
        return str(value)

    @classmethod
    def _session_cookie_name(cls, auth_role: str) -> str:
        return SESSION_COOKIE_NAMES[auth_role]

    @classmethod
    def _session_cookie_samesite(cls, auth_role: str) -> str:
        if auth_role == "admin":
            return SESSION_COOKIE_SAMESITE_ADMIN
        return SESSION_COOKIE_SAMESITE_USER

    @classmethod
    def _session_cookie_secure(cls) -> bool:
        return True

    @classmethod
    def _apply_session_cookie(
        cls,
        response: Response,
        *,
        auth_role: str,
        cookie_value: str,
        max_age: int,
    ) -> None:
        response.set_cookie(
            key=cls._session_cookie_name(auth_role),
            value=cookie_value,
            max_age=max(0, int(max_age)),
            httponly=True,
            secure=cls._session_cookie_secure(),
            samesite=cls._session_cookie_samesite(auth_role),
            path=SESSION_COOKIE_PATH,
        )

    @classmethod
    def _clear_session_cookie(cls, response: Response, *, auth_role: str) -> None:
        response.delete_cookie(
            key=cls._session_cookie_name(auth_role),
            path=SESSION_COOKIE_PATH,
            secure=cls._session_cookie_secure(),
            httponly=True,
            samesite=cls._session_cookie_samesite(auth_role),
        )

    @classmethod
    def attach_session_cookie(
        cls,
        response: Response,
        *,
        auth_role: AuthRole,
        cookie_value: str,
        max_age: int,
    ) -> None:
        cls._apply_session_cookie(
            response,
            auth_role=auth_role,
            cookie_value=cookie_value,
            max_age=max_age,
        )

    @classmethod
    def clear_session_cookie(cls, response: Response, *, auth_role: AuthRole) -> None:
        cls._clear_session_cookie(response, auth_role=auth_role)

    @classmethod
    def _stage_session_cookie(
        cls,
        request: Request | None,
        *,
        auth_role: str,
        cookie_value: str,
        max_age: int,
    ) -> None:
        if request is None:
            return
        pending = list(getattr(request.state, "auth_pending_cookies", []))
        pending.append({
            "action": "set",
            "auth_role": auth_role,
            "cookie_value": cookie_value,
            "max_age": int(max_age),
        })
        request.state.auth_pending_cookies = pending

    @classmethod
    def _stage_clear_session_cookie(cls, request: Request | None, *, auth_role: str) -> None:
        if request is None:
            return
        pending = list(getattr(request.state, "auth_pending_cookies", []))
        pending.append({"action": "clear", "auth_role": auth_role})
        request.state.auth_pending_cookies = pending

    @classmethod
    def apply_pending_cookies(cls, request: Request, response: Response) -> None:
        for pending in list(getattr(request.state, "auth_pending_cookies", [])):
            auth_role = str(pending.get("auth_role") or "")
            if auth_role not in SESSION_COOKIE_NAMES:
                continue
            if pending.get("action") == "clear":
                cls._clear_session_cookie(response, auth_role=auth_role)
            elif pending.get("action") == "set":
                cls._apply_session_cookie(
                    response,
                    auth_role=auth_role,
                    cookie_value=str(pending.get("cookie_value") or ""),
                    max_age=int(pending.get("max_age") or 0),
                )

    @classmethod
    def stage_renew_candidate(
        cls,
        request: Request,
        *,
        auth_role: AuthRole,
        token: str,
        payload: dict[str, Any],
    ) -> None:
        request.state.auth_renew_candidate = {
            "auth_role": auth_role,
            "token": token,
            "payload": payload,
        }

    @classmethod
    def _session_ttl(cls, payload: dict[str, Any], *, now: int | None = None) -> int:
        current = now if now is not None else cls._now_ts()
        idle_remaining = int(payload["idle_expires_at"]) - current
        absolute_remaining = int(payload["absolute_expires_at"]) - current
        return max(0, min(idle_remaining, absolute_remaining))

    @classmethod
    async def issue_token(
        cls,
        user_info: JwtUserInfo,
        *,
        auth_role: AuthRole,
        device_id: str = "",
        device_name: str = "",
        platform: str = "",
        request: Request | None = None,
        response: Response | None = None,
    ) -> AuthToken:
        role_config = cls._role_config(auth_role)
        redis = cls._redis(auth_role)
        if redis is None:
            raise RuntimeError("auth_config.*.redis 必须配置才能创建登录 session")

        now = cls._now_ts()
        sid = secrets.token_urlsafe(32)
        session_secret = secrets.token_urlsafe(48)
        session_family_id = secrets.token_urlsafe(32)
        jti = secrets.token_urlsafe(32)
        absolute_expires_at = now + role_config.session.absolute_timeout_seconds
        idle_expires_at = min(
            now + role_config.session.idle_timeout_seconds,
            absolute_expires_at,
        )

        enriched_user_info = JwtUserInfo(
            kid=user_info.kid,
            user_type=user_info.user_type,
            device_id=device_id,
            device_name=device_name,
            platform=platform,
            sid=sid,
            jti=jti,
            auth_role=auth_role,
        )
        token = JwtService.encode_token(
            enriched_user_info,
            auth_role=auth_role,
            extra_claims={"sid": sid, "jti": jti, "role": auth_role},
        )
        payload = JwtService.decode_token(token, auth_role=auth_role)

        session_payload = {
            "schema_version": 1,
            "sid": sid,
            "session_family_id": session_family_id,
            "role": auth_role,
            "kid": int(user_info.kid),
            "user_type": int(user_info.user_type),
            "device_id": device_id,
            "device_name": device_name,
            "platform": platform,
            "issued_at": now,
            "last_active_at": now,
            "idle_expires_at": idle_expires_at,
            "absolute_expires_at": absolute_expires_at,
            "session_secret_hash": cls._secret_hash(session_secret),
            "rotated_at": now,
        }
        ttl = cls._session_ttl(session_payload, now=now)
        await redis.set(cls._session_key(auth_role, sid), json.dumps(session_payload), ex=ttl)
        await redis.sadd(cls._session_family_key(auth_role, session_family_id), sid)
        await redis.expire(
            cls._session_family_key(auth_role, session_family_id),
            max(1, absolute_expires_at - now),
        )
        await redis.zadd(cls._user_sessions_key(auth_role, int(user_info.kid)), {sid: now})
        await redis.expire(
            cls._user_sessions_key(auth_role, int(user_info.kid)),
            max(1, absolute_expires_at - now),
        )
        await cls._enforce_max_sessions(auth_role, int(user_info.kid), current_sid=sid)

        cookie_value = f"{sid}.{session_secret}"
        cls._stage_session_cookie(
            request,
            auth_role=auth_role,
            cookie_value=cookie_value,
            max_age=ttl,
        )
        if response is not None:
            cls._apply_session_cookie(
                response,
                auth_role=auth_role,
                cookie_value=cookie_value,
                max_age=ttl,
            )

        return AuthToken(
            token=token,
            token_type="Bearer",
            expire_hours=float(role_config.jwt.access_token_lifetime_hours),
            expires_at=int(payload["exp"]),
            sid=sid,
            jti=jti,
            session_cookie_value=cookie_value,
            session_cookie_max_age=ttl,
        )

    @classmethod
    async def _enforce_max_sessions(cls, auth_role: str, kid: int, current_sid: str) -> None:
        role_config = cls._role_config(auth_role)
        max_sessions = role_config.session.max_sessions_per_user
        redis = cls._redis(auth_role)
        if redis is None or max_sessions is None:
            return

        sessions_key = cls._user_sessions_key(auth_role, kid)
        count = int(await redis.zcard(sessions_key) or 0)
        if count <= max_sessions:
            return

        remove_count = count - max_sessions
        sessions = [cls._redis_text(sid) for sid in await redis.zrange(sessions_key, 0, -1)]
        candidates = [sid for sid in sessions if sid != current_sid][:remove_count]
        for sid in candidates:
            await cls._delete_session_by_sid(auth_role, sid)

    @classmethod
    async def verify_token(cls, token: str, *, auth_role: AuthRole) -> JwtUserInfo:
        payload = JwtService.decode_token(token, auth_role=auth_role)
        return JwtService.payload_to_user_info(payload)

    @classmethod
    async def maybe_renew_access_token(
        cls,
        request: Request,
        response: Response,
        *,
        auth_role: AuthRole,
        token: str,
        payload: dict[str, Any],
    ) -> AuthToken | None:
        _ = token
        now = cls._now_ts()
        expires_at = int(payload.get("exp") or 0)
        if expires_at - now > ACCESS_TOKEN_RENEW_WINDOW_SECONDS:
            return None

        redis = cls._redis(auth_role)
        if redis is None:
            return None

        sid = str(payload.get("sid") or "")
        cookie_value = request.cookies.get(cls._session_cookie_name(auth_role), "")
        cookie_sid, session_secret = cls._parse_session_cookie(cookie_value)
        if not cookie_sid or not session_secret:
            return None
        if cookie_sid != sid:
            return None

        raw_session = await redis.get(cls._session_key(auth_role, sid))
        if not raw_session:
            cls._clear_session_cookie(response, auth_role=auth_role)
            return None

        try:
            session_payload = json.loads(cls._redis_text(raw_session))
        except json.JSONDecodeError:
            await cls._delete_session_by_sid(auth_role, sid)
            cls._clear_session_cookie(response, auth_role=auth_role)
            return None

        cls._validate_session_matches_access_token(
            session_payload,
            auth_role=auth_role,
            access_payload=payload,
        )

        if cls._session_is_expired(session_payload, now=now):
            await cls._delete_session_by_sid(auth_role, sid)
            cls._clear_session_cookie(response, auth_role=auth_role)
            return None

        if not cls._constant_time_equal(
            session_payload.get("session_secret_hash", ""),
            cls._secret_hash(session_secret),
        ):
            await cls._revoke_session_family(auth_role, session_payload, fallback_sid=sid)
            cls._clear_session_cookie(response, auth_role=auth_role)
            logger.warning("检测到登录 session secret replay，auth_role=%s, sid=%s", auth_role, sid)
            cls._raise_unauthorized()

        new_session_secret = secrets.token_urlsafe(48)
        new_jti = secrets.token_urlsafe(32)
        user_info = JwtUserInfo(
            kid=int(session_payload["kid"]),
            user_type=int(session_payload["user_type"]),
            device_id=str(session_payload.get("device_id") or ""),
            device_name=str(session_payload.get("device_name") or ""),
            platform=str(session_payload.get("platform") or ""),
            sid=sid,
            jti=new_jti,
            auth_role=auth_role,
        )
        new_token = JwtService.encode_token(
            user_info,
            auth_role=auth_role,
            extra_claims={"sid": sid, "jti": new_jti, "role": auth_role},
        )
        new_payload = JwtService.decode_token(new_token, auth_role=auth_role)

        session_payload["session_secret_hash"] = cls._secret_hash(new_session_secret)
        session_payload["last_active_at"] = now
        session_payload["rotated_at"] = now
        session_payload["idle_expires_at"] = min(
            now + cls._role_config(auth_role).session.idle_timeout_seconds,
            int(session_payload["absolute_expires_at"]),
        )
        ttl = cls._session_ttl(session_payload, now=now)
        if ttl <= 0:
            await cls._delete_session_by_sid(auth_role, sid)
            cls._clear_session_cookie(response, auth_role=auth_role)
            return None

        await redis.set(cls._session_key(auth_role, sid), json.dumps(session_payload), ex=ttl)
        await redis.expire(
            cls._session_family_key(auth_role, str(session_payload["session_family_id"])),
            max(1, int(session_payload["absolute_expires_at"]) - now),
        )
        await redis.expire(
            cls._user_sessions_key(auth_role, int(session_payload["kid"])),
            max(1, int(session_payload["absolute_expires_at"]) - now),
        )

        cls._apply_session_cookie(
            response,
            auth_role=auth_role,
            cookie_value=f"{sid}.{new_session_secret}",
            max_age=ttl,
        )
        response.headers["X-Auth-Token"] = new_token
        response.headers["X-Auth-Token-Type"] = "Bearer"
        response.headers["X-Auth-Expires-At"] = str(new_payload["exp"])
        response.headers["Cache-Control"] = "no-store"

        return AuthToken(
            token=new_token,
            token_type="Bearer",
            expire_hours=float(cls._role_config(auth_role).jwt.access_token_lifetime_hours),
            expires_at=int(new_payload["exp"]),
            sid=sid,
            jti=new_jti,
            session_cookie_value=f"{sid}.{new_session_secret}",
            session_cookie_max_age=ttl,
        )

    @classmethod
    async def renew_from_request_state(cls, request: Request, response: Response) -> None:
        cls.apply_pending_cookies(request, response)
        if getattr(request.state, "auth_skip_renew", False):
            return
        if response.status_code >= 400:
            return
        candidate = getattr(request.state, "auth_renew_candidate", None)
        if not isinstance(candidate, dict):
            return
        await cls.maybe_renew_access_token(
            request,
            response,
            auth_role=candidate["auth_role"],
            token=candidate["token"],
            payload=candidate["payload"],
        )

    @staticmethod
    def _parse_session_cookie(cookie_value: str) -> tuple[str, str]:
        value = str(cookie_value or "").strip()
        if not value or "." not in value:
            return "", ""
        sid, _, session_secret = value.partition(".")
        return sid.strip(), session_secret.strip()

    @classmethod
    def _validate_session_matches_access_token(
        cls,
        session_payload: dict[str, Any],
        *,
        auth_role: str,
        access_payload: dict[str, Any],
    ) -> None:
        try:
            expected = {
                "sid": str(access_payload.get("sid") or ""),
                "role": auth_role,
                "kid": int(access_payload.get("user_kid")),
                "user_type": int(access_payload.get("user_type")),
            }
            matches = (
                str(session_payload.get("sid") or "") == expected["sid"]
                and str(session_payload.get("role") or "") == expected["role"]
                and int(session_payload.get("kid")) == expected["kid"]
                and int(session_payload.get("user_type")) == expected["user_type"]
            )
        except (TypeError, ValueError):
            matches = False
        if not matches:
            cls._raise_unauthorized()

    @classmethod
    def _session_is_expired(cls, session_payload: dict[str, Any], *, now: int | None = None) -> bool:
        current = now if now is not None else cls._now_ts()
        return (
            int(session_payload.get("idle_expires_at") or 0) <= current
            or int(session_payload.get("absolute_expires_at") or 0) <= current
        )

    @classmethod
    async def _delete_session_by_sid(cls, auth_role: str, sid: str) -> None:
        redis = cls._redis(auth_role)
        if redis is None or not sid:
            return
        raw_session = await redis.get(cls._session_key(auth_role, sid))
        if raw_session:
            try:
                session_payload = json.loads(cls._redis_text(raw_session))
                family_id = str(session_payload.get("session_family_id") or "")
                kid = int(session_payload.get("kid"))
                if family_id:
                    await redis.srem(cls._session_family_key(auth_role, family_id), sid)
                await redis.zrem(cls._user_sessions_key(auth_role, kid), sid)
            except Exception:
                pass
        await redis.delete(cls._session_key(auth_role, sid))

    @classmethod
    async def _revoke_session_family(
        cls,
        auth_role: str,
        session_payload: dict[str, Any],
        *,
        fallback_sid: str,
    ) -> None:
        redis = cls._redis(auth_role)
        if redis is None:
            return
        family_id = str(session_payload.get("session_family_id") or "")
        family_key = cls._session_family_key(auth_role, family_id) if family_id else ""
        sids = set()
        if family_key:
            sids.update(cls._redis_text(sid) for sid in await redis.smembers(family_key))
        if not sids and fallback_sid:
            sids.add(fallback_sid)
        for sid in sids:
            await cls._delete_session_by_sid(auth_role, sid)
        if family_key:
            await redis.delete(family_key)

    @classmethod
    async def recover_expired_access_token(
        cls,
        request: Request,
        response: Response,
        *,
        auth_role: AuthRole,
        token: str,
    ) -> AuthToken | None:
        _ = request, response, auth_role, token
        return None

    @classmethod
    async def revoke_token(
        cls,
        token: str,
        *,
        auth_role: AuthRole,
        request: Request | None = None,
        response: Response | None = None,
    ) -> None:
        payload = JwtService.decode_token(token, auth_role=auth_role)
        sid = str(payload.get("sid") or "")
        if sid:
            await cls._delete_session_by_sid(auth_role, sid)
        if request is not None:
            request.state.auth_skip_renew = True
            cls._stage_clear_session_cookie(request, auth_role=auth_role)
        if response is not None:
            cls._clear_session_cookie(response, auth_role=auth_role)
        logger.info("已注销当前登录 session: auth_role=%s, sid=%s", auth_role, sid)

    @classmethod
    async def revoke_user_sessions(cls, *, auth_role: AuthRole, kid: int) -> None:
        redis = cls._redis(auth_role)
        if redis is None:
            return

        sessions_key = cls._user_sessions_key(auth_role, kid)
        sessions = list(await redis.zrange(sessions_key, 0, -1))
        for sid_value in sessions:
            await cls._delete_session_by_sid(auth_role, cls._redis_text(sid_value))
        await redis.delete(sessions_key)
        logger.info("已注销用户全部登录 session: auth_role=%s, kid=%s", auth_role, kid)
