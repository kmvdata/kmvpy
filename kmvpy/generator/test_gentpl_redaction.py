from __future__ import annotations

from pathlib import Path

import pytest

from kmvpy.generator.cli import build_parser, handle_gentpl
from kmvpy.generator.project_generator import (
    create_project,
    export_template_from_project,
    generate_template_from_project,
)
from kmvpy.generator.secret_redactor import SECRET_PLACEHOLDER

_DEMO_REDIS_SECRET = "redis-live-secret"
_DEMO_ADMIN_SECRET = "admin-live-secret"
_DEMO_DATABASE_SECRET = "pg-live-secret"
_DEMO_COMPOSE_DATABASE_SECRET = "pg-compose-live-secret"

_REDACTED_CONFIG_FILES = (
    "demo_project_py/app/etc/develop/config.yaml",
    "demo_project_py/app/etc/release/config.yaml",
    "demo_project_py/app/etc/develop/docker-compose.yaml",
    "demo_project_py/app/etc/release/docker-compose.yaml",
)


_CONFIG_URL_USERINFO = "postgresql+asyncpg://kmvuser:"
_CONFIG_PASSWORD_LINE = f"password: {SECRET_PLACEHOLDER}"

# 与模板中 `password:` 行的出现顺序保持一致：
# auth_config.user.redis → auth_config.admin.redis → default_admin → default_storage.redis
_CONFIG_PASSWORD_SECRETS = (
    _DEMO_REDIS_SECRET,
    _DEMO_REDIS_SECRET,
    _DEMO_ADMIN_SECRET,
    _DEMO_REDIS_SECRET,
)


def _rewrite_demo_secrets(project_root: Path) -> None:
    """为生成工程注入可辨识的明文凭据，使脱敏断言真正命中。

    模板默认值本身就是占位符 ``password_by_kmvdata.com``，因此这里按语义注入
    新的明文，而不是替换历史 demo 密码；否则工程里本就没有明文，gentpl 会
    因为“无事可做”而返回空报告。
    """
    for relative in _REDACTED_CONFIG_FILES:
        path = project_root / relative
        text = path.read_text(encoding="utf-8")
        if relative.endswith("config.yaml"):
            text = text.replace(
                f"{_CONFIG_URL_USERINFO}{SECRET_PLACEHOLDER}@",
                f"{_CONFIG_URL_USERINFO}{_DEMO_DATABASE_SECRET}@",
            )
            chunks = text.split(_CONFIG_PASSWORD_LINE)
            found = len(chunks) - 1
            if found != len(_CONFIG_PASSWORD_SECRETS):
                raise AssertionError(
                    f"{relative} 的 `password:` 行数为 {found}，与夹具假设的"
                    f" {len(_CONFIG_PASSWORD_SECRETS)} 行不符，请同步更新夹具"
                )
            rebuilt = [chunks[0]]
            for secret, tail in zip(_CONFIG_PASSWORD_SECRETS, chunks[1:]):
                rebuilt.append(f"password: {secret}")
                rebuilt.append(tail)
            text = "".join(rebuilt)
        else:
            text = text.replace(
                f"POSTGRES_PASSWORD: {SECRET_PLACEHOLDER}",
                f"POSTGRES_PASSWORD: {_DEMO_COMPOSE_DATABASE_SECRET}",
            ).replace(
                f"--requirepass {SECRET_PLACEHOLDER}",
                f"--requirepass {_DEMO_REDIS_SECRET}",
            )
        path.write_text(text, encoding="utf-8")


def test_gentpl_redacts_config_and_compose_credentials(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(project_root)
    template_parent = tmp_path / "gentpl_output"

    report = export_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )

    assert report.template_root == template_parent / "template"
    assert report.dry_run is False
    assert report.file_count == len(_REDACTED_CONFIG_FILES)
    assert report.warnings == ()

    for env in ("develop", "release"):
        config_tpl = (
            report.template_root / f"py/app/etc/{env}/config.yaml.tpl"
        ).read_text(encoding="utf-8")
        assert "redis-live-secret" not in config_tpl
        assert "admin-live-secret" not in config_tpl
        assert "pg-live-secret" not in config_tpl
        # 三个 Redis 密码 + default_admin 密码
        assert config_tpl.count(f"password: {SECRET_PLACEHOLDER}") == 4
        # 数据库密码只在 URL userinfo 中替换，用户名与库名保持不变
        assert (
            "url: postgresql+asyncpg://kmvuser:"
            f"{SECRET_PLACEHOLDER}@localhost:5432/kmvdata"
        ) in config_tpl
        assert config_tpl.count("username: null") == 3
        assert "private_key_path: ./secrets/jwt-private-user" in config_tpl
        assert "active_kid: k-" in config_tpl

        compose_tpl = (
            report.template_root / f"py/app/etc/{env}/docker-compose.yaml.tpl"
        ).read_text(encoding="utf-8")
        assert "pg-compose-live-secret" not in compose_tpl
        assert "redis-live-secret" not in compose_tpl
        assert f"POSTGRES_PASSWORD: {SECRET_PLACEHOLDER}" in compose_tpl
        assert f"- --requirepass {SECRET_PLACEHOLDER}" in compose_tpl
        assert "POSTGRES_USER: dbuser" in compose_tpl
        assert compose_tpl.count(SECRET_PLACEHOLDER) == 2

    kinds = {
        item.kind for redaction in report.redactions for item in redaction.items
    }
    assert kinds == {"key", "url-userinfo", "cli-flag"}

    # 明细只含键名与行号，绝不包含原始凭据。
    for redaction in report.redactions:
        for item in redaction.items:
            assert "live-secret" not in item.key
            assert item.line >= 1


def test_gentpl_redaction_output_is_byte_stable_on_rerun(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(project_root)
    template_parent = tmp_path / "gentpl_output"

    generate_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )
    first = {
        path.relative_to(template_parent).as_posix(): path.read_bytes()
        for path in (template_parent / "template").rglob("*.yaml.tpl")
    }

    second_report = export_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
    )
    second = {
        path.relative_to(template_parent).as_posix(): path.read_bytes()
        for path in (template_parent / "template").rglob("*.yaml.tpl")
    }

    assert len(first) == len(_REDACTED_CONFIG_FILES)
    assert second == first
    assert second_report.file_count == len(_REDACTED_CONFIG_FILES)


def test_gentpl_can_disable_redaction(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(project_root)
    template_parent = tmp_path / "gentpl_output"

    report = export_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
        secret_redaction=False,
    )

    assert report.file_count == 0
    assert report.redactions == ()
    config_tpl = (
        report.template_root / "py/app/etc/develop/config.yaml.tpl"
    ).read_text(encoding="utf-8")
    assert "redis-live-secret" in config_tpl
    assert SECRET_PLACEHOLDER not in config_tpl


def test_gentpl_custom_secret_placeholder(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(project_root)
    template_parent = tmp_path / "gentpl_output"

    report = export_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
        secret_placeholder="CHANGE_ME",
    )

    config_tpl = (
        report.template_root / "py/app/etc/develop/config.yaml.tpl"
    ).read_text(encoding="utf-8")
    assert config_tpl.count("password: CHANGE_ME") == 4
    assert SECRET_PLACEHOLDER not in config_tpl


def test_gentpl_rejects_unsafe_secret_placeholder(tmp_path: Path) -> None:
    create_project("demo_project", tmp_path)

    with pytest.raises(ValueError):
        export_template_from_project(
            "demo_project",
            base_directory=tmp_path,
            template_parent_directory=tmp_path / "gentpl_output",
            secret_placeholder="bad value",
        )


def test_gentpl_dry_run_reports_without_writing(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(project_root)
    template_parent = tmp_path / "gentpl_output"

    report = export_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=template_parent,
        dry_run=True,
    )

    assert report.dry_run is True
    assert report.file_count == len(_REDACTED_CONFIG_FILES)
    assert report.item_count > 0
    assert not template_parent.exists()


def test_gentpl_leaves_docs_and_env_files_untouched(tmp_path: Path) -> None:
    project_root = create_project("demo_project", tmp_path)
    leaked_doc = project_root / "demo_project_py/docs/leak.md"
    leaked_doc.parent.mkdir(parents=True, exist_ok=True)
    leaked_doc.write_text(
        f"redis 密码 {_DEMO_REDIS_SECRET}\n", encoding="utf-8"
    )
    env_file = project_root / "demo_project_spa/.env.development"
    env_file.write_text(
        f"API_PASSWORD={_DEMO_REDIS_SECRET}\n", encoding="utf-8"
    )

    report = export_template_from_project(
        "demo_project",
        base_directory=tmp_path,
        template_parent_directory=tmp_path / "gentpl_output",
    )

    doc_tpl = (report.template_root / "py/docs/leak.md.tpl").read_text(
        encoding="utf-8"
    )
    env_tpl = (report.template_root / "spa/.env.development.tpl").read_text(
        encoding="utf-8"
    )
    assert _DEMO_REDIS_SECRET in doc_tpl
    assert _DEMO_REDIS_SECRET in env_tpl


def test_gentpl_cli_supports_output_alias_and_dry_run(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(tmp_path / "demo_project")
    template_parent = tmp_path / "cli_output"
    monkeypatch.chdir(tmp_path)

    args = build_parser().parse_args(
        ["gentpl", "demo_project", "-o", str(template_parent), "--dry-run"]
    )

    assert args.directory == template_parent
    assert args.dry_run is True
    assert args.no_secret_redaction is False
    assert args.secret_placeholder == SECRET_PLACEHOLDER
    assert handle_gentpl(args) == 0

    captured = capsys.readouterr().out
    assert "模板预演（未写盘）" in captured
    assert "py/app/etc/develop/config.yaml.tpl" in captured
    assert "redis-live-secret" not in captured
    assert "admin-live-secret" not in captured
    assert not template_parent.exists()


def test_gentpl_cli_directory_flag_still_works(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(tmp_path / "demo_project")
    template_parent = tmp_path / "cli_output"
    monkeypatch.chdir(tmp_path)

    args = build_parser().parse_args(
        ["gentpl", "demo_project", "-d", str(template_parent)]
    )

    assert args.directory == template_parent
    assert handle_gentpl(args) == 0

    captured = capsys.readouterr().out
    assert "模板已生成" in captured
    config_tpl = (
        template_parent / "template/py/app/etc/develop/config.yaml.tpl"
    ).read_text(encoding="utf-8")
    assert "redis-live-secret" not in config_tpl
    assert config_tpl.count(f"password: {SECRET_PLACEHOLDER}") == 4


def test_gentpl_cli_no_secret_redaction_keeps_plaintext(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    create_project("demo_project", tmp_path)
    _rewrite_demo_secrets(tmp_path / "demo_project")
    template_parent = tmp_path / "cli_output"
    monkeypatch.chdir(tmp_path)

    args = build_parser().parse_args(
        [
            "gentpl",
            "demo_project",
            "--output",
            str(template_parent),
            "--no-secret-redaction",
        ]
    )

    assert handle_gentpl(args) == 0
    config_tpl = (
        template_parent / "template/py/app/etc/develop/config.yaml.tpl"
    ).read_text(encoding="utf-8")
    assert "redis-live-secret" in config_tpl
    assert SECRET_PLACEHOLDER not in config_tpl