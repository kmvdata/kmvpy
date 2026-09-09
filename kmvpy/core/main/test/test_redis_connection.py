import asyncio
from unittest.mock import AsyncMock, Mock

import pytest
import yaml

from kmvpy.common.conf import BaseConfig
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.kmv import kosmos
from kmvpy.core.main.service.auth_session_service import AuthSessionService

from .auth_test_utils import build_auth_config_dict


@pytest.mark.parametrize("config_location", ["default_storage", "legacy", "user", "admin"])
@pytest.mark.parametrize(
    ("credentials_yaml", "expected_auth"),
    [
        pytest.param(
            'username: "app:user@/中文"\npassword: "p@ss:/% word"',
            ("AUTH", "app:user@/中文", "p@ss:/% word"),
            id="acl",
        ),
        pytest.param('password: "legacy-secret"', ("AUTH", "legacy-secret"), id="password-only"),
        pytest.param(
            'username: null\npassword: "legacy-secret"',
            ("AUTH", "legacy-secret"),
            id="null-username",
        ),
        pytest.param(
            'username: ""\npassword: "legacy-secret"',
            ("AUTH", "legacy-secret"),
            id="empty-username",
        ),
        pytest.param('username: "app_user"', ("AUTH", "app_user", ""), id="username-only"),
        pytest.param("{}", None, id="no-auth"),
        pytest.param('password: ""', None, id="empty-password"),
    ],
)
def test_redis_connections_authenticate_from_config(
    monkeypatch, config_location, credentials_yaml, expected_auth
) -> None:
    redis_config = {
        "host": "redis.example.test",
        "port": 6380,
        "db": 3,
        "decode_responses": False,
        **yaml.safe_load(credentials_yaml),
    }
    config_data = {
        "general": {"debug": True, "env": "test"},
        "logging": {"level": "INFO"},
    }
    if config_location == "default_storage":
        config_data["default_storage"] = {
            "database": {"url": "sqlite+aiosqlite:///:memory:"},
            "redis": redis_config,
        }
    elif config_location == "legacy":
        config_data["redis"] = redis_config
    else:
        config_data["auth_config"] = build_auth_config_dict()
        config_data["auth_config"][config_location]["redis"] = redis_config

    config = BaseConfig.model_validate(config_data)
    if config_location in {"default_storage", "legacy"}:
        storage = KOrmStorage(redis_config=config.get_default_storage_redis_config())
        client = storage.init_redis_client()
        assert storage.init_redis_client() is client
    else:
        monkeypatch.setattr(kosmos, "config", config, raising=False)
        monkeypatch.setattr(AuthSessionService, "_redis_clients", {})
        client = AuthSessionService._redis(config_location)
        assert AuthSessionService._redis(config_location) is client

    connection = client.connection_pool.make_connection()
    assert connection.host == "redis.example.test"
    assert connection.port == 6380
    assert connection.db == 3
    assert connection.encoder.decode_responses is False

    # Run redis-py's real authentication handshake with only the transport mocked.
    # RESP2 makes the distinction between AUTH password and AUTH username password explicit.
    connection.protocol = 2
    monkeypatch.setattr(connection, "_parser", Mock())
    send_command = AsyncMock()
    monkeypatch.setattr(type(connection), "send_command", send_command)
    monkeypatch.setattr(type(connection), "read_response", AsyncMock(return_value=b"OK"))

    async def authenticate() -> None:
        try:
            await connection.on_connect_check_health()
        finally:
            await client.aclose()

    asyncio.run(authenticate())

    auth_commands = [call.args for call in send_command.await_args_list if call.args[0] == "AUTH"]
    assert auth_commands == ([expected_auth] if expected_auth else [])
