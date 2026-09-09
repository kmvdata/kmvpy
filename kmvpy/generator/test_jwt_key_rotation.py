from __future__ import annotations

import argparse
import re
from pathlib import Path

import pytest
import yaml

from kmvpy.common.conf import BaseConfig
from kmvpy.generator.cli import build_parser, handle_rotate_jwt_keys
from kmvpy.generator.jwt_key_rotation import rotate_jwt_keys

from kmvpy.core.main.test.auth_test_utils import build_auth_config_dict, generate_rsa_key_pair


def _write_config(config_path: Path) -> dict:
    auth_config = build_auth_config_dict(
        user_kid="user-old",
        admin_kid="admin-old",
    )
    data = {
        "general": {"debug": True, "env": "test", "timezone": "UTC"},
        "logging": {"level": "INFO"},
        "auth_config": auth_config,
    }
    config_path.write_text(
        yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )
    return data


def _load_yaml(config_path: Path) -> dict:
    return yaml.safe_load(config_path.read_text(encoding="utf-8"))


def test_rotate_jwt_keys_generates_new_key_pairs_and_updates_config(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    original_data = _write_config(config_path)

    result = rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    assert result.config_path == config_path
    assert result.backup_path.is_file()
    assert len(result.roles) == 2

    for role in ("user", "admin"):
        jwt_config = updated_data["auth_config"][role]["jwt"]
        active_kid = jwt_config["active_kid"]
        public_keys = jwt_config["public_keys"]

        assert re.fullmatch(r"k-[0-9a-f]{24}", active_kid)
        assert public_keys[0]["kid"] == active_kid
        assert jwt_config["private_key_path"].endswith(f"jwt-private-{role}-{active_kid}.pem")
        assert public_keys[0]["public_key_path"].endswith(f"jwt-public-{role}-{active_kid}.pem")
        assert Path(jwt_config["private_key_path"]).is_file()
        assert Path(public_keys[0]["public_key_path"]).is_file()
        assert public_keys[1]["kid"] == original_data["auth_config"][role]["jwt"]["active_kid"]
        assert len(public_keys) == 2

    BaseConfig.model_validate(updated_data)


def test_rotate_jwt_keys_drops_missing_public_key_entries(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    original_data = _write_config(config_path)
    for role in ("user", "admin"):
        original_data["auth_config"][role]["jwt"]["public_keys"][0]["public_key_path"] = str(
            tmp_path / f"missing-{role}-public.pem"
        )
    config_path.write_text(
        yaml.safe_dump(original_data, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    for role in ("user", "admin"):
        public_keys = updated_data["auth_config"][role]["jwt"]["public_keys"]
        assert len(public_keys) == 1
        assert public_keys[0]["kid"] == updated_data["auth_config"][role]["jwt"]["active_kid"]
        assert Path(public_keys[0]["public_key_path"]).is_file()

    BaseConfig.model_validate(updated_data)


def test_rotate_jwt_keys_creates_default_auth_config_when_missing(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    config_path = tmp_path / "config.yaml"
    config_path.write_text(
        yaml.safe_dump(
            {
                "general": {"debug": True, "env": "test", "timezone": "UTC"},
                "logging": {"level": "INFO"},
            },
            allow_unicode=True,
            sort_keys=False,
        ),
        encoding="utf-8",
    )
    runner_dir = tmp_path / "runner"
    runner_dir.mkdir()
    monkeypatch.chdir(runner_dir)

    rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    assert not (runner_dir / "secrets").exists()
    for role in ("user", "admin"):
        jwt_config = updated_data["auth_config"][role]["jwt"]
        active_kid = jwt_config["active_kid"]
        assert jwt_config["algorithm"] == "RS256"
        assert jwt_config["private_key_path"].startswith(f"./secrets/jwt-private-{role}-k-")
        assert jwt_config["public_keys"][0]["public_key_path"].startswith(f"./secrets/jwt-public-{role}-k-")
        assert jwt_config["public_keys"][0]["kid"] == active_kid
        assert (tmp_path / jwt_config["private_key_path"]).is_file()
        assert (tmp_path / jwt_config["public_keys"][0]["public_key_path"]).is_file()

    BaseConfig.load_config(config_path)


def test_rotate_jwt_keys_removes_legacy_jwt_fields_when_filling_defaults(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    data = {
        "general": {"debug": True, "env": "test", "timezone": "UTC"},
        "logging": {"level": "INFO"},
        "auth_config": {
            "user": {
                "jwt": {
                    "private_key": "__JWT_USER_PRIVATE_KEY__",
                    "public_key": "__JWT_USER_PUBLIC_KEY__",
                    "key_id": "user-key-1",
                }
            },
            "admin": {
                "jwt": {
                    "private_key": "__JWT_ADMIN_PRIVATE_KEY__",
                    "public_key": "__JWT_ADMIN_PUBLIC_KEY__",
                    "key_id": "admin-key-1",
                }
            },
        },
    }
    config_path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")

    rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    for role in ("user", "admin"):
        jwt_config = updated_data["auth_config"][role]["jwt"]
        assert "private_key" not in jwt_config
        assert "public_key" not in jwt_config
        assert "key_id" not in jwt_config
        assert jwt_config["algorithm"] == "RS256"

    BaseConfig.load_config(config_path)


def test_rotate_jwt_keys_migrates_hs_algorithm_to_rs256(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    data = {
        "general": {"debug": True, "env": "test", "timezone": "UTC"},
        "logging": {"level": "INFO"},
        "auth_config": {
            "user": {
                "jwt": {
                    "algorithm": "HS512",
                    "secret_key": "legacy-user-secret",
                }
            },
            "admin": {
                "jwt": {
                    "algorithm": "HS512",
                    "secret_key": "legacy-admin-secret",
                }
            },
        },
    }
    config_path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")

    rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    for role in ("user", "admin"):
        jwt_config = updated_data["auth_config"][role]["jwt"]
        assert jwt_config["algorithm"] == "RS256"
        assert "secret_key" not in jwt_config
        assert jwt_config["private_key_path"].startswith(f"./secrets/jwt-private-{role}-k-")
        assert jwt_config["public_keys"][0]["public_key_path"].startswith(f"./secrets/jwt-public-{role}-k-")
        assert (tmp_path / jwt_config["private_key_path"]).is_file()
        assert (tmp_path / jwt_config["public_keys"][0]["public_key_path"]).is_file()

    BaseConfig.load_config(config_path)


def test_rotate_jwt_keys_keeps_at_most_one_existing_old_public_key(tmp_path: Path) -> None:
    config_path = tmp_path / "config.yaml"
    original_data = _write_config(config_path)
    for role in ("user", "admin"):
        extra_key_pair = generate_rsa_key_pair()
        original_data["auth_config"][role]["jwt"]["public_keys"].append({
            "kid": f"{role}-older",
            "public_key_path": extra_key_pair.public_key_path,
        })
    config_path.write_text(
        yaml.safe_dump(original_data, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    for role in ("user", "admin"):
        public_keys = updated_data["auth_config"][role]["jwt"]["public_keys"]
        assert len(public_keys) == 2
        assert public_keys[0]["kid"] == updated_data["auth_config"][role]["jwt"]["active_kid"]
        assert public_keys[1]["kid"] == original_data["auth_config"][role]["jwt"]["active_kid"]


def test_rotate_jwt_keys_preserves_relative_secret_path_style(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    config_dir = tmp_path / "etc" / "develop"
    config_dir.mkdir(parents=True)
    config_path = config_dir / "config.yaml"
    original_data = _write_config(config_path)
    for role in ("user", "admin"):
        jwt_config = original_data["auth_config"][role]["jwt"]
        original_private_key_path = Path(jwt_config["private_key_path"])
        original_public_key_path = Path(jwt_config["public_keys"][0]["public_key_path"])
        jwt_config["private_key_path"] = f"./secrets/jwt-private-{role}-old.pem"
        jwt_config["public_keys"][0]["public_key_path"] = f"./secrets/jwt-public-{role}-old.pem"
        private_source = config_dir / "secrets" / f"jwt-private-{role}-old.pem"
        public_source = config_dir / "secrets" / f"jwt-public-{role}-old.pem"
        private_source.parent.mkdir(parents=True, exist_ok=True)
        private_source.write_bytes(original_private_key_path.read_bytes())
        private_source.chmod(0o400)
        public_source.parent.mkdir(parents=True, exist_ok=True)
        public_source.write_bytes(original_public_key_path.read_bytes())
        public_source.chmod(0o444)

    config_path.write_text(
        yaml.safe_dump(original_data, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )

    runner_dir = tmp_path / "runner"
    runner_dir.mkdir()
    monkeypatch.chdir(runner_dir)

    rotate_jwt_keys(config_path)
    updated_data = _load_yaml(config_path)

    assert updated_data["auth_config"]["user"]["jwt"]["private_key_path"].startswith("./secrets/jwt-private-user-k-")
    assert updated_data["auth_config"]["user"]["jwt"]["public_keys"][0]["public_key_path"].startswith(
        "./secrets/jwt-public-user-k-"
    )
    new_private_key_path = config_dir / updated_data["auth_config"]["user"]["jwt"]["private_key_path"]
    new_public_key_path = config_dir / updated_data["auth_config"]["user"]["jwt"]["public_keys"][0]["public_key_path"]
    assert new_private_key_path.is_file()
    assert new_public_key_path.is_file()
    assert not (runner_dir / "secrets").exists()
    BaseConfig.load_config(config_path)


def test_rotate_jwt_keys_cli_handler_and_parser(tmp_path: Path, capsys: pytest.CaptureFixture[str]) -> None:
    config_path = tmp_path / "config.yaml"
    _write_config(config_path)

    parser = build_parser()
    args = parser.parse_args(["rotate-jwt-keys", str(config_path)])
    assert args.command == "rotate-jwt-keys"
    assert handle_rotate_jwt_keys(argparse.Namespace(config_path=config_path)) == 0

    output = capsys.readouterr().out
    assert "JWT 密钥已轮换" in output
    assert "user:" in output
    assert "admin:" in output
