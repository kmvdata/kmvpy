import asyncio
import time

import jwt
import pytest
from fastapi import HTTPException

from kmvpy.common.conf import JwtConfig
from kmvpy.common.kmv import kosmos
from kmvpy.core.main.service.auth_session_service import AuthSessionService
from kmvpy.core.main.service.jwt_service import JwtService, JwtUserInfo

from .auth_test_utils import build_auth_config_dict, build_base_config, generate_rsa_key_pair


@pytest.fixture(autouse=True)
def reset_kosmos_config():
    had_config = "config" in vars(kosmos)
    previous_config = getattr(kosmos, "config", None)
    yield
    if had_config:
        kosmos.config = previous_config
    elif "config" in vars(kosmos):
        delattr(kosmos, "config")


def _issue_user_token() -> tuple[str, dict, JwtConfig]:
    kosmos.config = build_base_config()
    jwt_config = kosmos.config.auth_config.user.jwt
    token = JwtService.encode_token(
        JwtUserInfo(kid=123, user_type=0, device_id="dev-1", device_name="Chrome", platform="web"),
        auth_role="user",
        extra_claims={"sid": "sid-1", "jti": "jti-1", "role": "user"},
    )
    payload = jwt.decode(token, options={"verify_signature": False, "verify_exp": False})
    return token, payload, jwt_config


def test_access_jwt_header_and_claims_are_rfc9068_style() -> None:
    token, payload, jwt_config = _issue_user_token()
    header = jwt.get_unverified_header(token)

    assert header["typ"] == "at+jwt"
    assert header["alg"] == "RS256"
    assert header["kid"] == jwt_config.active_kid
    assert payload["iss"] == "kmvpy"
    assert payload["aud"] == "kmvpy-user-api"
    assert payload["sub"] == "123"
    assert payload["token_type"] == "access"
    assert payload["role"] == "user"
    assert payload["sid"] == "sid-1"
    assert payload["jti"] == "jti-1"
    assert payload["user_kid"] == 123
    assert payload["user_type"] == 0
    assert payload["device_id"] == "dev-1"
    assert payload["device_name"] == "Chrome"
    assert payload["platform"] == "web"
    assert payload["exp"] > payload["iat"] >= int(time.time()) - 5


def test_local_verification_does_not_require_redis(monkeypatch) -> None:
    token, _payload, _jwt_config = _issue_user_token()

    def _redis_must_not_be_called(cls, auth_role):
        raise AssertionError("JWT local verification must not read Redis")

    monkeypatch.setattr(AuthSessionService, "_redis", classmethod(_redis_must_not_be_called))

    user_info = asyncio.run(AuthSessionService.verify_token(token, auth_role="user"))
    assert user_info.kid == 123
    assert user_info.user_type == 0


def test_jwt_verify_rejects_wrong_audience_and_issuer() -> None:
    token, _payload, jwt_config = _issue_user_token()

    wrong_audience = jwt_config.model_copy(update={"audience": "wrong-aud"})
    with pytest.raises(HTTPException):
        JwtService.decode_token(token, auth_role="user", jwt_config=wrong_audience)

    wrong_issuer = jwt_config.model_copy(update={"issuer": "wrong-issuer"})
    with pytest.raises(HTTPException):
        JwtService.decode_token(token, auth_role="user", jwt_config=wrong_issuer)


def test_jwt_verify_rejects_wrong_typ_alg_token_type_and_role() -> None:
    token, payload, jwt_config = _issue_user_token()

    wrong_typ = jwt.encode(
        payload,
        jwt_config.get_active_private_key(),
        algorithm="RS256",
        headers={"typ": "JWT", "kid": jwt_config.active_kid},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(wrong_typ, auth_role="user")

    wrong_alg = jwt.encode(
        payload,
        "secret",
        algorithm="HS256",
        headers={"typ": "at+jwt", "kid": jwt_config.active_kid},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(wrong_alg, auth_role="user")

    wrong_type_payload = dict(payload)
    wrong_type_payload["token_type"] = "refresh"
    wrong_token_type = jwt.encode(
        wrong_type_payload,
        jwt_config.get_active_private_key(),
        algorithm="RS256",
        headers={"typ": "at+jwt", "kid": jwt_config.active_kid},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(wrong_token_type, auth_role="user")

    wrong_role_payload = dict(payload)
    wrong_role_payload["role"] = "admin"
    wrong_role_payload["auth_role"] = "admin"
    wrong_role = jwt.encode(
        wrong_role_payload,
        jwt_config.get_active_private_key(),
        algorithm="RS256",
        headers={"typ": "at+jwt", "kid": jwt_config.active_kid},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(wrong_role, auth_role="user")


def test_jwt_verify_rejects_wrong_kid_and_missing_sid_jti() -> None:
    _token, payload, jwt_config = _issue_user_token()

    wrong_kid = jwt.encode(
        payload,
        jwt_config.get_active_private_key(),
        algorithm="RS256",
        headers={"typ": "at+jwt", "kid": "wrong-kid"},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(wrong_kid, auth_role="user")

    missing_kid = jwt.encode(
        payload,
        jwt_config.get_active_private_key(),
        algorithm="RS256",
        headers={"typ": "at+jwt"},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(missing_kid, auth_role="user")

    missing_sid_jti_payload = dict(payload)
    missing_sid_jti_payload.pop("sid")
    missing_sid_jti_payload.pop("jti")
    missing_sid_jti = jwt.encode(
        missing_sid_jti_payload,
        jwt_config.get_active_private_key(),
        algorithm="RS256",
        headers={"typ": "at+jwt", "kid": jwt_config.active_kid},
    )
    with pytest.raises(HTTPException):
        JwtService.decode_token(missing_sid_jti, auth_role="user")


def test_jwks_reserved_interface_exports_current_public_key() -> None:
    token, _payload, jwt_config = _issue_user_token()

    jwks = JwtService.get_public_jwks(auth_role="user")

    assert jwks["keys"][0]["kid"] == jwt_config.active_kid
    assert jwks["keys"][0]["alg"] == "RS256"
    assert jwks["keys"][0]["use"] == "sig"
    assert jwt.get_unverified_header(token)["kid"] == jwks["keys"][0]["kid"]


def test_multiple_public_keys_can_verify_old_kid_token() -> None:
    active_key_pair = generate_rsa_key_pair()
    old_key_pair = generate_rsa_key_pair()
    auth_config = build_auth_config_dict(
        user_keys=active_key_pair,
        user_kid="user-2026-06",
    )
    auth_config["user"]["jwt"]["public_keys"].append({
        "kid": "user-2026-03",
        "public_key_path": old_key_pair.public_key_path,
    })
    kosmos.config = build_base_config(auth_config=auth_config)
    jwt_config = kosmos.config.auth_config.user.jwt

    active_token = JwtService.encode_token(
        JwtUserInfo(kid=123, user_type=0),
        auth_role="user",
        extra_claims={"sid": "sid-rotation", "jti": "jti-active", "role": "user"},
    )
    active_payload = jwt.decode(active_token, options={"verify_signature": False, "verify_exp": False})
    old_payload = dict(active_payload)
    old_payload["jti"] = "jti-old"
    old_token = jwt.encode(
        old_payload,
        old_key_pair.private_key,
        algorithm="RS256",
        headers={"typ": "at+jwt", "kid": "user-2026-03"},
    )

    assert jwt.get_unverified_header(active_token)["kid"] == jwt_config.active_kid
    assert JwtService.decode_token(active_token, auth_role="user")["kid"] == "user-2026-06"
    decoded_old = JwtService.decode_token(old_token, auth_role="user")
    assert decoded_old["kid"] == "user-2026-03"
    assert decoded_old["jti"] == "jti-old"


def test_direct_jwt_config_requires_path_based_asymmetric_keys() -> None:
    key_pair = generate_rsa_key_pair()
    config = JwtConfig(
        algorithm="RS256",
        active_kid="direct-key",
        private_key_path=key_pair.private_key_path,
        public_keys=[
            {
                "kid": "direct-key",
                "public_key_path": key_pair.public_key_path,
            }
        ],
        issuer="kmvpy",
        audience="direct-audience",
        access_token_lifetime_hours=0.01,
    )

    token = JwtService.encode_token(
        JwtUserInfo(kid=1, user_type=0),
        auth_role="user",
        jwt_config=config,
        extra_claims={"sid": "sid", "jti": "jti", "role": "user"},
    )

    assert JwtService.decode_token(token, auth_role="user", jwt_config=config)["user_kid"] == 1
