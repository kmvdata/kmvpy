import json
import secrets
from typing import Any

from fastapi import HTTPException, Request, Response
from redis.exceptions import RedisError

import kmvpy.core.main as kmvpy_main
from kmvpy.common.tool.logger import logger
from kmvpy.core.main.service.auth_session_service import (
    ACCESS_TOKEN_RENEW_WINDOW_SECONDS,
    AuthRole,
    AuthSessionService as KmvAuthSessionService,
    AuthToken,
)
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo


AUTH_TOKEN_HEADERS = (
    "X-Auth-Token",
    "X-Auth-Token-Type",
    "X-Auth-Expires-At",
)


class AuthSessionService(KmvAuthSessionService):
    """为 __PROJECT_NAME__ 提供以 Redis 空闲时效为准的滑动登录会话。"""

    _SLIDE_SESSION_LUA = r"""
local session_key = KEYS[1]
local now = tonumber(ARGV[1])
local idle_timeout = tonumber(ARGV[2])
local absolute_timeout = tonumber(ARGV[3])
local expected_sid = ARGV[4]
local expected_role = ARGV[5]
local expected_kid = ARGV[6]
local expected_user_type = tonumber(ARGV[7])
local expected_secret_hash = ARGV[8]
local family_key_prefix = ARGV[9]
local user_sessions_key_prefix = ARGV[10]

local raw = redis.call("GET", session_key)
if not raw then
    return {"missing"}
end

local decoded_ok, session = pcall(cjson.decode, raw)
if not decoded_ok or type(session) ~= "table" then
    redis.call("DEL", session_key)
    return {"corrupt"}
end

-- KID may be a Snowflake/BIGINT outside Lua's exact double range. Read its
-- original JSON digits and never cjson-encode the session again.
local stored_kid = string.match(raw, '"kid"%s*:%s*"([0-9]+)"')
if not stored_kid then
    stored_kid = string.match(raw, '"kid"%s*:%s*([0-9]+)')
end

local function constant_time_equal(left, right)
    if type(left) ~= "string" or type(right) ~= "string" then
        return false
    end
    local max_len = math.max(string.len(left), string.len(right))
    local different = string.len(left) == string.len(right) and 0 or 1
    for index = 1, max_len do
        if string.byte(left, index) ~= string.byte(right, index) then
            different = different + 1
        end
    end
    return different == 0
end

local identity_matches =
    tostring(session.sid or "") == expected_sid and
    tostring(session.role or "") == expected_role and
    stored_kid == expected_kid and
    tonumber(session.user_type) == expected_user_type
if not identity_matches then
    return {"identity_mismatch"}
end

if not constant_time_equal(
    tostring(session.session_secret_hash or ""),
    expected_secret_hash
) then
    return {"secret_mismatch"}
end

local idle_expires_at = tonumber(session.idle_expires_at or 0)
local absolute_expires_at = tonumber(session.absolute_expires_at or 0)
if idle_expires_at <= now or absolute_expires_at <= now then
    redis.call("DEL", session_key)
    local family_id = tostring(session.session_family_id or "")
    if family_id ~= "" then
        local family_key = family_key_prefix .. family_id
        redis.call("SREM", family_key, expected_sid)
        if redis.call("SCARD", family_key) == 0 then
            redis.call("DEL", family_key)
        end
    end
    local user_sessions_key = user_sessions_key_prefix .. expected_kid
    redis.call("ZREM", user_sessions_key, expected_sid)
    if redis.call("ZCARD", user_sessions_key) == 0 then
        redis.call("DEL", user_sessions_key)
    end
    return {"expired"}
end

local new_idle_expires_at = now + idle_timeout
local new_absolute_expires_at = now + absolute_timeout
local ttl = math.min(idle_timeout, absolute_timeout)
if ttl <= 0 then
    return {"expired"}
end

local function replace_integer(document, field, value)
    local pattern = '("' .. field .. '"%s*:%s*)%-?%d+'
    local updated, replacements = string.gsub(
        document,
        pattern,
        '%1' .. tostring(value),
        1
    )
    if replacements ~= 1 then
        return nil
    end
    return updated
end

local updated = replace_integer(raw, "last_active_at", now)
if not updated then
    redis.call("DEL", session_key)
    return {"corrupt"}
end
updated = replace_integer(updated, "idle_expires_at", new_idle_expires_at)
if not updated then
    redis.call("DEL", session_key)
    return {"corrupt"}
end
updated = replace_integer(updated, "absolute_expires_at", new_absolute_expires_at)
if not updated then
    redis.call("DEL", session_key)
    return {"corrupt"}
end

redis.call("SET", session_key, updated, "EX", ttl)
local family_id = tostring(session.session_family_id or "")
if family_id ~= "" then
    redis.call("EXPIRE", family_key_prefix .. family_id, ttl)
end
redis.call("EXPIRE", user_sessions_key_prefix .. expected_kid, ttl)

return {"ok", updated, tostring(ttl)}
"""

    _TRANSIENT_REDIS_ERRORS = (RedisError, OSError, TimeoutError)

    @staticmethod
    def _claim_integer_text(value: Any, *, claim_name: str) -> str:
        if isinstance(value, bool):
            JwtService._raise_unauthorized(f"Token {claim_name} 非法，请重新登录")
        if isinstance(value, int):
            return str(value)
        if isinstance(value, str):
            normalized = value.strip()
            if normalized and normalized.isdigit():
                return str(int(normalized))
        JwtService._raise_unauthorized(f"Token {claim_name} 非法，请重新登录")

    @classmethod
    def _validate_access_payload(
        cls,
        payload: dict[str, Any],
        *,
        auth_role: AuthRole,
    ) -> tuple[str, str]:
        sid = str(payload.get("sid") or "").strip()
        if not sid or not str(payload.get("jti") or "").strip():
            JwtService._raise_unauthorized("Token 会话标识缺失，请重新登录")

        if payload.get("role") != auth_role or payload.get("auth_role") != auth_role:
            JwtService._raise_unauthorized("Token 角色不匹配，请重新登录")

        user_kid = cls._claim_integer_text(
            payload.get("user_kid"),
            claim_name="user_kid",
        )
        subject = cls._claim_integer_text(payload.get("sub"), claim_name="sub")
        if subject != user_kid:
            JwtService._raise_unauthorized("Token 用户标识不一致，请重新登录")

        user_type = cls._claim_integer_text(
            payload.get("user_type"),
            claim_name="user_type",
        )
        return user_kid, user_type

    @classmethod
    def _stage_cookie_clear(cls, request: Request, *, auth_role: AuthRole) -> None:
        cls._stage_clear_session_cookie(request, auth_role=auth_role)

    @classmethod
    async def _touch_authenticated_session(
        cls,
        request: Request,
        *,
        auth_role: AuthRole,
        payload: dict[str, Any],
        access_token_expired: bool,
    ) -> tuple[dict[str, Any], str, int] | None:
        user_kid, user_type = cls._validate_access_payload(payload, auth_role=auth_role)
        sid = str(payload["sid"])
        cookie_value = request.cookies.get(cls._session_cookie_name(auth_role), "")
        cookie_sid, session_secret = cls._parse_session_cookie(cookie_value)
        if not cookie_sid or not session_secret or cookie_sid != sid:
            cls._stage_cookie_clear(request, auth_role=auth_role)
            cls._raise_unauthorized()

        redis = cls._redis(auth_role)
        if redis is None:
            if access_token_expired:
                cls._raise_unauthorized()
            logger.warning(
                "认证 Redis 未配置，暂时仅按未过期 JWT 放行: auth_role=%s",
                auth_role,
            )
            request.state.auth_session_redis_degraded = True
            return None

        role_config = cls._role_config(auth_role)
        now = cls._now_ts()
        try:
            result = await redis.eval(
                cls._SLIDE_SESSION_LUA,
                1,
                cls._session_key(auth_role, sid),
                str(now),
                str(role_config.session.idle_timeout_seconds),
                str(role_config.session.absolute_timeout_seconds),
                sid,
                auth_role,
                user_kid,
                user_type,
                cls._secret_hash(session_secret),
                f"auth:{auth_role}:session_family:",
                f"auth:{auth_role}:user_sessions:",
            )
        except cls._TRANSIENT_REDIS_ERRORS as exc:
            if access_token_expired:
                logger.warning(
                    "JWT 过期恢复时认证 Redis 不可用，拒绝恢复: auth_role=%s",
                    auth_role,
                    exc_info=exc,
                )
                cls._raise_unauthorized()
            logger.warning(
                "认证 Redis 暂时不可用，按未过期 JWT 短暂放行: auth_role=%s",
                auth_role,
                exc_info=exc,
            )
            request.state.auth_session_redis_degraded = True
            return None

        if not isinstance(result, (list, tuple)) or not result:
            cls._stage_cookie_clear(request, auth_role=auth_role)
            cls._raise_unauthorized()

        status = cls._redis_text(result[0])
        if status != "ok":
            cls._stage_cookie_clear(request, auth_role=auth_role)
            logger.warning(
                "认证 session 校验失败: auth_role=%s, status=%s",
                auth_role,
                status,
            )
            cls._raise_unauthorized()

        try:
            session_payload = json.loads(cls._redis_text(result[1]))
            ttl = int(cls._redis_text(result[2]))
        except (IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
            logger.warning(
                "认证 session 原子更新返回非法: auth_role=%s",
                auth_role,
                exc_info=exc,
            )
            cls._stage_cookie_clear(request, auth_role=auth_role)
            cls._raise_unauthorized()

        if ttl <= 0:
            cls._stage_cookie_clear(request, auth_role=auth_role)
            cls._raise_unauthorized()
        return session_payload, cookie_value, ttl

    @classmethod
    def _stage_authenticated_candidate(
        cls,
        request: Request,
        *,
        auth_role: AuthRole,
        token: str,
        payload: dict[str, Any],
        session_payload: dict[str, Any],
        cookie_value: str,
        cookie_max_age: int,
        access_token_expired: bool,
    ) -> dict[str, Any]:
        cls.stage_renew_candidate(
            request,
            auth_role=auth_role,
            token=token,
            payload=payload,
            session_payload=session_payload,
            session_cookie_value=cookie_value,
            session_cookie_max_age=cookie_max_age,
            access_token_expired=access_token_expired,
        )
        return request.state.auth_renew_candidate

    @classmethod
    def stage_renew_candidate(
        cls,
        request: Request,
        *,
        auth_role: AuthRole,
        token: str,
        payload: dict[str, Any],
        session_payload: dict[str, Any] | None = None,
        session_cookie_value: str = "",
        session_cookie_max_age: int = 0,
        access_token_expired: bool = False,
    ) -> None:
        super().stage_renew_candidate(
            request,
            auth_role=auth_role,
            token=token,
            payload=payload,
        )
        if session_payload is None:
            return
        request.state.auth_renew_candidate.update(
            {
                "session_payload": session_payload,
                "session_cookie_value": session_cookie_value,
                "session_cookie_max_age": session_cookie_max_age,
                "access_token_expired": access_token_expired,
            }
        )

    @classmethod
    async def authenticate_access_token(
        cls,
        request: Request,
        *,
        auth_role: AuthRole,
        token: str,
    ) -> dict[str, Any]:
        payload = JwtService.decode_token(token, auth_role=auth_role)
        touched = await cls._touch_authenticated_session(
            request,
            auth_role=auth_role,
            payload=payload,
            access_token_expired=False,
        )
        if touched is not None:
            session_payload, cookie_value, ttl = touched
            cls._stage_authenticated_candidate(
                request,
                auth_role=auth_role,
                token=token,
                payload=payload,
                session_payload=session_payload,
                cookie_value=cookie_value,
                cookie_max_age=ttl,
                access_token_expired=False,
            )
        return payload

    @classmethod
    def _build_renewed_token(
        cls,
        *,
        auth_role: AuthRole,
        session_payload: dict[str, Any],
        cookie_value: str,
        cookie_max_age: int,
    ) -> AuthToken:
        sid = str(session_payload["sid"])
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
        return AuthToken(
            token=new_token,
            token_type="Bearer",
            expire_hours=float(cls._role_config(auth_role).jwt.access_token_lifetime_hours),
            expires_at=int(new_payload["exp"]),
            sid=sid,
            jti=new_jti,
            session_cookie_value=cookie_value,
            session_cookie_max_age=cookie_max_age,
        )

    @staticmethod
    def _attach_renewed_token(response: Response, auth_token: AuthToken) -> None:
        response.headers["X-Auth-Token"] = auth_token.token
        response.headers["X-Auth-Token-Type"] = auth_token.token_type
        response.headers["X-Auth-Expires-At"] = str(auth_token.expires_at)
        response.headers["Cache-Control"] = "no-store"

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
        candidate = getattr(request.state, "auth_renew_candidate", None)
        if not isinstance(candidate, dict):
            return None
        if candidate.get("auth_role") != auth_role or candidate.get("token") != token:
            return None
        if not isinstance(candidate.get("session_payload"), dict):
            return None

        now = cls._now_ts()
        expires_at = int(payload.get("exp") or 0)
        is_expired = bool(candidate.get("access_token_expired"))
        if not is_expired and expires_at - now > ACCESS_TOKEN_RENEW_WINDOW_SECONDS:
            return None

        prepared = candidate.get("prepared_auth_token")
        if isinstance(prepared, AuthToken):
            auth_token = prepared
        else:
            auth_token = cls._build_renewed_token(
                auth_role=auth_role,
                session_payload=candidate["session_payload"],
                cookie_value=str(candidate["session_cookie_value"]),
                cookie_max_age=int(candidate["session_cookie_max_age"]),
            )
            candidate["prepared_auth_token"] = auth_token

        cls._attach_renewed_token(response, auth_token)
        return auth_token

    @classmethod
    async def recover_expired_access_token(
        cls,
        request: Request,
        response: Response,
        *,
        auth_role: AuthRole,
        token: str,
    ) -> AuthToken | None:
        payload = JwtService.decode_token_without_exp(token, auth_role=auth_role)
        cls._validate_access_payload(payload, auth_role=auth_role)
        if int(payload.get("exp") or 0) > cls._now_ts():
            return None

        touched = await cls._touch_authenticated_session(
            request,
            auth_role=auth_role,
            payload=payload,
            access_token_expired=True,
        )
        if touched is None:
            cls._raise_unauthorized()
        session_payload, cookie_value, ttl = touched
        candidate = cls._stage_authenticated_candidate(
            request,
            auth_role=auth_role,
            token=token,
            payload=payload,
            session_payload=session_payload,
            cookie_value=cookie_value,
            cookie_max_age=ttl,
            access_token_expired=True,
        )
        auth_token = cls._build_renewed_token(
            auth_role=auth_role,
            session_payload=session_payload,
            cookie_value=cookie_value,
            cookie_max_age=ttl,
        )
        candidate["prepared_auth_token"] = auth_token
        cls._attach_renewed_token(response, auth_token)
        return auth_token

    @classmethod
    async def renew_from_request_state(cls, request: Request, response: Response) -> None:
        if getattr(request.state, "auth_skip_renew", False):
            for header_name in AUTH_TOKEN_HEADERS:
                if header_name in response.headers:
                    del response.headers[header_name]
            return

        cls.apply_pending_cookies(request, response)
        candidate = getattr(request.state, "auth_renew_candidate", None)
        if not isinstance(candidate, dict):
            return
        if not isinstance(candidate.get("session_payload"), dict):
            return

        cls._apply_session_cookie(
            response,
            auth_role=candidate["auth_role"],
            cookie_value=str(candidate["session_cookie_value"]),
            max_age=int(candidate["session_cookie_max_age"]),
        )
        await cls.maybe_renew_access_token(
            request,
            response,
            auth_role=candidate["auth_role"],
            token=candidate["token"],
            payload=candidate["payload"],
        )

    @classmethod
    async def revoke_token(
        cls,
        token: str,
        *,
        auth_role: AuthRole,
        request: Request | None = None,
        response: Response | None = None,
    ) -> None:
        payload = JwtService.decode_token_without_exp(token, auth_role=auth_role)
        cls._validate_access_payload(payload, auth_role=auth_role)
        sid = str(payload.get("sid") or "")
        if sid:
            await cls._delete_session_by_sid(auth_role, sid)

        if request is not None:
            request.state.auth_skip_renew = True
            request.state.auth_renew_candidate = None
            request.state.auth_pending_cookies = []
            cls._stage_clear_session_cookie(request, auth_role=auth_role)
        if response is not None:
            cls._clear_session_cookie(response, auth_role=auth_role)
            for header_name in AUTH_TOKEN_HEADERS:
                if header_name in response.headers:
                    del response.headers[header_name]
        logger.info("已注销当前登录 session: auth_role=%s, sid=%s", auth_role, sid)


def install_kmvpy_auth_session_service() -> None:
    """把 kmvpy 的外层续签中间件绑定到本工程的会话实现。"""

    kmvpy_main.AuthSessionService = AuthSessionService


__all__ = ["AuthRole", "AuthSessionService", "AuthToken", "install_kmvpy_auth_session_service"]
