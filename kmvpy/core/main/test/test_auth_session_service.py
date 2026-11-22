import asyncio
import json
import time

import pytest
from fastapi import HTTPException, Response
from starlette.requests import Request

from kmvpy.common.kmv import kosmos
from kmvpy.core.main.service.auth_session_service import AuthSessionService
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo

from .auth_test_utils import FakeRedis, build_auth_config_dict, build_base_config


@pytest.fixture(autouse=True)
def reset_auth_state():
    had_config = "config" in vars(kosmos)
    previous_config = getattr(kosmos, "config", None)
    AuthSessionService._redis_clients.clear()
    yield
    AuthSessionService._redis_clients.clear()
    if had_config:
        kosmos.config = previous_config
    elif "config" in vars(kosmos):
        delattr(kosmos, "config")


def _request_with_cookie(name: str, value: str) -> Request:
    return Request({
        "type": "http",
        "method": "POST",
        "path": "/api/protected",
        "headers": [(b"cookie", f"{name}={value}".encode("utf-8"))],
    })


def _configure_user_auth(
    *,
    access_hours: float = 0.01,
    idle_hours: float = 1.0,
    absolute_hours: float = 8.0,
    max_sessions: int | None = None,
    env: str = "test",
    debug: bool = True,
) -> FakeRedis:
    auth_config = build_auth_config_dict(
        user_access_hours=access_hours,
        user_idle_hours=idle_hours,
        user_absolute_hours=absolute_hours,
        user_max_sessions=max_sessions,
    )
    kosmos.config = build_base_config(auth_config=auth_config, env=env, debug=debug)
    fake_redis = FakeRedis()
    AuthSessionService._redis_clients["user"] = fake_redis
    return fake_redis


def _configure_admin_auth(*, env: str = "main", debug: bool = False) -> FakeRedis:
    kosmos.config = build_base_config(env=env, debug=debug)
    fake_redis = FakeRedis()
    AuthSessionService._redis_clients["admin"] = fake_redis
    return fake_redis


def test_issue_token_writes_session_hash_ttl_and_user_cookie() -> None:
    fake_redis = _configure_user_auth(idle_hours=1.0, absolute_hours=8.0)
    response = Response()

    auth_token = asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
        device_id="device-1",
        device_name="Chrome",
        platform="web",
        response=response,
    ))

    session_key = AuthSessionService._session_key("user", auth_token.sid)
    session_payload = json.loads(fake_redis.values[session_key])
    assert session_payload["schema_version"] == 1
    assert session_payload["sid"] == auth_token.sid
    assert session_payload["role"] == "user"
    assert session_payload["kid"] == 1
    assert session_payload["device_id"] == "device-1"
    assert "session_secret_hash" in session_payload
    assert auth_token.session_cookie_value.split(".", 1)[1] not in fake_redis.values[session_key]
    assert "session_secret" not in session_payload
    assert fake_redis.expires[session_key] == 3600

    set_cookie = response.headers["set-cookie"]
    assert "__Host-kmvpy-user-session=" in set_cookie
    assert "HttpOnly" in set_cookie
    assert "Path=/" in set_cookie
    assert "SameSite=lax" in set_cookie
    assert "Secure" in set_cookie


def test_admin_cookie_is_secure_and_strict_in_production() -> None:
    _configure_admin_auth(env="main", debug=False)
    response = Response()

    asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=100, user_type=100),
        auth_role="admin",
        response=response,
    ))

    set_cookie = response.headers["set-cookie"]
    assert "__Host-kmvpy-admin-session=" in set_cookie
    assert "HttpOnly" in set_cookie
    assert "Path=/" in set_cookie
    assert "SameSite=strict" in set_cookie
    assert "Secure" in set_cookie


def test_maybe_renew_skips_token_outside_internal_window() -> None:
    fake_redis = _configure_user_auth(access_hours=0.5)
    issue_response = Response()
    auth_token = asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
        response=issue_response,
    ))
    payload = JwtService.decode_token(auth_token.token, auth_role="user")
    request = _request_with_cookie("__Host-kmvpy-user-session", auth_token.session_cookie_value)
    response = Response()

    renewed = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        response,
        auth_role="user",
        token=auth_token.token,
        payload=payload,
    ))

    assert renewed is None
    assert "x-auth-token" not in {key.lower() for key in response.headers.keys()}
    assert AuthSessionService._session_key("user", auth_token.sid) in fake_redis.values


def test_maybe_renew_rotates_secret_cookie_and_refreshes_idle_ttl() -> None:
    fake_redis = _configure_user_auth(access_hours=0.01, idle_hours=1.0, absolute_hours=8.0)
    issue_response = Response()
    auth_token = asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
        response=issue_response,
    ))
    session_key = AuthSessionService._session_key("user", auth_token.sid)
    before_payload = json.loads(fake_redis.values[session_key])
    payload = JwtService.decode_token(auth_token.token, auth_role="user")
    request = _request_with_cookie("__Host-kmvpy-user-session", auth_token.session_cookie_value)
    response = Response()

    renewed = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        response,
        auth_role="user",
        token=auth_token.token,
        payload=payload,
    ))

    assert renewed is not None
    assert renewed.token != auth_token.token
    assert response.headers["X-Auth-Token"] == renewed.token
    assert response.headers["X-Auth-Token-Type"] == "Bearer"
    assert response.headers["X-Auth-Expires-At"] == str(renewed.expires_at)
    assert response.headers["Cache-Control"] == "no-store"
    assert renewed.session_cookie_value != auth_token.session_cookie_value
    assert renewed.session_cookie_value in response.headers["set-cookie"]

    after_payload = json.loads(fake_redis.values[session_key])
    assert after_payload["session_secret_hash"] != before_payload["session_secret_hash"]
    assert after_payload["last_active_at"] >= before_payload["last_active_at"]
    assert after_payload["rotated_at"] >= before_payload["rotated_at"]
    assert fake_redis.expires[session_key] == 3600


def test_renew_does_not_extend_beyond_absolute_timeout() -> None:
    fake_redis = _configure_user_auth(access_hours=0.01, idle_hours=1.0, absolute_hours=8.0)
    auth_token = asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
    ))
    session_key = AuthSessionService._session_key("user", auth_token.sid)
    session_payload = json.loads(fake_redis.values[session_key])
    now = int(time.time())
    session_payload["absolute_expires_at"] = now + 30
    session_payload["idle_expires_at"] = now + 30
    fake_redis.values[session_key] = json.dumps(session_payload)

    request = _request_with_cookie("__Host-kmvpy-user-session", auth_token.session_cookie_value)
    response = Response()
    renewed = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        response,
        auth_role="user",
        token=auth_token.token,
        payload=JwtService.decode_token(auth_token.token, auth_role="user"),
    ))

    assert renewed is not None
    after_payload = json.loads(fake_redis.values[session_key])
    assert after_payload["idle_expires_at"] <= session_payload["absolute_expires_at"]
    assert fake_redis.expires[session_key] <= 30


def test_old_session_secret_replay_revokes_session_family() -> None:
    fake_redis = _configure_user_auth(access_hours=0.01)
    auth_token = asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
    ))
    request = _request_with_cookie("__Host-kmvpy-user-session", auth_token.session_cookie_value)
    first_response = Response()
    renewed = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        first_response,
        auth_role="user",
        token=auth_token.token,
        payload=JwtService.decode_token(auth_token.token, auth_role="user"),
    ))
    assert renewed is not None

    replay_request = _request_with_cookie("__Host-kmvpy-user-session", auth_token.session_cookie_value)
    replay_response = Response()
    with pytest.raises(HTTPException):
        asyncio.run(AuthSessionService.maybe_renew_access_token(
            replay_request,
            replay_response,
            auth_role="user",
            token=renewed.token,
            payload=JwtService.decode_token(renewed.token, auth_role="user"),
        ))

    assert AuthSessionService._session_key("user", auth_token.sid) not in fake_redis.values

    valid_cookie_request = _request_with_cookie("__Host-kmvpy-user-session", renewed.session_cookie_value)
    valid_cookie_response = Response()
    result = asyncio.run(AuthSessionService.maybe_renew_access_token(
        valid_cookie_request,
        valid_cookie_response,
        auth_role="user",
        token=renewed.token,
        payload=JwtService.decode_token(renewed.token, auth_role="user"),
    ))
    assert result is None


def test_logout_deletes_session_and_clears_cookie_but_access_jwt_remains_locally_valid() -> None:
    fake_redis = _configure_user_auth(access_hours=0.01)
    auth_token = asyncio.run(AuthSessionService.issue_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
    ))
    response = Response()

    asyncio.run(AuthSessionService.revoke_token(
        auth_token.token,
        auth_role="user",
        response=response,
    ))

    assert AuthSessionService._session_key("user", auth_token.sid) not in fake_redis.values
    assert "__Host-kmvpy-user-session=" in response.headers["set-cookie"]
    assert "Max-Age=0" in response.headers["set-cookie"]

    user_info = asyncio.run(AuthSessionService.verify_token(auth_token.token, auth_role="user"))
    assert user_info.kid == 1

    request = _request_with_cookie("__Host-kmvpy-user-session", auth_token.session_cookie_value)
    renew_response = Response()
    result = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        renew_response,
        auth_role="user",
        token=auth_token.token,
        payload=JwtService.decode_token(auth_token.token, auth_role="user"),
    ))
    assert result is None


def test_revoke_user_sessions_prevents_future_renewal() -> None:
    fake_redis = _configure_user_auth(access_hours=0.01)
    first = asyncio.run(AuthSessionService.issue_token(JwtUserInfo(kid=1, user_type=0), auth_role="user"))
    second = asyncio.run(AuthSessionService.issue_token(JwtUserInfo(kid=1, user_type=0), auth_role="user"))

    asyncio.run(AuthSessionService.revoke_user_sessions(auth_role="user", kid=1))

    assert AuthSessionService._session_key("user", first.sid) not in fake_redis.values
    assert AuthSessionService._session_key("user", second.sid) not in fake_redis.values

    request = _request_with_cookie("__Host-kmvpy-user-session", first.session_cookie_value)
    response = Response()
    result = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        response,
        auth_role="user",
        token=first.token,
        payload=JwtService.decode_token(first.token, auth_role="user"),
    ))
    assert result is None


def test_max_sessions_per_user_kicks_oldest_session() -> None:
    fake_redis = _configure_user_auth(max_sessions=1)
    first = asyncio.run(AuthSessionService.issue_token(JwtUserInfo(kid=1, user_type=0), auth_role="user"))
    second = asyncio.run(AuthSessionService.issue_token(JwtUserInfo(kid=1, user_type=0), auth_role="user"))

    assert AuthSessionService._session_key("user", first.sid) not in fake_redis.values
    assert AuthSessionService._session_key("user", second.sid) in fake_redis.values

    request = _request_with_cookie("__Host-kmvpy-user-session", first.session_cookie_value)
    response = Response()
    result = asyncio.run(AuthSessionService.maybe_renew_access_token(
        request,
        response,
        auth_role="user",
        token=first.token,
        payload=JwtService.decode_token(first.token, auth_role="user"),
    ))
    assert result is None
