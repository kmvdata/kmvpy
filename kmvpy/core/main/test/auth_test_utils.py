from __future__ import annotations

import atexit
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa

from kmvpy.common.conf import BaseConfig


@dataclass(frozen=True)
class TestKeyPair:
    private_key: str
    public_key: str
    private_key_path: str
    public_key_path: str


_TEST_KEY_DIRS: list[Path] = []


def _cleanup_test_key_dirs() -> None:
    for key_dir in _TEST_KEY_DIRS:
        shutil.rmtree(key_dir, ignore_errors=True)


atexit.register(_cleanup_test_key_dirs)


def _write_key_pair_files(private_pem: str, public_pem: str) -> tuple[str, str]:
    key_dir = Path(tempfile.mkdtemp(prefix="kmvpy-jwt-test-"))
    _TEST_KEY_DIRS.append(key_dir)
    private_key_path = key_dir / "private.pem"
    public_key_path = key_dir / "public.pem"
    private_key_path.write_text(private_pem, encoding="utf-8")
    public_key_path.write_text(public_pem, encoding="utf-8")
    private_key_path.chmod(0o400)
    public_key_path.chmod(0o444)
    return str(private_key_path), str(public_key_path)


def generate_rsa_key_pair() -> TestKeyPair:
    private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("utf-8")
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    ).decode("utf-8")
    private_key_path, public_key_path = _write_key_pair_files(private_pem, public_pem)
    return TestKeyPair(
        private_key=private_pem,
        public_key=public_pem,
        private_key_path=private_key_path,
        public_key_path=public_key_path,
    )


def build_auth_config_dict(
    *,
    user_keys: TestKeyPair | None = None,
    admin_keys: TestKeyPair | None = None,
    user_access_hours: float = 0.25,
    admin_access_hours: float = 0.1667,
    user_idle_hours: float = 24.0,
    admin_idle_hours: float = 1.0,
    user_absolute_hours: float = 720.0,
    admin_absolute_hours: float = 8.0,
    user_max_sessions: int | None = None,
    admin_max_sessions: int | None = 3,
    user_algorithm: str = "RS256",
    admin_algorithm: str = "RS256",
    user_kid: str = "user-key-1",
    admin_kid: str = "admin-key-1",
    include_user_redis: bool = True,
    include_admin_redis: bool = True,
) -> dict[str, Any]:
    user_keys = user_keys or generate_rsa_key_pair()
    admin_keys = admin_keys or generate_rsa_key_pair()
    user: dict[str, Any] = {
        "jwt": {
            "algorithm": user_algorithm,
            "active_kid": user_kid,
            "private_key_path": user_keys.private_key_path,
            "public_keys": [
                {
                    "kid": user_kid,
                    "public_key_path": user_keys.public_key_path,
                }
            ],
            "issuer": "kmvpy",
            "audience": "kmvpy-user-api",
            "access_token_lifetime_hours": user_access_hours,
        },
        "session": {
            "idle_timeout_hours": user_idle_hours,
            "absolute_timeout_hours": user_absolute_hours,
            "max_sessions_per_user": user_max_sessions,
        },
    }
    admin: dict[str, Any] = {
        "jwt": {
            "algorithm": admin_algorithm,
            "active_kid": admin_kid,
            "private_key_path": admin_keys.private_key_path,
            "public_keys": [
                {
                    "kid": admin_kid,
                    "public_key_path": admin_keys.public_key_path,
                }
            ],
            "issuer": "kmvpy",
            "audience": "kmvpy-admin-api",
            "access_token_lifetime_hours": admin_access_hours,
        },
        "session": {
            "idle_timeout_hours": admin_idle_hours,
            "absolute_timeout_hours": admin_absolute_hours,
            "max_sessions_per_user": admin_max_sessions,
        },
    }
    if include_user_redis:
        user["redis"] = {"host": "localhost", "port": 6379, "db": 1, "decode_responses": True}
    if include_admin_redis:
        admin["redis"] = {"host": "localhost", "port": 6379, "db": 10, "decode_responses": True}
    return {"user": user, "admin": admin}


def build_base_config(
    *,
    auth_config: dict[str, Any] | None = None,
    env: str = "test",
    debug: bool = True,
) -> BaseConfig:
    return BaseConfig.model_validate({
        "general": {"debug": debug, "env": env, "timezone": "UTC"},
        "logging": {"level": "INFO"},
        "auth_config": auth_config or build_auth_config_dict(),
    })


class FakeRedis:
    def __init__(self) -> None:
        self.values: dict[str, str] = {}
        self.expires: dict[str, int] = {}
        self.sets: dict[str, set[str]] = {}
        self.zsets: dict[str, dict[str, float]] = {}

    async def set(self, key: str, value: str, ex: int | None = None):
        self.values[key] = value
        if ex is not None:
            self.expires[key] = int(ex)
        return True

    async def get(self, key: str):
        return self.values.get(key)

    async def delete(self, *keys: str):
        deleted = 0
        for key in keys:
            if key in self.values or key in self.sets or key in self.zsets:
                deleted += 1
            self.values.pop(key, None)
            self.expires.pop(key, None)
            self.sets.pop(key, None)
            self.zsets.pop(key, None)
        return deleted

    async def exists(self, key: str):
        return int(key in self.values or key in self.sets or key in self.zsets)

    async def sadd(self, key: str, *values: str):
        target = self.sets.setdefault(key, set())
        before = len(target)
        target.update(str(value) for value in values)
        return len(target) - before

    async def smembers(self, key: str):
        return set(self.sets.get(key, set()))

    async def srem(self, key: str, *values: str):
        target = self.sets.setdefault(key, set())
        removed = 0
        for value in values:
            if str(value) in target:
                target.remove(str(value))
                removed += 1
        return removed

    async def expire(self, key: str, seconds: int):
        self.expires[key] = int(seconds)
        return True

    async def zadd(self, key: str, mapping: dict[str, float]):
        target = self.zsets.setdefault(key, {})
        for member, score in mapping.items():
            target[str(member)] = float(score)
        return len(mapping)

    async def zcard(self, key: str):
        return len(self.zsets.get(key, {}))

    async def zrange(self, key: str, start: int, end: int):
        items = sorted(self.zsets.get(key, {}).items(), key=lambda item: (item[1], item[0]))
        if end == -1:
            sliced = items[start:]
        else:
            sliced = items[start:end + 1]
        return [member for member, _score in sliced]

    async def zrem(self, key: str, *members: str):
        target = self.zsets.setdefault(key, {})
        removed = 0
        for member in members:
            if str(member) in target:
                target.pop(str(member), None)
                removed += 1
        return removed
