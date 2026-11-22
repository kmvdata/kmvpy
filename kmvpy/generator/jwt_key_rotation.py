from __future__ import annotations

import contextlib
import os
import secrets
import shutil
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import yaml
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa

from kmvpy.common.conf import ASYMMETRIC_JWT_ALGORITHMS, BaseConfig


JWT_ROTATION_ROLES = ("user", "admin")
JWT_ROLE_DEFAULTS = {
    "user": {
        "audience": "kmvpy-user-api",
        "access_token_lifetime_hours": 0.25,
        "idle_timeout_hours": 24.0,
        "absolute_timeout_hours": 720.0,
        "max_sessions_per_user": None,
        "redis_db": 1,
    },
    "admin": {
        "audience": "kmvpy-admin-api",
        "access_token_lifetime_hours": 0.1667,
        "idle_timeout_hours": 1.0,
        "absolute_timeout_hours": 8.0,
        "max_sessions_per_user": 3,
        "redis_db": 10,
    },
}
LEGACY_JWT_FIELDS = {
    "private_key",
    "public_key",
    "key_id",
    "secret_key",
    "access_token_expire_hours",
}


@dataclass(frozen=True)
class JwtRoleRotationResult:
    role: str
    kid: str
    private_key_path: str
    public_key_path: str


@dataclass(frozen=True)
class JwtKeyRotationResult:
    config_path: Path
    backup_path: Path
    roles: tuple[JwtRoleRotationResult, ...]


def _load_yaml_config(config_path: Path) -> dict[str, Any]:
    if not config_path.is_file():
        raise FileNotFoundError(f"配置文件不存在: {config_path}")
    try:
        data = yaml.safe_load(config_path.read_text(encoding="utf-8")) or {}
    except yaml.YAMLError as exc:
        raise ValueError(f"YAML 解析失败: {config_path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ValueError("配置文件顶层必须是 YAML mapping")
    return data


def _require_mapping(value: Any, field_name: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{field_name} 必须是 YAML mapping")
    return value


def _ensure_mapping(parent: dict[str, Any], key: str, field_name: str) -> dict[str, Any]:
    value = parent.get(key)
    if value is None:
        value = {}
        parent[key] = value
    return _require_mapping(value, field_name)


def _public_keys_from_config(value: Any, field_name: str) -> list[dict[str, Any]]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ValueError(f"{field_name} 必须是列表")
    for index, item in enumerate(value):
        if not isinstance(item, dict):
            raise ValueError(f"{field_name}[{index}] 必须是 YAML mapping")
    return value


def _apply_role_defaults(role_config: dict[str, Any], role: str) -> dict[str, Any]:
    defaults = JWT_ROLE_DEFAULTS[role]
    jwt_config = _ensure_mapping(role_config, "jwt", f"auth_config.{role}.jwt")
    for legacy_field in LEGACY_JWT_FIELDS:
        jwt_config.pop(legacy_field, None)
    jwt_config.setdefault("algorithm", "RS256")
    algorithm = str(jwt_config.get("algorithm") or "").strip().upper()
    if algorithm not in ASYMMETRIC_JWT_ALGORITHMS:
        algorithm = "RS256"
    jwt_config["algorithm"] = algorithm
    jwt_config.setdefault("issuer", "kmvpy")
    jwt_config.setdefault("audience", defaults["audience"])
    jwt_config.setdefault("access_token_lifetime_hours", defaults["access_token_lifetime_hours"])

    session_config = _ensure_mapping(role_config, "session", f"auth_config.{role}.session")
    session_config.setdefault("idle_timeout_hours", defaults["idle_timeout_hours"])
    session_config.setdefault("absolute_timeout_hours", defaults["absolute_timeout_hours"])
    session_config.setdefault("max_sessions_per_user", defaults["max_sessions_per_user"])

    redis_config = _ensure_mapping(role_config, "redis", f"auth_config.{role}.redis")
    redis_config.setdefault("host", "localhost")
    redis_config.setdefault("port", 6379)
    redis_config.setdefault("db", defaults["redis_db"])
    redis_config.setdefault("decode_responses", True)
    return jwt_config


def _ensure_auth_config_defaults(data: dict[str, Any]) -> dict[str, Any]:
    auth_config = _ensure_mapping(data, "auth_config", "auth_config")
    for role in JWT_ROTATION_ROLES:
        role_config = _ensure_mapping(auth_config, role, f"auth_config.{role}")
        _apply_role_defaults(role_config, role)
    return auth_config


def _path_join_preserving_style(original_path: str, filename: str) -> str:
    normalized = str(original_path or "").strip()
    if not normalized:
        raise ValueError("JWT key path 不能为空")
    parent = Path(normalized).parent.as_posix()
    if parent in ("", "."):
        return f"./{filename}" if normalized.startswith("./") else filename
    if normalized.startswith("./") and not parent.startswith("./"):
        parent = f"./{parent}"
    return f"{parent.rstrip('/')}/{filename}"


def _path_for_write(path_text: str, base_dir: Path) -> Path:
    path = Path(path_text).expanduser()
    if path.is_absolute():
        return path
    return base_dir / path


def _public_key_path_for_rotation(
    *,
    role: str,
    jwt_config: dict[str, Any],
    public_keys: list[dict[str, Any]],
) -> str:
    active_kid = str(jwt_config.get("active_kid") or "").strip()
    if active_kid:
        for item in public_keys:
            if str(item.get("kid") or "").strip() == active_kid:
                public_key_path = str(item.get("public_key_path") or "").strip()
                if public_key_path:
                    return public_key_path
    for item in public_keys:
        public_key_path = str(item.get("public_key_path") or "").strip()
        if public_key_path:
            return public_key_path
    return f"./secrets/jwt-public-{role}-bootstrap.pem"


def _public_key_file_exists(public_key_entry: dict[str, Any], base_dir: Path) -> bool:
    public_key_path = str(public_key_entry.get("public_key_path") or "").strip()
    if not public_key_path:
        return False
    return _path_for_write(public_key_path, base_dir).is_file()


def _select_retained_public_keys(
    *,
    previous_public_keys: list[dict[str, Any]],
    previous_active_kid: str,
    base_dir: Path,
) -> list[dict[str, Any]]:
    existing_entries = [
        dict(entry)
        for entry in previous_public_keys
        if str(entry.get("kid") or "").strip() and _public_key_file_exists(entry, base_dir)
    ]
    if not existing_entries:
        return []

    for entry in existing_entries:
        if str(entry.get("kid") or "").strip() == previous_active_kid:
            return [entry]
    return [existing_entries[0]]


def _generate_kid(existing_kids: set[str]) -> str:
    for _ in range(32):
        kid = f"k-{secrets.token_hex(12)}"
        if kid not in existing_kids:
            existing_kids.add(kid)
            return kid
    raise RuntimeError("无法生成不重复的 JWT kid")


def _generate_key_pair(algorithm: str) -> tuple[bytes, bytes]:
    upper_algorithm = str(algorithm or "RS256").strip().upper()
    if upper_algorithm.startswith(("RS", "PS")):
        private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    elif upper_algorithm == "ES256":
        private_key = ec.generate_private_key(ec.SECP256R1())
    elif upper_algorithm == "ES384":
        private_key = ec.generate_private_key(ec.SECP384R1())
    elif upper_algorithm == "ES512":
        private_key = ec.generate_private_key(ec.SECP521R1())
    else:
        raise ValueError(f"rotate-jwt-keys 不支持 JWT algorithm={algorithm}")

    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    return private_pem, public_pem


def _write_new_key_file(path: Path, content: bytes, mode: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    fd = os.open(path, flags, mode)
    try:
        with os.fdopen(fd, "wb") as file:
            file.write(content)
    except Exception:
        with contextlib.suppress(OSError):
            path.unlink()
        raise
    os.chmod(path, mode)


def _backup_config(config_path: Path) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S")
    backup_path = config_path.with_name(f"{config_path.name}.bak-{timestamp}")
    counter = 1
    while backup_path.exists():
        backup_path = config_path.with_name(f"{config_path.name}.bak-{timestamp}-{counter}")
        counter += 1
    shutil.copy2(config_path, backup_path)
    return backup_path


def _validate_config_from_dir(data: dict[str, Any], config_dir: Path) -> None:
    previous_cwd = Path.cwd()
    try:
        os.chdir(config_dir)
        BaseConfig.model_validate(data)
    finally:
        os.chdir(previous_cwd)


def rotate_jwt_keys(config_path: str | Path) -> JwtKeyRotationResult:
    target_config_path = Path(config_path).expanduser()
    config_dir = target_config_path.resolve().parent
    data = _load_yaml_config(target_config_path)
    auth_config = _ensure_auth_config_defaults(data)

    existing_kids: set[str] = set()
    role_inputs: list[tuple[str, dict[str, Any], list[dict[str, Any]], str, str]] = []
    for role in JWT_ROTATION_ROLES:
        role_config = _require_mapping(auth_config.get(role), f"auth_config.{role}")
        jwt_config = _apply_role_defaults(role_config, role)
        private_key_path = str(jwt_config.get("private_key_path") or "").strip()
        if not private_key_path:
            private_key_path = f"./secrets/jwt-private-{role}-bootstrap.pem"
        public_keys = _public_keys_from_config(jwt_config.get("public_keys"), f"auth_config.{role}.jwt.public_keys")
        public_key_path = _public_key_path_for_rotation(role=role, jwt_config=jwt_config, public_keys=public_keys)
        for item in public_keys:
            kid = str(item.get("kid") or "").strip()
            if kid:
                existing_kids.add(kid)
        role_inputs.append((role, jwt_config, public_keys, private_key_path, public_key_path))

    role_results: list[JwtRoleRotationResult] = []
    generated_files: list[Path] = []
    try:
        for role, jwt_config, public_keys, private_key_path, public_key_path in role_inputs:
            previous_active_kid = str(jwt_config.get("active_kid") or "").strip()
            retained_public_keys = _select_retained_public_keys(
                previous_public_keys=public_keys,
                previous_active_kid=previous_active_kid,
                base_dir=config_dir,
            )
            kid = _generate_kid(existing_kids)
            new_private_key_path = _path_join_preserving_style(
                private_key_path,
                f"jwt-private-{role}-{kid}.pem",
            )
            new_public_key_path = _path_join_preserving_style(
                public_key_path,
                f"jwt-public-{role}-{kid}.pem",
            )

            private_pem, public_pem = _generate_key_pair(str(jwt_config.get("algorithm") or "RS256"))
            private_path = _path_for_write(new_private_key_path, config_dir)
            public_path = _path_for_write(new_public_key_path, config_dir)
            _write_new_key_file(private_path, private_pem, 0o400)
            generated_files.append(private_path)
            _write_new_key_file(public_path, public_pem, 0o444)
            generated_files.append(public_path)

            jwt_config["active_kid"] = kid
            jwt_config["private_key_path"] = new_private_key_path
            jwt_config["public_keys"] = [{
                "kid": kid,
                "public_key_path": new_public_key_path,
            }, *retained_public_keys]
            role_results.append(JwtRoleRotationResult(
                role=role,
                kid=kid,
                private_key_path=new_private_key_path,
                public_key_path=new_public_key_path,
            ))

        _validate_config_from_dir(data, config_dir)
        backup_path = _backup_config(target_config_path)
        serialized = yaml.safe_dump(data, allow_unicode=True, sort_keys=False)
        temp_path = target_config_path.with_name(f"{target_config_path.name}.tmp")
        temp_path.write_text(serialized, encoding="utf-8")
        os.replace(temp_path, target_config_path)
    except Exception:
        for path in reversed(generated_files):
            try:
                path.unlink()
            except OSError:
                pass
        raise

    return JwtKeyRotationResult(
        config_path=target_config_path,
        backup_path=backup_path,
        roles=tuple(role_results),
    )
