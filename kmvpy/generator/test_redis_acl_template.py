import asyncio
import importlib
import sys
from types import SimpleNamespace

import pytest
from redis.asyncio.connection import parse_url

from kmvpy.common.conf import RedisConfig
from kmvpy.generator.project_generator import create_project


@pytest.fixture(scope="module")
def socket_service(tmp_path_factory):
    project_name = "redis_acl_test_project"
    project_root = create_project(project_name, tmp_path_factory.mktemp("redis_acl"))
    source_root = str(project_root / f"{project_name}_py")
    sys.path.insert(0, source_root)
    try:
        module = importlib.import_module(f"{project_name}.core.main.service.user.socket")
        yield module.UserSocketService
    finally:
        sys.path.remove(source_root)
        for name in list(sys.modules):
            if name == project_name or name.startswith(f"{project_name}."):
                del sys.modules[name]


@pytest.mark.parametrize(
    ("credentials", "expected_url"),
    [
        pytest.param(
            {"username": "app:user@/中文", "password": "p@ss:/% word"},
            "redis://app%3Auser%40%2F%E4%B8%AD%E6%96%87:p%40ss%3A%2F%25%20word@localhost:6379/1",
            id="acl-special-characters",
        ),
        pytest.param({"password": "secret"}, "redis://:secret@localhost:6379/1", id="password-only"),
        pytest.param(
            {"username": None, "password": "secret"},
            "redis://:secret@localhost:6379/1",
            id="null-username",
        ),
        pytest.param(
            {"username": "", "password": "secret"},
            "redis://:secret@localhost:6379/1",
            id="empty-username",
        ),
        pytest.param({"username": "app_user"}, "redis://app_user:@localhost:6379/1", id="username-only"),
        pytest.param({}, "redis://localhost:6379/1", id="no-auth"),
        pytest.param({"password": ""}, "redis://localhost:6379/1", id="empty-password"),
    ],
)
def test_generated_socket_redis_credentials(socket_service, monkeypatch, credentials, expected_url) -> None:
    config = RedisConfig(db=1, **credentials)
    monkeypatch.setattr(socket_service, "_user_redis_config", staticmethod(lambda: config))
    monkeypatch.setattr(socket_service, "_user_socket_redis_client", None)
    monkeypatch.setattr(socket_service, "_user_socket_redis_client_key", None)

    client = socket_service._user_redis_client()
    try:
        assert socket_service._user_redis_client() is client
        connection = client.connection_pool.make_connection()
        assert connection.username == config.username
        assert connection.password == config.password
        assert connection.db == 1

        url = socket_service._redis_url(config)
        assert url == expected_url
        parsed = parse_url(url)
        assert parsed.get("username") == (config.username or None)
        assert parsed.get("password") == (config.password or None)
    finally:
        asyncio.run(client.aclose())


def test_generated_socket_recreates_client_when_acl_username_changes(socket_service, monkeypatch) -> None:
    config = RedisConfig(username="first_user", password="shared-password")
    monkeypatch.setattr(socket_service, "_user_redis_config", staticmethod(lambda: config))
    monkeypatch.setattr(socket_service, "_user_socket_redis_client", None)
    monkeypatch.setattr(socket_service, "_user_socket_redis_client_key", None)

    first = socket_service._user_redis_client()
    second = None
    try:
        config.username = "second_user"
        second = socket_service._user_redis_client()
        assert second is not first
        assert second.connection_pool.connection_kwargs["username"] == "second_user"
    finally:
        asyncio.run(first.aclose())
        if second is not None:
            asyncio.run(second.aclose())


def test_generated_socket_url_accepts_legacy_config_without_username(socket_service) -> None:
    config = SimpleNamespace(host="localhost", port=6379, db=0, password="p@ss:/% word")
    assert socket_service._redis_url(config) == "redis://:p%40ss%3A%2F%25%20word@localhost:6379/0"
