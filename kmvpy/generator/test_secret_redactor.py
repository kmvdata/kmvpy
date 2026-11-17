from __future__ import annotations

import pytest

from kmvpy.generator.secret_redactor import (
    KIND_CLI_FLAG,
    KIND_ENV,
    KIND_KEY,
    KIND_URL_USERINFO,
    SECRET_PLACEHOLDER,
    RedactionItem,
    is_secret_key,
    redact_secrets,
    should_redact_template_file,
    validate_secret_placeholder,
)


def test_redacts_nested_redis_password_and_keeps_neighbors() -> None:
    text = "\n".join(
        [
            "auth_config:",
            "  user:",
            "    redis:",
            "      host: localhost",
            "      username: null",
            "      password: cgd3nf4fs1PnYfKDgA3gCxk47zFNT9L5",
            "",
        ]
    )

    result = redact_secrets(text)

    lines = result.text.splitlines()
    assert lines[3] == "      host: localhost"
    assert lines[4] == "      username: null"
    assert lines[5] == f"      password: {SECRET_PLACEHOLDER}"
    assert result.items == (RedactionItem(key="password", kind=KIND_KEY, line=6),)
    assert result.warnings == ()


def test_redacts_database_url_password_only() -> None:
    text = (
        "    url: postgresql+asyncpg://kmvuser:www.kmvdata.com"
        "@localhost:5432/kmvdata\n"
    )

    result = redact_secrets(text)

    assert result.text == (
        "    url: postgresql+asyncpg://kmvuser:"
        f"{SECRET_PLACEHOLDER}@localhost:5432/kmvdata\n"
    )
    assert [item.kind for item in result.items] == [KIND_URL_USERINFO]
    assert result.items[0].key == "postgresql+asyncpg://kmvuser:<password>@"


def test_redacts_url_password_without_username() -> None:
    result = redact_secrets("url: redis://:pw-123@localhost:6379/0\n")

    assert result.text == f"url: redis://:{SECRET_PLACEHOLDER}@localhost:6379/0\n"


def test_leaves_url_without_credentials() -> None:
    text = "url: https://example.kmvdata.com/api\n"

    result = redact_secrets(text)

    assert result.text == text
    assert result.items == ()


@pytest.mark.parametrize(
    ("line", "expected"),
    [
        (
            "      - --requirepass pw\n",
            f"      - --requirepass {SECRET_PLACEHOLDER}\n",
        ),
        (
            "      - --requirepass=pw\n",
            f"      - --requirepass={SECRET_PLACEHOLDER}\n",
        ),
        (
            "command: redis-server --requirepass pw --maxmemory 800mb\n",
            "command: redis-server --requirepass "
            f"{SECRET_PLACEHOLDER} --maxmemory 800mb\n",
        ),
    ],
)
def test_redacts_cli_password_flags(line: str, expected: str) -> None:
    result = redact_secrets(line)

    assert result.text == expected
    assert {item.kind for item in result.items} == {KIND_CLI_FLAG}


def test_redacts_env_assignment_list_items() -> None:
    result = redact_secrets("      - POSTGRES_PASSWORD=pw-1\n")

    assert result.text == f"      - POSTGRES_PASSWORD={SECRET_PLACEHOLDER}\n"
    assert result.items == (
        RedactionItem(key="POSTGRES_PASSWORD", kind=KIND_ENV, line=1),
    )


def test_redacts_env_mapping_values() -> None:
    result = redact_secrets(
        "      POSTGRES_PASSWORD: pw-1\n      POSTGRES_USER: dbuser\n"
    )

    assert result.text == (
        f"      POSTGRES_PASSWORD: {SECRET_PLACEHOLDER}\n"
        "      POSTGRES_USER: dbuser\n"
    )


@pytest.mark.parametrize(
    "line",
    [
        "      username: null\n",
        "      user: dbuser\n",
        "      POSTGRES_USER: dbuser\n",
        "      private_key_path: ./secrets/jwt-private-user.pem\n",
        "      public_key_path: ./secrets/jwt-public-user.pem\n",
        "      access_token_lifetime_hours: 48.0\n",
        "      decode_responses: true\n",
        "      active_kid: k-28f7d5abf5953d37ce1d0bf9\n",
        "      options: -c timezone=Asia/Shanghai\n",
        "      port: 15000\n",
        "      db: 1\n",
        "      database: kmvdata\n",
        "      - redis-server\n",
    ],
)
def test_keeps_non_secret_keys(line: str) -> None:
    result = redact_secrets(line)

    assert result.text == line
    assert result.items == ()


@pytest.mark.parametrize(
    "line",
    [
        "# password: cgd3nf4fs1PnYfKDgA3gCxk47zFNT9L5\n",
        "  # POSTGRES_PASSWORD: 3PVtuInMCcYwOa9Xye7akWQr0RTfTFp3\n",
    ],
)
def test_does_not_touch_comment_lines(line: str) -> None:
    result = redact_secrets(line)

    assert result.text == line
    assert result.items == ()


@pytest.mark.parametrize("quote", ['"', "'"])
def test_preserves_quote_style(quote: str) -> None:
    line = f"  password: {quote}s3cret value{quote}\n"

    result = redact_secrets(line)

    assert result.text == f"  password: {quote}{SECRET_PLACEHOLDER}{quote}\n"


def test_preserves_trailing_comment() -> None:
    line = "  password: s3cret  # 上线前替换\n"

    result = redact_secrets(line)

    assert result.text == f"  password: {SECRET_PLACEHOLDER}  # 上线前替换\n"


def test_second_pass_is_byte_identical() -> None:
    text = "\n".join(
        [
            "  password: s3cret",
            "    url: postgresql+asyncpg://kmvuser:pw@localhost:5432/kmvdata",
            "      - --requirepass pw",
            "",
        ]
    )

    first = redact_secrets(text)
    second = redact_secrets(first.text)

    assert second.text == first.text
    assert second.items == ()


@pytest.mark.parametrize("value", ["null", "~", "''", '\"\"'])
def test_skips_empty_values(value: str) -> None:
    line = f"  password: {value}\n"

    result = redact_secrets(line)

    assert result.text == line
    assert result.items == ()


def test_block_scalar_is_reported_without_changing_value() -> None:
    text = "  password: |\n    multi-line-secret\n"

    result = redact_secrets(text)

    assert "multi-line-secret" in result.text
    assert result.items == ()
    assert result.warnings == (
        "第 1 行 password 使用块标量或内联集合，未自动脱敏",
    )


def test_preserves_crlf_line_endings() -> None:
    result = redact_secrets("  password: s3cret\r\n  port: 6379\r\n")

    assert result.text == f"  password: {SECRET_PLACEHOLDER}\r\n  port: 6379\r\n"


def test_handles_final_line_without_newline() -> None:
    result = redact_secrets("  password: s3cret")

    assert result.text == f"  password: {SECRET_PLACEHOLDER}"


@pytest.mark.parametrize(
    "path",
    [
        "demo_project_py/app/etc/develop/config.yaml",
        "demo_project_py/app/etc/release/config.yml",
        "demo_project_py/app/etc/release/docker-compose.yaml",
        "docker-compose.yml",
        "compose.yaml",
        "compose.yml",
    ],
)
def test_should_redact_template_file_accepts_known_names(path: str) -> None:
    assert should_redact_template_file(path) is True


@pytest.mark.parametrize(
    "path",
    [
        "demo_project_py/app/etc/develop/.env.development",
        "demo_project_py/pyproject.toml",
        "docs/ops-docker-services.md",
        "demo_project_py/app/etc/develop/config.yaml.bak-20240101",
    ],
)
def test_should_redact_template_file_rejects_other_files(path: str) -> None:
    assert should_redact_template_file(path) is False


@pytest.mark.parametrize(
    "value",
    ["", "   ", "a b", "user@host", "a/b", "a:b", "a#b", "'quoted'"],
)
def test_validate_secret_placeholder_rejects_unsafe_values(value: str) -> None:
    with pytest.raises(ValueError):
        validate_secret_placeholder(value)


def test_validate_secret_placeholder_accepts_safe_values() -> None:
    assert validate_secret_placeholder(SECRET_PLACEHOLDER) == SECRET_PLACEHOLDER
    assert validate_secret_placeholder("  REDACTED  ") == "REDACTED"


@pytest.mark.parametrize(
    "key",
    [
        "password",
        "PASSWORD",
        "postgres_password",
        "redis-password",
        "admin_secret",
        "api_key",
        "apiKey",
        "access_token",
        "refresh_token",
        "private_key",
        "client_secret",
        "aws_secret_access_key",
    ],
)
def test_is_secret_key_accepts_secret_names(key: str) -> None:
    assert is_secret_key(key) is True


@pytest.mark.parametrize(
    "key",
    [
        "username",
        "user",
        "POSTGRES_USER",
        "POSTGRES_DB",
        "host",
        "port",
        "db",
        "active_kid",
        "issuer",
        "audience",
        "decode_responses",
        "private_key_path",
        "public_key_path",
        "access_token_lifetime_hours",
        "url",
        "database",
        "options",
        "password_hint",
        "secret_placeholder",
    ],
)
def test_is_secret_key_rejects_non_secret_names(key: str) -> None:
    assert is_secret_key(key) is False
