import datetime
import json
import secrets
from typing import Any, Mapping, Optional

import jwt
from fastapi import HTTPException, status
from jwt.algorithms import ECAlgorithm, RSAAlgorithm

from kmvpy.common.conf import ASYMMETRIC_JWT_ALGORITHMS, JwtConfig
from kmvpy.common.kmv import kosmos
from kmvpy.common.tool.logger import logger


ACCESS_JWT_TYP = "at+jwt"
ACCESS_JWT_ALLOWED_TYP = frozenset({"at+jwt", "application/at+jwt"})


class JwtUserInfo:
    kid: int
    user_type: int
    device_id: str
    device_name: str
    platform: str
    sid: str
    jti: str
    auth_role: str
    token_kid: str
    issued_at: int
    expires_at: int

    def __init__(
        self,
        kid: int,
        user_type: int,
        device_id: str = "",
        device_name: str = "",
        platform: str = "",
        sid: str = "",
        jti: str = "",
        auth_role: str = "",
        token_kid: str = "",
        issued_at: int = 0,
        expires_at: int = 0,
    ):
        self.kid = kid
        self.user_type = user_type
        self.device_id = device_id
        self.device_name = device_name
        self.platform = platform
        self.sid = sid
        self.jti = jti
        self.auth_role = auth_role
        self.token_kid = token_kid
        self.issued_at = issued_at
        self.expires_at = expires_at


class JwtService:
    """短寿命 OAuth access JWT 服务；资源服务只需本地验签。"""

    def __init__(
        self,
        jwt_config: Optional[JwtConfig] = None,
        auth_role: Optional[str] = None,
    ) -> None:
        self.jwt_config = jwt_config
        self.auth_role = auth_role

    @staticmethod
    def _raise_unauthorized(detail: str = "Token 无效，请重新登录") -> None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=detail,
            headers={"WWW-Authenticate": "Bearer"},
        )

    @staticmethod
    def _get_jwt_config(
        user_type: Optional[int] = None,
        auth_role: Optional[str] = None,
        jwt_config: Optional[JwtConfig] = None,
    ) -> JwtConfig:
        if jwt_config is not None:
            return jwt_config

        if auth_role is None and user_type is not None:
            auth_role = "admin" if int(user_type) == 100 else "user"

        auth_config = getattr(getattr(kosmos, "config", None), "auth_config", None)
        if auth_config is not None and auth_role is not None:
            scoped_auth_config = getattr(auth_config, auth_role, None)
            scoped_jwt_config = getattr(scoped_auth_config, "jwt", None)
            if scoped_jwt_config is not None:
                return scoped_jwt_config

        JwtService._raise_unauthorized("鉴权失败：认证配置缺失")

    @staticmethod
    def _infer_auth_role(user_type: int, auth_role: Optional[str]) -> str:
        if auth_role:
            return auth_role
        return "admin" if int(user_type) == 100 else "user"

    @staticmethod
    def _now_ts() -> int:
        return int(datetime.datetime.now(datetime.timezone.utc).timestamp())

    @staticmethod
    def _validate_header(token: str, jwt_config: JwtConfig) -> dict[str, Any]:
        try:
            header = jwt.get_unverified_header(token)
        except jwt.InvalidTokenError:
            JwtService._raise_unauthorized()

        typ = str(header.get("typ") or "").lower()
        alg = str(header.get("alg") or "")
        kid = str(header.get("kid") or "")
        expected_alg = jwt_config.algorithm
        if typ not in ACCESS_JWT_ALLOWED_TYP:
            JwtService._raise_unauthorized("Token 类型错误，请重新登录")
        if alg != expected_alg or alg not in ASYMMETRIC_JWT_ALGORITHMS:
            JwtService._raise_unauthorized("Token 签名算法不被允许")
        if not kid:
            JwtService._raise_unauthorized("Token kid 缺失")
        if jwt_config.get_public_key(kid) is None:
            JwtService._raise_unauthorized("Token kid 未配置")
        return header

    @staticmethod
    def encode_token(
        user_info: JwtUserInfo,
        expire_hours: Optional[float] = None,
        auth_role: Optional[str] = None,
        jwt_config: Optional[JwtConfig] = None,
        extra_claims: Optional[Mapping[str, Any]] = None,
    ) -> str:
        jwt_config = JwtService._get_jwt_config(
            user_type=user_info.user_type,
            auth_role=auth_role,
            jwt_config=jwt_config,
        )
        role = JwtService._infer_auth_role(user_info.user_type, auth_role)
        extra = dict(extra_claims or {})
        sid = str(extra.pop("sid", "") or user_info.sid or secrets.token_urlsafe(32))
        jti = str(extra.pop("jti", "") or user_info.jti or secrets.token_urlsafe(32))
        role = str(extra.pop("role", "") or extra.pop("auth_role", "") or role)

        lifetime_hours = (
            float(expire_hours)
            if expire_hours is not None
            else float(jwt_config.access_token_lifetime_hours)
        )
        now = JwtService._now_ts()
        expires_at = now + max(1, int(round(lifetime_hours * 3600)))

        payload: dict[str, Any] = {
            "iss": jwt_config.issuer,
            "aud": jwt_config.audience,
            "sub": str(user_info.kid),
            "exp": expires_at,
            "iat": now,
            "jti": jti,
            "role": role,
            "auth_role": role,
            "token_type": "access",
            "sid": sid,
            "user_kid": int(user_info.kid),
            "user_type": int(user_info.user_type),
            "device_id": user_info.device_id,
            "device_name": user_info.device_name,
            "platform": user_info.platform,
        }
        conflicting_claims = set(payload).intersection(extra)
        if conflicting_claims:
            raise ValueError(f"extra_claims 不能覆盖 JWT 核心字段: {sorted(conflicting_claims)}")
        payload.update(extra)

        headers = {
            "typ": ACCESS_JWT_TYP,
            "kid": jwt_config.active_kid,
        }
        token = jwt.encode(
            payload,
            jwt_config.get_active_private_key(),
            algorithm=jwt_config.algorithm,
            headers=headers,
        )
        logger.info(
            "JWT access token 已签发: user_kid=%s, user_type=%s, auth_role=%s, kid=%s, expires_at=%s",
            user_info.kid,
            user_info.user_type,
            role,
            jwt_config.active_kid,
            expires_at,
        )
        return token

    @staticmethod
    def decode_token(
        token: str,
        auth_role: Optional[str] = None,
        jwt_config: Optional[JwtConfig] = None,
        *,
        verify_exp: bool = True,
    ) -> dict[str, Any]:
        jwt_config = JwtService._get_jwt_config(
            auth_role=auth_role,
            jwt_config=jwt_config,
        )
        header = JwtService._validate_header(token, jwt_config)
        token_kid = str(header.get("kid") or "")

        try:
            payload = jwt.decode(
                token,
                jwt_config.require_public_key(token_kid),
                algorithms=[jwt_config.algorithm],
                issuer=jwt_config.issuer,
                audience=jwt_config.audience,
                options={
                    "require": ["iss", "aud", "sub", "exp", "iat", "jti"],
                    "verify_signature": True,
                    "verify_exp": verify_exp,
                    "verify_iat": True,
                    "verify_iss": True,
                    "verify_aud": True,
                },
            )
        except jwt.ExpiredSignatureError:
            logger.warning("JWT access token 已过期")
            JwtService._raise_unauthorized("Token 已过期，请重新登录")
        except jwt.InvalidTokenError as exc:
            logger.warning("JWT access token 校验失败: %s", exc)
            JwtService._raise_unauthorized()
        except Exception as exc:
            logger.warning("JWT access token 解码异常: %s", exc)
            JwtService._raise_unauthorized()

        payload["kid"] = token_kid
        JwtService._validate_access_claims(payload, auth_role=auth_role)
        return payload

    @staticmethod
    def _validate_access_claims(payload: Mapping[str, Any], auth_role: Optional[str]) -> None:
        if payload.get("token_type") != "access":
            JwtService._raise_unauthorized("Token 类型错误，请重新登录")
        if not payload.get("sid") or not payload.get("jti"):
            JwtService._raise_unauthorized("Token 会话标识缺失，请重新登录")
        if payload.get("user_kid") is None or payload.get("user_type") is None:
            JwtService._raise_unauthorized("Token 用户信息缺失，请重新登录")
        if auth_role is not None:
            role = payload.get("role") or payload.get("auth_role")
            if role != auth_role:
                JwtService._raise_unauthorized("Token 角色不匹配，请重新登录")
        iat = int(payload.get("iat") or 0)
        if iat > JwtService._now_ts() + 30:
            JwtService._raise_unauthorized("Token 签发时间无效，请重新登录")

    @staticmethod
    def decode_token_without_exp(
        token: str,
        auth_role: Optional[str] = None,
        jwt_config: Optional[JwtConfig] = None,
    ) -> dict[str, Any]:
        return JwtService.decode_token(
            token,
            auth_role=auth_role,
            jwt_config=jwt_config,
            verify_exp=False,
        )

    @staticmethod
    def extract_token_from_header(authorization_header: str) -> str:
        if not authorization_header:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="未登录，请先登录",
            )

        if not authorization_header.startswith("Bearer "):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Authorization header 格式错误，应为 'Bearer <token>'",
            )

        token = authorization_header[7:].strip()
        if not token:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token 不能为空",
            )
        return token

    @staticmethod
    def verify_token(token: str, *, auth_role: Optional[str] = None) -> dict[str, Any]:
        return JwtService.decode_token(token, auth_role=auth_role)

    @staticmethod
    def get_username_from_token(token: str) -> str:
        payload = JwtService.decode_token(token)
        username = payload.get("sub")
        if not username:
            logger.warning("JWT access token 中缺少 sub 字段")
            JwtService._raise_unauthorized("Token 格式错误：缺少用户信息")
        return str(username)

    @staticmethod
    def payload_to_user_info(payload: Mapping[str, Any]) -> JwtUserInfo:
        try:
            return JwtUserInfo(
                kid=int(payload["user_kid"]),
                user_type=int(payload["user_type"]),
                device_id=str(payload.get("device_id") or ""),
                device_name=str(payload.get("device_name") or ""),
                platform=str(payload.get("platform") or ""),
                sid=str(payload.get("sid") or ""),
                jti=str(payload.get("jti") or ""),
                auth_role=str(payload.get("role") or payload.get("auth_role") or ""),
                token_kid=str(payload.get("kid") or ""),
                issued_at=int(payload.get("iat") or 0),
                expires_at=int(payload.get("exp") or 0),
            )
        except (KeyError, TypeError, ValueError):
            JwtService._raise_unauthorized("Token 格式错误：用户信息字段非法")

    @staticmethod
    def get_user_info_from_token(token: str, *, auth_role: Optional[str] = None) -> JwtUserInfo:
        payload = JwtService.decode_token(token, auth_role=auth_role)
        return JwtService.payload_to_user_info(payload)

    @staticmethod
    def get_user_info_from_authorization_header(authorization_header: str) -> JwtUserInfo:
        token = JwtService.extract_token_from_header(authorization_header)
        user_info = JwtService.get_user_info_from_token(token)
        logger.info(
            "从 Authorization header 中获取用户信息成功: user_kid=%s, user_type=%s, platform=%s",
            user_info.kid,
            user_info.user_type,
            user_info.platform,
        )
        return user_info

    @staticmethod
    def get_username_from_authorization_header(authorization_header: str) -> str:
        token = JwtService.extract_token_from_header(authorization_header)
        username = JwtService.get_username_from_token(token)
        logger.info("从 Authorization header 中获取用户名成功: username=%s", username)
        return username

    @staticmethod
    def is_token_expired(token: str) -> bool:
        try:
            payload = jwt.decode(
                token,
                options={"verify_signature": False, "verify_exp": False},
            )
            exp = payload.get("exp")
            if exp is None:
                return True
            return float(exp) < datetime.datetime.now(datetime.timezone.utc).timestamp()
        except Exception:
            return True

    @staticmethod
    def get_public_jwks(
        *,
        auth_role: Optional[str] = None,
        jwt_config: Optional[JwtConfig] = None,
    ) -> dict[str, list[dict[str, Any]]]:
        jwt_config = JwtService._get_jwt_config(auth_role=auth_role, jwt_config=jwt_config)
        keys: list[dict[str, Any]] = []
        for kid, public_key in jwt_config.iter_public_keys():
            if jwt_config.algorithm.startswith(("RS", "PS")):
                jwk = json.loads(RSAAlgorithm.to_jwk(public_key))
            elif jwt_config.algorithm.startswith("ES"):
                jwk = json.loads(ECAlgorithm.to_jwk(public_key))
            else:
                raise ValueError("仅支持非对称 JWT 公钥导出为 JWKS")
            jwk.update({
                "kid": kid,
                "use": "sig",
                "alg": jwt_config.algorithm,
            })
            keys.append(jwk)
        return {"keys": keys}

    def create_access_token(
        self,
        data: Mapping[str, Any],
        *,
        user_info: Optional[JwtUserInfo] = None,
    ) -> str:
        if user_info is None:
            user_info = JwtUserInfo(
                kid=int(data.get("user_kid") or data.get("kid") or data.get("sub")),
                user_type=int(data.get("user_type", 0)),
            )
        return self.encode_token(
            user_info,
            auth_role=self.auth_role,
            jwt_config=self.jwt_config,
            extra_claims={k: v for k, v in data.items() if k not in {"kid", "sub", "user_kid", "user_type"}},
        )

    def parse_token_data(self, token: str) -> dict[str, Any]:
        return self.decode_token(token, auth_role=self.auth_role, jwt_config=self.jwt_config)
