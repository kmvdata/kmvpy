import logging
import os
import stat
import sys
from pathlib import Path
from typing import Any, TypeVar, Optional, Union
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import i18n
import yaml
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec, rsa
from fastapi import FastAPI
from fastapi_socketio import SocketManager
from pydantic import BaseModel, ConfigDict, Field, PrivateAttr, computed_field, field_validator, model_validator

from kmvpy.common.tool.logger import logger

# 仅支持 Python >= 3.11：使用内置日志级别映射

def get_level_value(level_text: str) -> int:
    return logging.getLevelNamesMapping().get(level_text.upper(), 0)


def _validate_timezone_name(value: str) -> str:
    if not isinstance(value, str):
        raise TypeError("timezone 必须是 IANA 时区字符串")

    normalized = value.strip()
    if not normalized:
        raise ValueError("timezone 不能为空")

    try:
        ZoneInfo(normalized)
    except ZoneInfoNotFoundError as exc:
        raise ValueError(f"无效 timezone: {normalized}") from exc

    return normalized


# ---------------------------
# 嵌套配置模型
# ---------------------------


class DatabaseConfig(BaseModel):
    url: str
    pool_size: int = Field(default=20, ge=1)
    max_overflow: int = Field(default=10, ge=0)
    pool_recycle: int = Field(default=3600, ge=60)
    timeout: int = Field(default=60, ge=1)
    echo: bool = False

    # PostgreSQL 特有参数；不要直接用于 MySQL / SQLite
    pool_pre_ping: bool = True
    ssl: bool = False
    options: str = ''


class RedisConfig(BaseModel):
    host: str = "localhost"
    port: int = Field(default=6379, ge=1, le=65535)
    db: int = Field(default=0, ge=0)
    username: Optional[str] = Field(default=None, description="Redis ACL 用户名；不配置时兼容仅密码认证")
    password: Optional[str] = None
    decode_responses: bool = True


class DefaultStorageConfig(BaseModel):
    """默认存储配置：用于构建全局 KOrmStorage/DefaultStorage 实例。"""
    database: DatabaseConfig
    redis: Optional[RedisConfig] = None


class GeneralConfig(BaseModel):
    debug: bool = False
    env: str = 'test'
    timezone: str = "Asia/Shanghai"

    @field_validator("timezone")
    @classmethod
    def validate_timezone(cls, value: str) -> str:
        return _validate_timezone_name(value)


class LoggingConfig(BaseModel):
    level_text: str = Field(alias="level")  # 改为字符串更符合日志级别惯例，如 "INFO"
    path: str | None = None  # 日志文件路径
    format: str | None = '%(asctime)s - %(levelname)s - 进程%(process)d:线程%(thread)d - %(filename)s:%(funcName)s:%(lineno)d: %(message)s'
    max_bytes: str = '100MB'  # 默认：100MB
    backup_count: int = 20  # 默认：20个

    @computed_field  # Pydantic v2 新特性
    @property
    def level(self) -> int:
        """通过属性直接访问数值级别"""
        return get_level_value(self.level_text)


class SocketioConfig(BaseModel):
    mount_location: str = "/ws"
    socketio_path: str = "/socket.io"
    cors_allowed_origins: Union[str, list] = '*'


class ServiceConfig(BaseModel):
    host: str = "0.0.0.0"
    port: int = Field(ge=1, le=65535, default=8000)
    workers: int = Field(ge=1, default=4)
    reload: bool = False
    socketio_config: Optional[SocketioConfig] = None
    # CORS 允许的前端来源（如 https://sucai.tuta.icu），不设则不添加 CORS 中间件
    cors_allow_origins: Optional[list[str]] = None

    def gen_socket_manager(self, app: FastAPI) -> Optional[SocketManager]:
        """
        初始化并返回 Socket.IO 管理器
        Args:
            app: FastAPI 应用实例
        Returns:
            Optional[SocketManager]:
                - 如果配置了 socketio_config，返回 SocketManager 实例
                - 如果没有配置，返回 None
        """
        if not self.socketio_config:
            return None

        return SocketManager(
            app=app,
            socketio_path=self.socketio_config.socketio_path,
            cors_allowed_origins=self.socketio_config.cors_allowed_origins
        )


class I18nConfig(BaseModel):
    path: str = "locales"
    locale: str = "en"


class ProxiesConfig(BaseModel):
    http: str
    https: str


ASYMMETRIC_JWT_ALGORITHMS = frozenset({
    "RS256",
    "RS384",
    "RS512",
    "PS256",
    "PS384",
    "PS512",
    "ES256",
    "ES384",
    "ES512",
})
FORBIDDEN_JWT_ALGORITHMS = frozenset({"none", "HS256", "HS384", "HS512"})


def _hours_to_seconds(hours: float) -> int:
    return max(1, int(round(float(hours) * 3600)))


def _resolve_config_relative_path(value: object, config_dir: Path) -> object:
    if not isinstance(value, str):
        return value
    normalized = value.strip()
    if not normalized or _looks_like_pem(normalized):
        return value
    path = Path(normalized).expanduser()
    if path.is_absolute():
        return value
    return str(config_dir / path)


def _resolve_auth_key_paths_relative_to_config(data: object, config_dir: Path) -> None:
    if not isinstance(data, dict):
        return
    auth_config = data.get("auth_config")
    if not isinstance(auth_config, dict):
        return
    for role in ("user", "admin"):
        role_config = auth_config.get(role)
        if not isinstance(role_config, dict):
            continue
        jwt_config = role_config.get("jwt")
        if not isinstance(jwt_config, dict):
            continue
        if "private_key_path" in jwt_config:
            jwt_config["private_key_path"] = _resolve_config_relative_path(
                jwt_config["private_key_path"],
                config_dir,
            )
        public_keys = jwt_config.get("public_keys")
        if not isinstance(public_keys, list):
            continue
        for public_key in public_keys:
            if not isinstance(public_key, dict) or "public_key_path" not in public_key:
                continue
            public_key["public_key_path"] = _resolve_config_relative_path(
                public_key["public_key_path"],
                config_dir,
            )


def _looks_like_pem(value: object) -> bool:
    if not isinstance(value, str):
        return False
    normalized = value.strip()
    return "-----BEGIN " in normalized and "-----END " in normalized


def _find_inline_pem_config_path(value: object, path: str = "jwt") -> str | None:
    if _looks_like_pem(value):
        return path
    if isinstance(value, dict):
        for key, child in value.items():
            found = _find_inline_pem_config_path(child, f"{path}.{key}")
            if found is not None:
                return found
    if isinstance(value, list):
        for index, child in enumerate(value):
            found = _find_inline_pem_config_path(child, f"{path}[{index}]")
            if found is not None:
                return found
    return None


def _normalize_required_path(value: str, field_name: str) -> str:
    normalized = str(value or "").strip()
    if not normalized:
        raise ValueError(f"JWT {field_name} 不能为空")
    if _looks_like_pem(normalized):
        raise ValueError(f"JWT {field_name} 只能配置文件路径，不能写入 PEM 内容")
    return str(Path(normalized).expanduser())


def _read_key_file(path: str, field_name: str) -> bytes:
    key_path = Path(path)
    try:
        if not key_path.exists():
            raise ValueError(f"JWT {field_name} 文件不存在: {path}")
        if not key_path.is_file():
            raise ValueError(f"JWT {field_name} 不是普通文件: {path}")
        return key_path.read_bytes()
    except ValueError:
        raise
    except PermissionError as exc:
        raise ValueError(f"JWT {field_name} 文件不可读: {path}") from exc
    except OSError as exc:
        raise ValueError(f"JWT {field_name} 文件不可读: {path}: {exc.strerror}") from exc


def _load_private_key_from_path(path: str):
    key_bytes = _read_key_file(path, "private_key_path")
    try:
        return serialization.load_pem_private_key(key_bytes, password=None)
    except Exception as exc:
        raise ValueError(f"JWT private_key_path 文件不是合法的未加密 PEM 私钥: {path}") from exc


def _load_public_key_from_path(path: str):
    key_bytes = _read_key_file(path, "public_key_path")
    try:
        return serialization.load_pem_public_key(key_bytes)
    except Exception as exc:
        raise ValueError(f"JWT public_key_path 文件不是合法 PEM 公钥: {path}") from exc


def _public_key_bytes(public_key: Any) -> bytes:
    return public_key.public_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )


def _public_keys_match(private_key: Any, public_key: Any) -> bool:
    try:
        return _public_key_bytes(private_key.public_key()) == _public_key_bytes(public_key)
    except Exception:
        return False


def _validate_jwt_key_type(algorithm: str, private_key: Any, public_keys: dict[str, Any]) -> None:
    if algorithm.startswith(("RS", "PS")):
        if not isinstance(private_key, rsa.RSAPrivateKey):
            raise ValueError(f"JWT algorithm={algorithm} 必须使用 RSA 私钥")
        invalid_kids = [
            kid for kid, public_key in public_keys.items()
            if not isinstance(public_key, rsa.RSAPublicKey)
        ]
        if invalid_kids:
            raise ValueError(f"JWT algorithm={algorithm} 的 public_keys 必须全部是 RSA 公钥: {invalid_kids}")
        return

    if algorithm.startswith("ES"):
        if not isinstance(private_key, ec.EllipticCurvePrivateKey):
            raise ValueError(f"JWT algorithm={algorithm} 必须使用 EC 私钥")
        invalid_kids = [
            kid for kid, public_key in public_keys.items()
            if not isinstance(public_key, ec.EllipticCurvePublicKey)
        ]
        if invalid_kids:
            raise ValueError(f"JWT algorithm={algorithm} 的 public_keys 必须全部是 EC 公钥: {invalid_kids}")
        return

    raise ValueError(f"JWT algorithm 必须是非对称算法: {sorted(ASYMMETRIC_JWT_ALGORITHMS)}")


def _is_production_env(env: str | None) -> bool:
    return str(env or "").strip().lower() in {"prod", "production", "main", "release"}


def _check_private_key_file_permissions(
    path: str,
    *,
    active_kid: str,
    strict: bool,
) -> None:
    if os.name == "nt":
        return
    try:
        mode = stat.S_IMODE(os.stat(path).st_mode)
    except OSError as exc:
        logger.warning("JWT private_key_path 权限检查失败: path=%s, active_kid=%s, error=%s", path, active_kid, exc)
        return

    severe_bits = stat.S_IWGRP | stat.S_IWOTH | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH
    if mode & severe_bits:
        message = f"JWT private_key_path 权限过宽: path={path}, active_kid={active_kid}, mode={oct(mode)}"
        if strict:
            raise ValueError(message)
        logger.warning("%s；非生产环境仅告警", message)
        return

    advisory_bits = stat.S_IWUSR | stat.S_IRGRP | stat.S_IROTH
    if mode & advisory_bits:
        logger.warning(
            "JWT private_key_path 建议使用只读且仅必要用户可读: path=%s, active_kid=%s, mode=%s",
            path,
            active_kid,
            oct(mode),
        )


class JwtPublicKeyConfig(BaseModel):
    """单个可用于验签的 JWT 公钥文件配置。"""

    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)

    kid: str = Field(min_length=1)
    public_key_path: str = Field(min_length=1)

    @model_validator(mode="before")
    @classmethod
    def reject_inline_or_legacy_public_key(cls, data):
        if isinstance(data, dict):
            inline_pem_path = _find_inline_pem_config_path(data, "public_keys[]")
            if inline_pem_path is not None:
                raise ValueError(f"JWT public_keys 检测到 PEM 内容字段: {inline_pem_path}；请改用 public_key_path 文件路径")
            legacy_fields = {"public_key", "key_id"}.intersection(data)
            if legacy_fields:
                raise ValueError(f"JWT public_keys 不再接受旧字段: {sorted(legacy_fields)}；请使用 kid/public_key_path")
        return data

    @field_validator("kid")
    @classmethod
    def validate_kid(cls, value: str) -> str:
        normalized = str(value or "").strip()
        if not normalized:
            raise ValueError("JWT public_keys.kid 不能为空")
        return normalized

    @field_validator("public_key_path")
    @classmethod
    def validate_public_key_path(cls, value: str) -> str:
        return _normalize_required_path(value, "public_key_path")


class JwtConfig(BaseModel):
    """短寿命 OAuth/OIDC access JWT 配置，仅从文件路径加载非对称密钥。"""

    model_config = ConfigDict(extra="forbid", hide_input_in_errors=True)

    algorithm: str = "RS256"
    active_kid: str = Field(min_length=1)
    private_key_path: str = Field(min_length=1)
    public_keys: list[JwtPublicKeyConfig] = Field(min_length=1)
    issuer: str = Field(default="kmvpy", min_length=1)
    audience: str = Field(min_length=1)
    access_token_lifetime_hours: float = Field(default=0.25, gt=0)

    _private_key: Any = PrivateAttr(default=None)
    _public_key_by_id: dict[str, Any] = PrivateAttr(default_factory=dict)

    @model_validator(mode="before")
    @classmethod
    def reject_legacy_jwt_fields(cls, data):
        if isinstance(data, dict):
            inline_pem_path = _find_inline_pem_config_path(data)
            if inline_pem_path is not None:
                raise ValueError(f"JWT 配置中检测到 PEM 内容字段: {inline_pem_path}；密钥只能通过文件路径加载")

            legacy_fields = {
                "private_key",
                "public_key",
                "key_id",
                "secret_key",
                "access_token_expire_hours",
            }.intersection(data)
            if legacy_fields:
                raise ValueError(
                    "JWT 配置不再接受内联 PEM 或旧字段；请迁移字段: "
                    f"{sorted(legacy_fields)} -> active_kid/private_key_path/public_keys[].kid/access_token_lifetime_hours"
                )
        return data

    @field_validator("algorithm")
    @classmethod
    def validate_algorithm(cls, value: str) -> str:
        normalized = str(value or "RS256").strip()
        upper = normalized.upper()
        if normalized.lower() == "none" or upper in FORBIDDEN_JWT_ALGORITHMS:
            raise ValueError("JWT algorithm 禁止使用 none 或 HS* 对称算法")
        if upper not in ASYMMETRIC_JWT_ALGORITHMS:
            raise ValueError(f"JWT algorithm 必须是非对称算法: {sorted(ASYMMETRIC_JWT_ALGORITHMS)}")
        return upper

    @field_validator("active_kid", "issuer", "audience")
    @classmethod
    def validate_non_empty_text(cls, value: str) -> str:
        normalized = str(value or "").strip()
        if not normalized:
            raise ValueError("JWT active_kid/issuer/audience 均不能为空")
        return normalized

    @field_validator("private_key_path")
    @classmethod
    def validate_private_key_path(cls, value: str) -> str:
        return _normalize_required_path(value, "private_key_path")

    @model_validator(mode="after")
    def load_and_validate_key_files(self):
        public_kids = [entry.kid for entry in self.public_keys]
        duplicate_kids = sorted({kid for kid in public_kids if public_kids.count(kid) > 1})
        if duplicate_kids:
            raise ValueError(f"JWT public_keys.kid 不允许重复: {duplicate_kids}")
        if self.active_kid not in public_kids:
            raise ValueError(f"JWT public_keys 必须包含 active_kid={self.active_kid}")

        private_key = _load_private_key_from_path(self.private_key_path)
        public_key_by_id = {
            entry.kid: _load_public_key_from_path(entry.public_key_path)
            for entry in self.public_keys
        }
        _validate_jwt_key_type(self.algorithm, private_key, public_key_by_id)

        active_public_key = public_key_by_id[self.active_kid]
        if not _public_keys_match(private_key, active_public_key):
            active_public_key_path = next(
                entry.public_key_path for entry in self.public_keys if entry.kid == self.active_kid
            )
            raise ValueError(
                "JWT active 私钥与公钥不匹配: "
                f"active_kid={self.active_kid}, "
                f"private_key_path={self.private_key_path}, public_key_path={active_public_key_path}"
            )

        self._private_key = private_key
        self._public_key_by_id = public_key_by_id
        _check_private_key_file_permissions(
            self.private_key_path,
            active_kid=self.active_kid,
            strict=False,
        )
        return self

    @property
    def access_token_lifetime_seconds(self) -> int:
        return _hours_to_seconds(self.access_token_lifetime_hours)

    def get_active_private_key(self):
        return self._private_key

    def get_public_key(self, kid: str):
        return self._public_key_by_id.get(kid)

    def require_public_key(self, kid: str):
        public_key = self.get_public_key(kid)
        if public_key is None:
            raise KeyError(kid)
        return public_key

    def iter_public_keys(self):
        for entry in self.public_keys:
            yield entry.kid, self._public_key_by_id[entry.kid]

    def validate_private_key_permissions(self, *, strict: bool) -> None:
        _check_private_key_file_permissions(
            self.private_key_path,
            active_kid=self.active_kid,
            strict=strict,
        )


class AuthSessionConfig(BaseModel):
    """Redis-backed login session 配置，用于自动续签、空闲/绝对超时与撤销。"""
    idle_timeout_hours: float = Field(default=24.0, gt=0)
    absolute_timeout_hours: float = Field(default=720.0, gt=0)
    max_sessions_per_user: Optional[int] = Field(default=None, ge=1)

    @property
    def idle_timeout_seconds(self) -> int:
        return _hours_to_seconds(self.idle_timeout_hours)

    @property
    def absolute_timeout_seconds(self) -> int:
        return _hours_to_seconds(self.absolute_timeout_hours)


class AuthJwtConfig(BaseModel):
    """单类用户的认证配置：短 access JWT + Redis 登录态 session。"""
    jwt: JwtConfig
    session: AuthSessionConfig = Field(default_factory=AuthSessionConfig)
    redis: Optional[RedisConfig] = None

    @model_validator(mode="after")
    def validate_session_requirements(self):
        if self.redis is None:
            raise ValueError("auth_config.*.redis 必须配置，否则自动续签、空闲超时和 max_sessions 无法工作")
        if self.session.absolute_timeout_hours < self.session.idle_timeout_hours:
            raise ValueError("session.absolute_timeout_hours 必须大于等于 idle_timeout_hours")
        if self.jwt.access_token_lifetime_hours >= self.session.idle_timeout_hours:
            raise ValueError("jwt.access_token_lifetime_hours 必须小于 session.idle_timeout_hours")
        return self


class AuthConfig(BaseModel):
    """认证配置，区分普通用户与管理员。"""
    user: AuthJwtConfig
    admin: AuthJwtConfig

    @model_validator(mode="after")
    def validate_role_separation(self):
        if self.user.jwt.active_kid == self.admin.jwt.active_kid:
            raise ValueError("auth_config.user.jwt.active_kid 与 admin.jwt.active_kid 必须不同")
        if self.user.jwt.audience == self.admin.jwt.audience:
            raise ValueError("auth_config.user.jwt.audience 与 admin.jwt.audience 必须不同")
        return self

    def validate_jwt_private_key_permissions(self, *, strict: bool) -> None:
        self.user.jwt.validate_private_key_permissions(strict=strict)
        self.admin.jwt.validate_private_key_permissions(strict=strict)


class DefaultAdminConfig(BaseModel):
    """
    可选：当且仅当库中尚无任何管理员账号时，用于创建首个管理员。

    管理端登录使用邮箱；配置里仅有 username 时，派生登录邮箱为
    ``{username}@default-admin.local``（username 会先去除首尾空格，邮箱本地部分为小写）。
    """

    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1)

    @field_validator("username")
    @classmethod
    def strip_username(cls, v: str) -> str:
        return v.strip()


class SnowflakeConfig(BaseModel):
    """
    KSnowflake（雪花 ID）配置。

    推荐做法：
    - 生产环境请显式配置全局唯一的 worker_id（例如通过环境变量或配置文件），以保证多实例/多进程下确定性不撞号。
    - epoch 使用 UTC（默认 2020-01-01），避免不同时区机器造成解析/排序口径不一致。
    """

    # 0..1023：建议在多实例部署中显式配置；为 None 时由 KSnowflake 内部：
    # 优先读取环境变量 KMVPY_WORKER_ID，否则用 host/mac/pid hash 兜底生成。
    worker_id: Optional[int] = Field(default=None, ge=0, le=1023)

    # 允许的最大时钟回拨（毫秒）。小幅回拨会阻塞等待，大于阈值会抛错。
    max_backwards_ms: int = Field(default=5, ge=0, le=60_000)

    # 自定义 epoch（UTC 日期），默认 2020-01-01。
    epoch_year: int = Field(default=2020, ge=1970, le=3000)
    epoch_month: int = Field(default=1, ge=1, le=12)
    epoch_day: int = Field(default=1, ge=1, le=31)

    @computed_field
    @property
    def epoch_ymd(self) -> str:
        """epoch 的 YYYY-MM-DD 形式（UTC）。"""
        return f"{self.epoch_year:04d}-{self.epoch_month:02d}-{self.epoch_day:02d}"

    def init_snowflake(self) -> None:
        """
        将配置应用到 KSnowflake（建议在应用启动阶段调用一次）。

        注意：
        - 必须在首次生成 ID 之前调用，否则 epoch 不允许再修改。
        - 如需多实例确定性唯一，请显式配置 worker_id（或设置环境变量 KMVPY_WORKER_ID）。
        """
        from kmvpy.common.infra.ksnowflake import KSnowflake

        KSnowflake.set_custom_epoch(
            self.epoch_year, self.epoch_month, self.epoch_day)

        # 若单例尚未创建或尚未生成过 ID，则按配置创建/替换单例实例。
        inst = getattr(KSnowflake, "_instance", None)
        if inst is None or getattr(inst, "last_timestamp", -1) == -1:
            KSnowflake._instance = KSnowflake(
                worker_id=self.worker_id, max_backwards_ms=self.max_backwards_ms)


# ---------------------------
# 顶层配置模型
# ---------------------------
T = TypeVar('T', bound='BaseConfig')


class BaseConfig(BaseModel):
    general: GeneralConfig
    logging: LoggingConfig
    service: Optional[ServiceConfig] = None
    i18n: Optional[I18nConfig] = None
    default_storage: Optional[DefaultStorageConfig] = None
    # 兼容旧工程的顶层 database / redis；新工程应优先使用 default_storage。
    database: Optional[DatabaseConfig] = None
    redis: Optional[RedisConfig] = None
    proxies: Optional[ProxiesConfig] = None
    auth_config: Optional[AuthConfig] = None
    default_admin: Optional[DefaultAdminConfig] = None
    snowflake: SnowflakeConfig = Field(default_factory=SnowflakeConfig)

    @property
    def timezone(self) -> str:
        return self.general.timezone

    @model_validator(mode="after")
    def validate_auth_security_runtime(self):
        if self.auth_config is not None:
            self.auth_config.validate_jwt_private_key_permissions(
                strict=_is_production_env(self.general.env),
            )
        return self

    def get_default_storage_database_config(self) -> Optional[DatabaseConfig]:
        if self.default_storage is not None:
            return self.default_storage.database
        return self.database

    def get_default_storage_redis_config(self) -> Optional[RedisConfig]:
        if self.default_storage is not None:
            return self.default_storage.redis
        return self.redis

    @classmethod
    def load_config(cls, file_path: Union[str, Path]) -> T:
        """
        从YAML文件加载配置
        自动返回调用类的实例，子类无需重新实现
        """
        file_path = Path(file_path)  # 统一转换为Path对象

        with open(file_path, "r", encoding="utf-8") as f:
            try:
                yaml_data = yaml.safe_load(f) or {}
            except yaml.YAMLError as e:
                raise ValueError(f"YAML解析错误: {e}")

            _resolve_auth_key_paths_relative_to_config(yaml_data, file_path.parent)
            return cls(**yaml_data)

    def init_logger(self,
                    package: str,
                    _format: str = '%(asctime)s - %(levelname)s - 进程%(process)d:线程%(thread)d - %(filename)s:%('
                                   'funcName)s:%(lineno)d: %(message)s') -> None:
        # 创建一个logger
        logger.setLevel(self.logging.level)

        # 日志格式
        formatter = logging.Formatter(fmt=_format)

        # Debug模式不输出日志文件
        if self.general.debug:
            console_handler = logging.StreamHandler(sys.stdout)
            console_handler.setFormatter(formatter)
            logger.addHandler(console_handler)
        else:
            # 如果logger_path为None或者为空字符串，使用当前目录
            if not self.logging.path or len(self.logging.path) == 0:
                logger_path = os.path.join(os.getcwd(), f"{package}.log")
            else:
                logger_path = os.path.join(self.logging.path, f"{package}.log")

            # 确保日志文件所在的目录存在
            os.makedirs(os.path.dirname(logger_path), exist_ok=True)

            # 创建并设置文件handler
            file_handler = logging.FileHandler(logger_path, encoding='utf-8')
            file_handler.setFormatter(formatter)
            logger.addHandler(file_handler)

    def load_i18n(self):
        """
        国际化i18n
        """
        if self.i18n is None:
            return
        i18n.load_path.append(self.i18n.path)
        i18n.set('file_format', 'json')
        i18n.set('enable_memoization', True)
        # i18n.set('filename_format', '{locale}.{format}')
        i18n.set('skip_locale_root_data', True)
        i18n.set('locale', self.i18n.locale)
