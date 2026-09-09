# coding: utf-8
"""
数据库表初始化模块
"""
import inspect
import re
from typing import Any, List, Type, cast

from kmvpy.common.infra.korm_base import KOrmBase
from kmvpy.common.infra.korm_storage import (
    KOrmStorage,
    _build_mysql_connect_args,
    _build_postgresql_connect_args,
)
from kmvpy.common.tool.logger import logger
from sqlalchemy import inspect as sql_inspect, text
from sqlalchemy.engine import Connection, make_url
from sqlalchemy.ext.asyncio import create_async_engine
from sqlalchemy.schema import CreateColumn

def _quote_identifier(conn: Connection, name: str) -> str:
    return conn.dialect.identifier_preparer.quote_identifier(name)


def _quote_database_name(backend_name: str, database_name: str) -> str:
    if backend_name == "mysql":
        return f"`{database_name.replace('`', '``')}`"
    if backend_name == "postgresql":
        return f'"{database_name.replace(chr(34), chr(34) * 2)}"'
    raise ValueError(f"Unsupported database backend: {backend_name}")


def _is_database_missing_error(exc: Exception, backend_name: str) -> bool:
    error_text = " ".join(
        str(part).lower() for part in (exc, getattr(exc, "orig", None)) if part
    )
    if backend_name == "mysql":
        return "unknown database" in error_text or "1049" in error_text
    if backend_name == "postgresql":
        return (
            "3d000" in error_text
            or "invalid_catalog_name" in error_text
            or ("database" in error_text and "does not exist" in error_text)
        )
    return False


async def _ensure_database_exists(
    db_config: Any,
    connect_error: Exception,
    timezone: str,
) -> bool:
    sqlalchemy_url = make_url(db_config.url)
    backend_name = sqlalchemy_url.get_backend_name().lower()
    database_name = (sqlalchemy_url.database or "").strip()
    if not database_name or not _is_database_missing_error(connect_error, backend_name):
        return False

    if backend_name == "mysql":
        admin_url = sqlalchemy_url.set(database=None)
    elif backend_name == "postgresql":
        admin_url = sqlalchemy_url.set(database="postgres")
    else:
        logger.warning("Auto create database is not supported for dialect=%s", backend_name)
        return False

    logger.warning("Database %s does not exist, attempting auto-create", database_name)

    engine_kwargs: dict[str, Any] = {
        "echo": db_config.echo,
        "pool_pre_ping": True,
    }
    connect_args: dict[str, Any] = {}
    driver_name = sqlalchemy_url.get_driver_name().lower()
    if backend_name == "mysql":
        connect_args.update(_build_mysql_connect_args(db_config, timezone))
    elif backend_name == "postgresql":
        connect_args.update(
            _build_postgresql_connect_args(db_config, driver_name, timezone)
        )
        engine_kwargs["isolation_level"] = "AUTOCOMMIT"

    if connect_args:
        engine_kwargs["connect_args"] = connect_args

    admin_engine = create_async_engine(
        admin_url.render_as_string(hide_password=False),
        **engine_kwargs,
    )
    try:
        async with admin_engine.connect() as conn:
            if backend_name == "postgresql":
                exists = await conn.scalar(
                    text("SELECT 1 FROM pg_database WHERE datname = :db_name"),
                    {"db_name": database_name},
                )
                if exists:
                    logger.info("Database already exists: %s", database_name)
                    return True

            create_database_sql = (
                f"CREATE DATABASE IF NOT EXISTS {_quote_database_name(backend_name, database_name)}"
                if backend_name == "mysql"
                else f"CREATE DATABASE {_quote_database_name(backend_name, database_name)}"
            )
            await conn.execute(text(create_database_sql))
        logger.info("Database created: %s", database_name)
        return True
    finally:
        await admin_engine.dispose()


def _table_exists(conn: Connection, table_name: str) -> bool:
    """
    检查表是否存在

    Args:
        conn: 数据库连接
        table_name: 表名

    Returns:
        bool: 表是否存在
    """
    inspector = sql_inspect(conn)
    return table_name in inspector.get_table_names()


def _get_table_columns(conn: Connection, table_name: str) -> dict:
    """
    获取表的列信息

    Args:
        conn: 数据库连接
        table_name: 表名

    Returns:
        dict: 列名到列信息的映射
    """
    inspector = sql_inspect(conn)
    columns = inspector.get_columns(table_name)
    return {col['name']: col for col in columns}


def _table_has_rows(conn: Connection, table_name: str) -> bool:
    quoted_table_name = _quote_identifier(conn, table_name)
    return bool(conn.execute(text(f"SELECT 1 FROM {quoted_table_name} LIMIT 1")).first())


def _compile_add_column_clause(conn: Connection, model_col: Any, allow_nullable_fallback: bool) -> str:
    compiled = str(CreateColumn(model_col).compile(
        dialect=conn.dialect)).strip()
    if allow_nullable_fallback:
        compiled = re.sub(r"\s+NOT NULL\b", "", compiled,
                          count=1, flags=re.IGNORECASE)
    return compiled


def _apply_postgresql_column_comment(
    conn: Connection,
    table_name: str,
    column_name: str,
    comment: str | None,
) -> None:
    if conn.dialect.name != "postgresql" or not comment:
        return

    quoted_table_name = _quote_identifier(conn, table_name)
    quoted_column_name = _quote_identifier(conn, column_name)
    escaped_comment = comment.replace("'", "''")
    conn.execute(
        text(
            f"COMMENT ON COLUMN {quoted_table_name}.{quoted_column_name} IS '{escaped_comment}'")
    )


def _get_table_indexes(conn: Connection, table_name: str) -> dict:
    """
    获取表的索引信息

    Args:
        conn: 数据库连接
        table_name: 表名

    Returns:
        dict: 索引名到索引信息的映射
    """
    inspector = sql_inspect(conn)
    indexes = inspector.get_indexes(table_name)
    return {idx['name']: idx for idx in indexes}


def _get_table_foreign_keys(conn: Connection, table_name: str) -> dict:
    """
    获取表的外键信息

    Args:
        conn: 数据库连接
        table_name: 表名

    Returns:
        dict: 外键名到外键信息的映射
    """
    inspector = sql_inspect(conn)
    foreign_keys = inspector.get_foreign_keys(table_name)
    return {fk['name']: fk for fk in foreign_keys}


def _ensure_table_indexes_generic(conn: Connection, model: Type[KOrmBase]) -> None:
    """
    通用索引确保：对模型声明的 Index 执行 create(checkfirst=True)。

    说明：
    - 该逻辑跨方言工作（PostgreSQL/MySQL/SQLite 等）。
    - 不做“删除废弃索引”，也不尝试跨方言 ALTER COLUMN。
    """
    for index in model.__table__.indexes:
        try:
            index.create(bind=conn, checkfirst=True)
        except Exception as e:
            logger.warning(f"Index create failed: {index.name}: {str(e)}")


def _sync_table_structure_generic(conn: Connection, model: Type[KOrmBase]) -> None:
    """
    非 MySQL 的通用结构同步：
    1. 表不存在时自动建表；
    2. ORM 新增字段时自动补列，并尽量保留默认值；
    3. 数据库存在 ORM 未声明字段时仅告警，不自动删除。
    """
    table_name = cast(str, model.__tablename__)
    model_table = cast(Any, getattr(model, "__table__"))

    if not _table_exists(conn, table_name):
        logger.info(f"Create table: {table_name}")
        model_table.create(conn, checkfirst=True)
        _ensure_table_indexes_generic(conn, model)
        logger.info(f"Table created: {table_name}")
        return

    db_columns = _get_table_columns(conn, table_name)
    db_column_names = set(db_columns.keys())
    model_column_names = set(model_table.columns.keys())

    columns_to_add = sorted(model_column_names - db_column_names)
    columns_to_drop = sorted(db_column_names - model_column_names)

    has_rows = False
    if columns_to_add:
        has_rows = _table_has_rows(conn, table_name)

    quoted_table_name = _quote_identifier(conn, table_name)

    for col_name in columns_to_add:
        model_col = model_table.columns[col_name]
        needs_nullable_fallback = bool(
            has_rows and model_col.nullable is False and model_col.server_default is None
        )
        add_column_clause = _compile_add_column_clause(
            conn, model_col, needs_nullable_fallback)
        logger.info(f"Add column: {table_name}.{col_name}")
        conn.execute(
            text(f"ALTER TABLE {quoted_table_name} ADD COLUMN {add_column_clause}"))
        _apply_postgresql_column_comment(
            conn, table_name, col_name, model_col.comment)

        if needs_nullable_fallback:
            logger.warning(
                "%s.%s added as NULL; backfill data, then set NOT NULL manually.",
                table_name,
                col_name,
            )

    # 日志提示待删除废弃的列（谨慎操作，确保数据安全）
    if columns_to_drop:
        drop_column_clauses = ", ".join(
            f"DROP COLUMN {_quote_identifier(conn, col_name)}"
            for col_name in columns_to_drop
        )
        logger.warning(
            "Extra DB columns: ALTER TABLE %s %s;",
            quoted_table_name,
            drop_column_clauses,
        )

    _ensure_table_indexes_generic(conn, model)

    if columns_to_add or columns_to_drop:
        logger.info(f"Table synced: {table_name}")
    else:
        logger.info(f"Table up to date: {table_name}")


def _sync_table_structure_mysql(conn: Connection, model: Type[KOrmBase]) -> None:
    """
    同步表结构（MySQL 专用）：如果表不存在则创建，如果存在则更新结构。

    Args:
        conn: 数据库连接
        model: ORM 模型类
    """
    table_name = model.__tablename__
    model_table = model.__table__

    if not _table_exists(conn, table_name):
        # 表不存在，直接创建（包括索引）
        logger.info(f"Create table: {table_name}")
        model_table.create(conn, checkfirst=True)
        # 创建索引
        _sync_table_indexes_mysql(conn, model)
        logger.info(f"Table created: {table_name}")
        return

    # 获取数据库中的列信息
    db_columns = _get_table_columns(conn, table_name)
    db_column_names = set(db_columns.keys())

    # 获取模型定义的列信息
    model_column_names = set(model_table.columns.keys())

    # 找出需要添加的列
    columns_to_add = sorted(model_column_names - db_column_names)
    # 找出需要删除的列（废弃的列）
    columns_to_drop = sorted(db_column_names - model_column_names)

    # 检查现有列是否需要修改
    columns_to_modify = []
    for col_name in model_column_names & db_column_names:
        model_col = model_table.columns[col_name]
        db_col = db_columns[col_name]

        # 检查列类型、是否可空、默认值等是否一致
        # 这里简化处理，只检查类型和可空性
        model_type = str(model_col.type)
        db_type = str(db_col['type'])

        # 类型比较（简化版，实际可能需要更复杂的比较）
        if model_type != db_type or model_col.nullable != db_col['nullable']:
            columns_to_modify.append(col_name)

    quoted_table_name = _quote_identifier(conn, table_name)
    has_rows = False
    if columns_to_add:
        has_rows = _table_has_rows(conn, table_name)

    # 执行变更
    # 添加新列
    for col_name in columns_to_add:
        col = model_table.columns[col_name]
        needs_nullable_fallback = bool(
            has_rows and col.nullable is False and col.server_default is None
        )
        add_column_clause = _compile_add_column_clause(
            conn, col, needs_nullable_fallback)
        logger.info(f"Add column: {table_name}.{col_name}")
        conn.execute(
            text(f"ALTER TABLE {quoted_table_name} ADD COLUMN {add_column_clause}"))

        if needs_nullable_fallback:
            logger.warning(
                "%s.%s added as NULL; backfill data, then set NOT NULL manually.",
                table_name,
                col_name,
            )

    # 修改现有列
    for col_name in columns_to_modify:
        col = model_table.columns[col_name]
        modify_column_clause = _compile_add_column_clause(conn, col, False)
        logger.info(f"Modify column: {table_name}.{col_name}")
        conn.execute(
            text(f"ALTER TABLE {quoted_table_name} MODIFY COLUMN {modify_column_clause}"))

    # 日志提示待删除废弃的列（谨慎操作，确保数据安全）
    if columns_to_drop:
        drop_column_clauses = ", ".join(
            f"DROP COLUMN {_quote_identifier(conn, col_name)}"
            for col_name in columns_to_drop
        )
        logger.warning(
            "Extra DB columns: ALTER TABLE %s %s;",
            quoted_table_name,
            drop_column_clauses,
        )

    # 同步索引
    _sync_table_indexes_mysql(conn, model)

    if columns_to_add or columns_to_modify or columns_to_drop:
        logger.info(f"Table synced: {table_name}")
    else:
        logger.info(f"Table up to date: {table_name}")


def _sync_table_indexes_mysql(conn: Connection, model: Type[KOrmBase]) -> None:
    """
    同步表的索引（MySQL 专用）

    Args:
        conn: 数据库连接
        model: ORM 模型类
    """
    table_name = model.__tablename__
    model_table = model.__table__
    quoted_table_name = _quote_identifier(conn, table_name)

    # 获取数据库中的索引
    db_indexes = _get_table_indexes(conn, table_name)
    db_index_names = set(db_indexes.keys())

    # 获取模型定义的所有索引（包括显式定义的索引和列上的 index/unique）
    model_indexes = {}

    # 1. 处理显式定义的索引
    for index in model_table.indexes:
        index_name = index.name if index.name else f"idx_{table_name}_{'_'.join([c.name for c in index.columns])}"
        model_indexes[index_name] = {
            'index': index,
            'columns': [col.name for col in index.columns],
            'unique': index.unique
        }

    # 2. 处理列上的 index=True 和 unique=True
    for column in model_table.columns:
        # unique=True 会创建唯一索引
        if column.unique:
            # 检查是否已有显式索引
            index_name = f"{table_name}_{column.name}_unique"
            if index_name not in model_indexes:
                model_indexes[index_name] = {
                    'index': None,
                    'columns': [column.name],
                    'unique': True
                }
        # index=True 会创建普通索引
        elif hasattr(column, 'index') and column.index:
            index_name = f"{table_name}_{column.name}_idx"
            if index_name not in model_indexes:
                model_indexes[index_name] = {
                    'index': None,
                    'columns': [column.name],
                    'unique': False
                }

    model_index_names = set(model_indexes.keys())

    # 找出需要添加的索引
    indexes_to_add = model_index_names - db_index_names
    # 找出需要删除的索引（废弃的索引，但要排除主键）
    indexes_to_drop = db_index_names - model_index_names

    # 添加新索引
    for index_name in indexes_to_add:
        index_info = model_indexes[index_name]
        logger.info(f"Add index: {table_name}.{index_name}")
        # 生成创建索引的 SQL
        columns = ', '.join([f"`{col}`" for col in index_info['columns']])
        unique = "UNIQUE " if index_info['unique'] else ""
        create_index_sql = f"CREATE {unique}INDEX `{index_name}` ON `{table_name}` ({columns})"
        try:
            conn.execute(text(create_index_sql))
        except Exception as e:
            logger.warning(f"Index create failed: {index_name}: {str(e)}")

    # 删除废弃的普通索引
    droppable_indexes: list[str] = []
    for index_name in sorted(indexes_to_drop):
        # 跳过主键索引和唯一约束（unique constraint）
        if index_name == 'PRIMARY' or index_name.startswith('PRIMARY'):
            continue
        # 检查是否是唯一约束（MySQL 中 unique 约束也是索引）
        db_index = db_indexes.get(index_name, {})
        if db_index.get('unique', False):
            # 跳过唯一约束，因为它们可能对应 unique=True 的列
            continue
        droppable_indexes.append(index_name)

    deleted_indexes: list[str] = []
    for index_name in droppable_indexes:
        quoted_index_name = _quote_identifier(conn, index_name)
        drop_index_sql = (
            f"ALTER TABLE {quoted_table_name} DROP INDEX {quoted_index_name}"
        )
        try:
            conn.execute(text(drop_index_sql))
            deleted_indexes.append(index_name)
        except Exception as e:
            logger.warning(
                f"Index drop failed: {table_name}.{index_name}: {str(e)}")

    if deleted_indexes:
        logger.info(
            "Dropped DB indexes: %s",
            ", ".join(
                f"{table_name}.{index_name}" for index_name in deleted_indexes),
        )


async def init_tables_by_orms(
    storage: KOrmStorage,
    orm_package_or_models: List[Type[KOrmBase]],
):
    """
    初始化数据库表

    功能：
    1. 如果表不存在，则创建表
    2. 如果表已存在，检查表结构是否一致
    3. 新增字段时自动补列，并尽量保留 ORM 中声明的默认值
    4. 检测到数据库字段多于 ORM 声明时，仅输出明确警告，不自动删除；废弃的普通索引会自动删除
    5. 同步新增索引，并尽量保证数据一致性

    Args:
        storage: 已初始化完成的 KOrmStorage 实例（或其子类实例）
        orm_package_or_models: ORM 模型类列表（调用方只需传入要初始化的表结构）。
    """
    try:
        if not storage:
            raise ValueError("KOrmStorage 实例不存在")
        if not isinstance(storage, KOrmStorage):
            raise TypeError("storage 必须是 KOrmStorage 或其子类实例")

        db_config = storage.database_config
        if not db_config:
            raise ValueError("数据库配置不存在")
        if not db_config.url:
            raise ValueError("数据库 URL 为空")

        # 确保 AsyncEngine 已初始化（运行态由 infra/storage 托管）
        if not storage.has_db_session():
            storage.init_db_session()
        engine = storage.engine

        # 测试数据库连接（异步）
        try:
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        except Exception as e:
            created = await _ensure_database_exists(db_config, e, storage.timezone)
            if not created:
                raise
            await engine.dispose()
            async with engine.connect() as conn:
                await conn.execute(text("SELECT 1"))
        logger.info("DB connected")

        # 校验并去重 ORM 模型列表
        if isinstance(orm_package_or_models, (str, bytes)) or not isinstance(orm_package_or_models, list):
            raise ValueError("orm_package_or_models 必须是 ORM 模型类列表")

        models: List[Type[KOrmBase]] = []
        for model in orm_package_or_models:
            if not inspect.isclass(model) or not issubclass(model, KOrmBase) or model is KOrmBase:
                raise ValueError("ORM 模型列表中存在无效项，必须全部为继承自 KOrmBase 的模型类")
            if not hasattr(model, "__tablename__"):
                raise ValueError(f"ORM 模型 {model} 缺少 __tablename__ 声明")
            if model not in models:
                models.append(model)

        logger.info(
            f"Input models: {len(models)} {[model.__tablename__ for model in models]}")
        if not models:
            logger.warning("No ORM models found")
            return

        dialect_name = engine.dialect.name.lower()
        logger.info(f"Init {len(models)} ORM models (dialect={dialect_name})")

        async with engine.begin() as aconn:
            for model in models:
                try:
                    if dialect_name == "mysql":
                        await aconn.run_sync(_sync_table_structure_mysql, model)
                    else:
                        await aconn.run_sync(_sync_table_structure_generic, model)
                except Exception as e:
                    logger.error(
                        f"Table init failed: {model.__tablename__}: {str(e)}", exc_info=True)
                    raise

        logger.info("Table init done")

    except Exception as e:
        logger.error(f"DB init failed: {str(e)}", exc_info=True)
        raise
