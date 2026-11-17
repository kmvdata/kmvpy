from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import PurePosixPath

SECRET_PLACEHOLDER = "password_by_kmvdata.com"

# 只有这些「工程侧文件名」会被脱敏；与模板文件名规则无关。
DEFAULT_REDACT_FILE_NAMES = frozenset(
    {
        "config.yaml",
        "config.yml",
        "docker-compose.yaml",
        "docker-compose.yml",
        "compose.yaml",
        "compose.yml",
    }
)

KIND_KEY = "key"
KIND_URL_USERINFO = "url-userinfo"
KIND_CLI_FLAG = "cli-flag"
KIND_ENV = "env"

_SECRET_KEY_SUFFIXES = (
    "password",
    "passwd",
    "pwd",
    "passphrase",
    "secret",
    "token",
    "api_key",
    "apikey",
    "access_key",
    "private_key",
    "credential",
    "credentials",
)

# 以这些后缀结尾的键只是路径/元数据，不承载明文凭据。
_NON_SECRET_KEY_SUFFIXES = (
    "_path",
    "_file",
    "_files",
    "_dir",
    "_url",
    "_uri",
    "_hash",
    "_len",
    "_length",
    "_type",
    "_name",
    "_count",
    "_hours",
    "_ms",
    "_policy",
    "_timeout",
    "_expire",
    "_expires",
    "_enabled",
    "_label",
    "_hint",
    "_min",
    "_max",
    "_field",
    "_provider",
    "_header",
    "_prefix",
    "_param",
    "_placeholder",
)

_EMPTY_SCALARS = frozenset({"", "null", "~", "none"})
_BLOCK_VALUE_PREFIXES = frozenset("|>[{&*!")
_FORBIDDEN_PLACEHOLDER_CHARS = frozenset(" \t\r\n@:/#\"'")

_IDENTIFIER = r"[A-Za-z_][A-Za-z0-9_.\-]*"

_YAML_KEY_VALUE = re.compile(
    r"^(?P<prefix>[ \t]*(?:-[ \t]+)?)"
    rf"(?P<key>{_IDENTIFIER})"
    r"(?P<sep>[ \t]*:[ \t]+)"
    r"(?P<value>.*?)"
    r"(?P<trailer>[ \t]*)$"
)

_ENV_ASSIGNMENT = re.compile(
    r"^(?P<prefix>[ \t]*(?:-[ \t]+)?)"
    rf"(?P<key>{_IDENTIFIER})"
    r"(?P<sep>[ \t]*=[ \t]*)"
    r"(?P<value>.*?)"
    r"(?P<trailer>[ \t]*)$"
)

_CLI_FLAG = re.compile(
    r"(?P<flag>--(?:requirepass|masterauth|password|passwd|auth-pass))"
    r"(?P<sep>[ \t]*=[ \t]*|[ \t]+)"
    r"(?P<value>'[^']*'|\"[^\"]*\"|[^ \t]+)"
)

# 数据库/Redis 等连接串：只替换 userinfo 中的密码，保留 scheme、用户名与 @ 之后的部分。
_URL_USERINFO = re.compile(
    r"(?P<scheme>[A-Za-z][A-Za-z0-9+.\-]*://)"
    r"(?P<user>[^:/@\s]*?)"
    r":(?P<password>[^@\s]+)@"
)


@dataclass(frozen=True)
class RedactionItem:
    """单处脱敏记录；只保存键名与行号，绝不保存原始值。"""

    key: str
    kind: str
    line: int


@dataclass(frozen=True)
class SecretRedactionResult:
    text: str
    items: tuple[RedactionItem, ...]
    warnings: tuple[str, ...]


def validate_secret_placeholder(value: str) -> str:
    """校验脱敏占位符是否可安全内联进 YAML/URL/命令行。"""
    placeholder = (value or "").strip()
    if not placeholder:
        raise ValueError("脱敏占位符不能为空。")
    if any(char in _FORBIDDEN_PLACEHOLDER_CHARS for char in placeholder):
        raise ValueError("脱敏占位符不能包含空白、@、:、/、#、引号等字符。")
    return placeholder


def should_redact_template_file(project_relative_path: str) -> bool:
    """按工程内文件名判断该文件是否需要密码/密钥脱敏。"""
    normalized = str(project_relative_path).replace("\\", "/")
    name = PurePosixPath(normalized).name.lower()
    return name in DEFAULT_REDACT_FILE_NAMES


def is_secret_key(name: str) -> bool:
    """判断 YAML 键名或环境变量名是否承载明文密码/密钥。"""
    normalized = name.strip().lower().replace("-", "_")
    if not normalized:
        return False
    if any(normalized.endswith(suffix) for suffix in _NON_SECRET_KEY_SUFFIXES):
        return False
    return any(
        normalized == suffix or normalized.endswith(f"_{suffix}")
        for suffix in _SECRET_KEY_SUFFIXES
    )


def redact_secrets(
    text: str, *, placeholder: str = SECRET_PLACEHOLDER
) -> SecretRedactionResult:
    """把配置/Compose 文本中的密码与密钥替换为占位符，其余内容保持不变。"""
    placeholder = validate_secret_placeholder(placeholder)
    items: list[RedactionItem] = []
    warnings: list[str] = []
    rendered: list[str] = []

    for lineno, raw_line in enumerate(text.splitlines(keepends=True), start=1):
        body = raw_line.rstrip("\r\n")
        ending = raw_line[len(body) :]
        rendered.append(
            _redact_line(body, lineno, placeholder, items, warnings) + ending
        )

    return SecretRedactionResult("".join(rendered), tuple(items), tuple(warnings))


def _redact_line(
    body: str,
    lineno: int,
    placeholder: str,
    items: list[RedactionItem],
    warnings: list[str],
) -> str:
    stripped = body.lstrip()
    if not stripped or stripped.startswith("#"):
        return body

    content, comment = _split_trailing_comment(body)
    if not content.strip():
        return body

    content = _redact_url_userinfo(content, lineno, placeholder, items)
    content = _redact_yaml_key_value(content, lineno, placeholder, items, warnings)
    content = _redact_env_assignment(content, lineno, placeholder, items)
    content = _redact_cli_flag(content, lineno, placeholder, items)
    return content + comment


def _split_trailing_comment(text: str) -> tuple[str, str]:
    quote = ""
    for index, char in enumerate(text):
        if quote:
            if char == quote:
                quote = ""
        elif char in "\"'":
            quote = char
        elif char == "#" and index > 0 and text[index - 1] in " \t":
            return text[:index], text[index:]
    return text, ""


def _replace_scalar(value: str, placeholder: str) -> str | None:
    """返回替换后的标量；无需改动时返回 ``None``。"""
    quote = ""
    inner = value
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        quote = value[0]
        inner = value[1:-1]

    normalized = inner.strip()
    if not normalized or normalized.lower() in _EMPTY_SCALARS:
        return None
    if normalized == placeholder:
        return None
    return f"{quote}{placeholder}{quote}"


def _redact_yaml_key_value(
    content: str,
    lineno: int,
    placeholder: str,
    items: list[RedactionItem],
    warnings: list[str],
) -> str:
    match = _YAML_KEY_VALUE.fullmatch(content)
    if match is None:
        return content

    key = match.group("key")
    if not is_secret_key(key):
        return content

    value = match.group("value")
    if value[:1] in _BLOCK_VALUE_PREFIXES:
        warnings.append(f"第 {lineno} 行 {key} 使用块标量或内联集合，未自动脱敏")
        return content

    replaced = _replace_scalar(value, placeholder)
    if replaced is None:
        return content

    items.append(RedactionItem(key=key, kind=KIND_KEY, line=lineno))
    return (
        f"{match.group('prefix')}{key}{match.group('sep')}"
        f"{replaced}{match.group('trailer')}"
    )


def _redact_env_assignment(
    content: str,
    lineno: int,
    placeholder: str,
    items: list[RedactionItem],
) -> str:
    match = _ENV_ASSIGNMENT.fullmatch(content)
    if match is None:
        return content

    key = match.group("key")
    if not is_secret_key(key):
        return content

    replaced = _replace_scalar(match.group("value"), placeholder)
    if replaced is None:
        return content

    items.append(RedactionItem(key=key, kind=KIND_ENV, line=lineno))
    return (
        f"{match.group('prefix')}{key}{match.group('sep')}"
        f"{replaced}{match.group('trailer')}"
    )


def _redact_cli_flag(
    content: str,
    lineno: int,
    placeholder: str,
    items: list[RedactionItem],
) -> str:
    def _replace(match: re.Match[str]) -> str:
        replaced = _replace_scalar(match.group("value"), placeholder)
        if replaced is None:
            return match.group(0)
        items.append(
            RedactionItem(
                key=match.group("flag"), kind=KIND_CLI_FLAG, line=lineno
            )
        )
        return f"{match.group('flag')}{match.group('sep')}{replaced}"

    return _CLI_FLAG.sub(_replace, content)


def _redact_url_userinfo(
    content: str,
    lineno: int,
    placeholder: str,
    items: list[RedactionItem],
) -> str:
    def _replace(match: re.Match[str]) -> str:
        password = match.group("password")
        if not password or password == placeholder:
            return match.group(0)
        items.append(
            RedactionItem(
                key=f"{match.group('scheme')}{match.group('user')}:<password>@",
                kind=KIND_URL_USERINFO,
                line=lineno,
            )
        )
        return (
            f"{match.group('scheme')}{match.group('user')}:{placeholder}@"
        )

    return _URL_USERINFO.sub(_replace, content)
