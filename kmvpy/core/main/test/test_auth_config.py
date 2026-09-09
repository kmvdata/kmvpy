import pytest

from kmvpy.common.conf import BaseConfig

from .auth_test_utils import build_auth_config_dict, build_base_config, generate_rsa_key_pair


def test_auth_config_float_hours_to_seconds_defaults() -> None:
    config = build_base_config()

    assert config.auth_config is not None
    assert config.auth_config.user.jwt.access_token_lifetime_seconds == 15 * 60
    assert config.auth_config.admin.jwt.access_token_lifetime_seconds == 600
    assert config.auth_config.user.session.idle_timeout_seconds == 24 * 60 * 60
    assert config.auth_config.admin.session.absolute_timeout_seconds == 8 * 60 * 60


def test_auth_config_rejects_absolute_before_idle() -> None:
    auth_config = build_auth_config_dict(user_idle_hours=2.0, user_absolute_hours=1.0)

    with pytest.raises(ValueError, match="absolute_timeout_hours"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_access_lifetime_not_shorter_than_idle() -> None:
    auth_config = build_auth_config_dict(user_access_hours=1.0, user_idle_hours=1.0)

    with pytest.raises(ValueError, match="access_token_lifetime_hours"):
        build_base_config(auth_config=auth_config)


def test_auth_config_requires_redis_when_session_is_configured() -> None:
    auth_config = build_auth_config_dict(include_user_redis=False)

    with pytest.raises(ValueError, match="redis"):
        build_base_config(auth_config=auth_config)


@pytest.mark.parametrize("algorithm", ["none", "HS256", "HS384", "HS512"])
def test_auth_config_rejects_none_and_hs_algorithms(algorithm: str) -> None:
    auth_config = build_auth_config_dict(user_algorithm=algorithm)

    with pytest.raises(ValueError, match="algorithm"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_legacy_jwt_fields() -> None:
    auth_config = build_auth_config_dict()
    user_jwt = auth_config["user"]["jwt"]
    user_jwt["secret_key"] = "legacy-secret"
    user_jwt["access_token_expire_hours"] = 24

    with pytest.raises(ValueError, match="旧字段"):
        build_base_config(auth_config=auth_config)


def test_auth_config_requires_distinct_user_admin_active_kid_and_audience() -> None:
    auth_config = build_auth_config_dict()
    same_kid = auth_config["user"]["jwt"]["active_kid"]
    auth_config["admin"]["jwt"]["active_kid"] = same_kid
    auth_config["admin"]["jwt"]["public_keys"][0]["kid"] = same_kid

    with pytest.raises(ValueError, match="active_kid"):
        build_base_config(auth_config=auth_config)

    auth_config = build_auth_config_dict()
    auth_config["admin"]["jwt"]["audience"] = auth_config["user"]["jwt"]["audience"]

    with pytest.raises(ValueError, match="audience"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_duplicate_public_kid() -> None:
    auth_config = build_auth_config_dict()
    user_public_keys = auth_config["user"]["jwt"]["public_keys"]
    user_public_keys.append(dict(user_public_keys[0]))

    with pytest.raises(ValueError, match="重复"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_active_kid_missing_from_public_keys() -> None:
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["active_kid"] = "missing-key"

    with pytest.raises(ValueError, match="active_kid"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_missing_private_key_path(tmp_path) -> None:
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["private_key_path"] = str(tmp_path / "missing-private.pem")

    with pytest.raises(ValueError, match="private_key_path.*不存在"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_missing_public_key_path(tmp_path) -> None:
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["public_keys"][0]["public_key_path"] = str(tmp_path / "missing-public.pem")

    with pytest.raises(ValueError, match="public_key_path.*不存在"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_inline_pem_in_path_fields() -> None:
    key_pair = generate_rsa_key_pair()
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["private_key_path"] = key_pair.private_key

    with pytest.raises(ValueError, match="PEM 内容") as exc_info:
        build_base_config(auth_config=auth_config)

    error_text = str(exc_info.value)
    assert key_pair.private_key not in error_text
    assert "BEGIN PRIVATE KEY" not in error_text


def test_auth_config_rejects_legacy_inline_private_public_key_fields() -> None:
    key_pair = generate_rsa_key_pair()
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["private_key"] = key_pair.private_key
    auth_config["user"]["jwt"]["public_key"] = key_pair.public_key

    with pytest.raises(ValueError, match="PEM 内容|旧字段"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_invalid_pem_file(tmp_path) -> None:
    invalid_private_key_path = tmp_path / "invalid-private.pem"
    invalid_private_key_path.write_text("not a pem key", encoding="utf-8")
    invalid_private_key_path.chmod(0o400)
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["private_key_path"] = str(invalid_private_key_path)

    with pytest.raises(ValueError, match="合法.*PEM"):
        build_base_config(auth_config=auth_config)


def test_auth_config_rejects_mismatched_active_private_and_public_key() -> None:
    other_key_pair = generate_rsa_key_pair()
    auth_config = build_auth_config_dict()
    auth_config["user"]["jwt"]["public_keys"][0]["public_key_path"] = other_key_pair.public_key_path

    with pytest.raises(ValueError, match="不匹配"):
        build_base_config(auth_config=auth_config)


def test_base_config_accepts_missing_auth_config_for_public_apps() -> None:
    config = BaseConfig.model_validate({
        "general": {"debug": True, "env": "test"},
        "logging": {"level": "INFO"},
    })

    assert config.auth_config is None


def test_base_config_load_config_resolves_jwt_key_paths_relative_to_config_file(
    tmp_path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    key_pair = generate_rsa_key_pair()
    config_dir = tmp_path / "etc" / "develop"
    config_dir.mkdir(parents=True)
    secret_dir = config_dir / "secrets"
    secret_dir.mkdir()
    private_key_path = secret_dir / "jwt-private-user-test.pem"
    public_key_path = secret_dir / "jwt-public-user-test.pem"
    private_key_path.write_text(key_pair.private_key, encoding="utf-8")
    private_key_path.chmod(0o400)
    public_key_path.write_text(key_pair.public_key, encoding="utf-8")
    public_key_path.chmod(0o444)

    admin_key_pair = generate_rsa_key_pair()
    admin_private_key_path = secret_dir / "jwt-private-admin-test.pem"
    admin_public_key_path = secret_dir / "jwt-public-admin-test.pem"
    admin_private_key_path.write_text(admin_key_pair.private_key, encoding="utf-8")
    admin_private_key_path.chmod(0o400)
    admin_public_key_path.write_text(admin_key_pair.public_key, encoding="utf-8")
    admin_public_key_path.chmod(0o444)

    config_path = config_dir / "config.yaml"
    config_path.write_text(
        """
general:
  debug: true
  env: "test"
  timezone: "UTC"
logging:
  level: "INFO"
auth_config:
  user:
    jwt:
      algorithm: "RS256"
      active_kid: "user-test"
      private_key_path: "./secrets/jwt-private-user-test.pem"
      public_keys:
        - kid: "user-test"
          public_key_path: "./secrets/jwt-public-user-test.pem"
      issuer: "kmvpy"
      audience: "kmvpy-user-api"
      access_token_lifetime_hours: 0.25
    session:
      idle_timeout_hours: 24.0
      absolute_timeout_hours: 720.0
      max_sessions_per_user: null
    redis:
      host: "localhost"
      port: 6379
      db: 1
      decode_responses: true
  admin:
    jwt:
      algorithm: "RS256"
      active_kid: "admin-test"
      private_key_path: "./secrets/jwt-private-admin-test.pem"
      public_keys:
        - kid: "admin-test"
          public_key_path: "./secrets/jwt-public-admin-test.pem"
      issuer: "kmvpy"
      audience: "kmvpy-admin-api"
      access_token_lifetime_hours: 0.1667
    session:
      idle_timeout_hours: 1.0
      absolute_timeout_hours: 8.0
      max_sessions_per_user: 3
    redis:
      host: "localhost"
      port: 6379
      db: 10
      decode_responses: true
""",
        encoding="utf-8",
    )

    runner_dir = tmp_path / "runner"
    runner_dir.mkdir()
    monkeypatch.chdir(runner_dir)

    config = BaseConfig.load_config(config_path)

    assert config.auth_config is not None
    assert config.auth_config.user.jwt.private_key_path == str(private_key_path)
    assert config.auth_config.user.jwt.public_keys[0].public_key_path == str(public_key_path)
