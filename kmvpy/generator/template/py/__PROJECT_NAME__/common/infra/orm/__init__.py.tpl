
# coding: utf-8
"""
数据库表初始化模块
"""

import hashlib
import secrets
from collections.abc import Callable
from typing import Any

from kmvpy.common.infra import init_tables_by_orms
from kmvpy.common.infra.korm_base import KOrmBase
from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.tool.logger import logger
from sqlalchemy import (
    BigInteger,
    Integer,
    MetaData,
    Table,
    func,
    inspect as sa_inspect,
    select,
)
from sqlalchemy.dialects.mysql import BIGINT as MYSQL_BIGINT
from sqlalchemy.exc import IntegrityError

from __PROJECT_NAME__.common.conf import AppConfig
from __PROJECT_NAME__.common.dependencies.auth import UserType
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage

# 公共类型定义
BIGINT_TYPE = BigInteger().with_variant(MYSQL_BIGINT(unsigned=True), "mysql")
AUTO_INCREMENT_PK_TYPE = BIGINT_TYPE.with_variant(Integer, "sqlite")

from .kv_conf import KvConf
from .admin_op_log import AdminOperationLog
from .user_base import UserBase
from .user_socket_message import UserSocketMessage
from .user_tree import UserTree
from .work_ticket import WorkTicket
from .work_ticket_message import WorkTicketMessage


_REGISTERED_ORM_MODELS: list[type[KOrmBase]] = [
    KvConf,
    UserBase,
    UserTree,
    AdminOperationLog,
    WorkTicket,
    WorkTicketMessage,
    UserSocketMessage,
]


def registered_orm_models() -> list[type[KOrmBase]]:
    """Return ORM models managed by project table initialization."""
    return list(_REGISTERED_ORM_MODELS)


def registered_orm_model_by_table_name(table_name: str) -> type[KOrmBase] | None:
    normalized = table_name.strip()
    if not normalized:
        return None
    for model in _REGISTERED_ORM_MODELS:
        if getattr(model, "__tablename__", None) == normalized:
            return model
    return None


async def init_tables():
    """
    初始化数据库表

    功能：
    1. 如果表不存在，则创建表
    2. 如果表已存在，检查表结构是否一致
    3. 如果不一致，更新表结构（添加新列、修改列、删除废弃列）
    4. 同步索引信息
    5. 尽量保证数据一致性

    Args:
        storage: 已初始化完成的 KOrmStorage 实例
    """
    try:
        storage = DefaultStorage.instance()
        await init_tables_by_orms(
            storage,
            _REGISTERED_ORM_MODELS,
        )
    except Exception as e:
        logger.error(f"初始化数据库表时出错: {str(e)}", exc_info=True)
        raise


def _savepoint_call(
    sync_conn,
    description: str,
    action: Callable[[], Any],
    default: Any,
) -> Any:
    """在 SAVEPOINT 内执行可能失败的内省语句。

    PostgreSQL 中任一语句失败都会把当前事务标记为 aborted，此后同一事务内的
    其它语句一律被拒绝（InFailedSQLTransactionError）。因此单表读取失败必须
    回滚到保存点，才能在跳过该表后继续读取其余表，而不是让整次内省失败。
    """
    savepoint = sync_conn.begin_nested()
    try:
        result = action()
    except Exception as exc:  # noqa: BLE001
        logger.warning("%s 失败: %s", description, exc)
        # 必须显式 ROLLBACK TO SAVEPOINT，才能让 PostgreSQL 事务脱离 aborted 状态。
        try:
            savepoint.rollback()
        except Exception as rollback_exc:  # noqa: BLE001
            logger.warning("%s 回滚保存点失败: %s", description, rollback_exc)
        return default
    savepoint.commit()
    return result


def _table_row_count(sync_conn, table_name: str) -> int | None:
    def _count() -> int:
        table = Table(table_name, MetaData(), autoload_with=sync_conn)
        return int(
            sync_conn.execute(select(func.count()).select_from(table)).scalar_one()
        )

    return _savepoint_call(sync_conn, f"读取表 {table_name} 行数", _count, None)


def _table_comment(sync_conn, inspector, table_name: str) -> str | None:
    comment = _savepoint_call(
        sync_conn,
        f"读取表 {table_name} 注释",
        lambda: inspector.get_table_comment(table_name),
        None,
    )
    text_value = comment.get("text") if isinstance(comment, dict) else None
    return text_value if isinstance(text_value, str) and text_value else None


def _table_structure(
    sync_conn,
    inspector,
    table_name: str,
) -> dict[str, Any]:
    """读取单表列、主键、索引与唯一约束；失败时返回降级结构。"""

    def _collect() -> dict[str, Any]:
        columns = inspector.get_columns(table_name)
        pk_constraint = inspector.get_pk_constraint(table_name) or {}
        pk_column_names = [
            str(name)
            for name in pk_constraint.get("constrained_columns") or []
            if name
        ]
        pk_columns = set(pk_column_names)
        pk_name = str(pk_constraint.get("name") or "PRIMARY")
        index_columns: set[str] = set()
        unique_columns: set[str] = set()
        # 索引清单与列上的 indexed/unique 标记来自同一次内省，不额外建连。
        indexes: list[dict[str, Any]] = []
        if pk_column_names:
            indexes.append(
                {
                    "name": pk_name,
                    "columns": pk_column_names,
                    "unique": True,
                    "primary": True,
                }
            )
        for index in inspector.get_indexes(table_name):
            index_name = str(index.get("name") or "")
            names = [str(name) for name in index.get("column_names") or [] if name]
            index_columns.update(names)
            if index.get("unique"):
                unique_columns.update(names)
            # MySQL 会把主键作为 PRIMARY 索引一并返回，避免与上面条目重复。
            if not names or index_name == pk_name:
                continue
            indexes.append(
                {
                    "name": index_name,
                    "columns": names,
                    "unique": bool(index.get("unique")),
                    "primary": False,
                }
            )
        for unique_constraint in inspector.get_unique_constraints(table_name):
            unique_columns.update(
                str(name)
                for name in unique_constraint.get("column_names") or []
                if name
            )

        return {
            "table_name": table_name,
            "comment": _table_comment(sync_conn, inspector, table_name),
            "row_count": _table_row_count(sync_conn, table_name),
            "columns": [
                {
                    "name": str(column.get("name", "")),
                    "type": str(column.get("type", "")),
                    "nullable": bool(column.get("nullable", True)),
                    "primary_key": str(column.get("name", "")) in pk_columns,
                    "indexed": str(column.get("name", "")) in index_columns,
                    "unique": str(column.get("name", "")) in unique_columns,
                }
                for column in columns
            ],
            "indexes": indexes,
        }

    fallback = {
        "table_name": table_name,
        "comment": None,
        "row_count": None,
        "columns": [],
        "indexes": [],
    }
    return _savepoint_call(
        sync_conn,
        f"读取表 {table_name} 结构",
        _collect,
        fallback,
    )


def _inspect_database_tables(
    sync_conn,
    registered_table_names: set[str],
) -> list[dict[str, Any]]:
    inspector = sa_inspect(sync_conn)
    tables: list[dict[str, Any]] = []
    for table_name in sorted(inspector.get_table_names()):
        structure = _table_structure(sync_conn, inspector, table_name)
        tables.append(
            {
                **structure,
                "registered": table_name in registered_table_names,
            }
        )
    return tables


async def inspect_database_tables(
    storage: KOrmStorage | None = None,
) -> list[dict[str, Any]]:
    target_storage = storage or DefaultStorage.instance()
    if not target_storage.has_db_session():
        target_storage.init_db_session()
    registered_table_names = {
        str(model.__tablename__) for model in registered_orm_models()
    }
    async with target_storage.engine.connect() as conn:
        return await conn.run_sync(_inspect_database_tables, registered_table_names)


def _drop_database_table(sync_conn, table_name: str) -> bool:
    inspector = sa_inspect(sync_conn)
    if not inspector.has_table(table_name):
        return False
    table = Table(table_name, MetaData(), autoload_with=sync_conn)
    table.drop(sync_conn, checkfirst=True)
    return True


async def drop_database_table(
    table_name: str,
    storage: KOrmStorage | None = None,
) -> bool:
    target_storage = storage or DefaultStorage.instance()
    if not target_storage.has_db_session():
        target_storage.init_db_session()
    async with target_storage.engine.begin() as conn:
        return await conn.run_sync(_drop_database_table, table_name)


async def regenerate_database_table(
    table_name: str,
    storage: KOrmStorage | None = None,
) -> bool:
    model = registered_orm_model_by_table_name(table_name)
    if model is None:
        return False

    target_storage = storage or DefaultStorage.instance()
    await init_tables_by_orms(target_storage, [model])
    return True


def _bootstrap_admin_password_hash(password: str, salt: str) -> str:
    return hashlib.sha256(f"{password}:{salt}".encode("utf-8")).hexdigest()


async def init_default_admin_if_needed(config: AppConfig) -> None:
    """
    若配置了 default_admin，且当前库中尚无任何管理员，则创建首个管理员。

    登录邮箱为 ``{username}@default-admin.local``，与 AdminOpService 邮箱登录一致。
    """
    if config.default_admin is None:
        return
    if config.get_default_storage_database_config() is None:
        return

    db = DefaultStorage.instance()
    existing_admin = await db.get_by_condition(
        UserBase, user_type=int(UserType.ADMIN))
    if existing_admin is not None:
        return

    admin_cfg = config.default_admin
    login_email = f"{admin_cfg.username.lower()}@default-admin.local"
    username = admin_cfg.username
    if await db.get_by_condition(UserBase, email=login_email) is not None:
        logger.warning(
            "已存在邮箱 %s，跳过 default_admin 初始化", login_email)
        return
    if await db.get_by_condition(UserBase, username=username) is not None:
        logger.warning(
            "已存在用户名 %s，跳过 default_admin 初始化", username)
        return

    salt = secrets.token_hex(16)
    password_hash = _bootstrap_admin_password_hash(admin_cfg.password, salt)
    user_kid = UserBase.gen_kid()

    async with db.session_scope() as session:
        user = UserBase(
            kid=user_kid,
            username=username,
            email=login_email,
            nickname=username[:32],
            salt=salt,
            password=password_hash,
            user_type=int(UserType.ADMIN),
            state=1,
            ip=None,
            deviceid=None,
        )
        session.add(user)
        user_tree = UserTree(
            kid=user_kid,
            invitation_code=UserTree._snowflake.gen_base36_for_int(user_kid),
            p1_kid=None,
            p2_kid=None,
            p3_kid=None,
            p4_kid=None,
            p5_kid=None,
            p6_kid=None,
            p7_kid=None,
            p8_kid=None,
            p9_kid=None,
        )
        session.add(user_tree)
        try:
            await session.flush()
        except IntegrityError as exc:
            logger.warning(
                "default_admin 写入失败（可能并发创建或唯一约束冲突）: username=%s",
                username,
                exc_info=exc,
            )
            return

    logger.info(
        "已按 default_admin 创建首个管理员，登录邮箱: %s", login_email)
