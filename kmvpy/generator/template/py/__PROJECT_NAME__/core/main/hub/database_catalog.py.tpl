# coding: utf-8
"""管理端数据库目录识别业务规则。

配置文件中只声明一个业务数据库，因此这里不再枚举数据库服务上的其它库，
只在默认连接上读取该库的表清单与 ORM 注册情况。
"""

from typing import Any

from kmvpy.common.exception.kmv_exception import KmvException
from kmvpy.common.tool.logger import logger

from __PROJECT_NAME__.common.conf import get_app_config
from __PROJECT_NAME__.common.exception import database_table_errors as database_table_exc
from __PROJECT_NAME__.common.infra.database.connection import (
    database_name_of,
    describe_database_url,
)
from __PROJECT_NAME__.common.infra.database.inspection import read_database_table_names
from __PROJECT_NAME__.common.infra.orm import registered_orm_models
from __PROJECT_NAME__.common.infra.storage.default_storage import DefaultStorage


class DatabaseCatalogHub:
    """按配置文件中声明的数据库读取表清单，并关联 ORM 注册情况。"""

    # 侧边菜单只展示少量表名预览，完整清单走 tables 接口。
    _PREVIEW_LIMIT = 6

    @staticmethod
    def configured_database() -> str:
        """从应用配置中解析唯一允许操作的数据库名。

        数据库名以 default_storage.database.url 为唯一权威来源；配置缺失或
        无法解析出库名时直接失败，绝不回退成枚举数据库服务的其它库。
        """
        try:
            config = get_app_config()
            database_config = config.get_default_storage_database_config()
        except Exception as exc:  # noqa: BLE001
            logger.warning("读取数据库配置失败: %s", exc, exc_info=exc)
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            ) from exc

        database_name = database_name_of(database_config)
        if not database_name:
            logger.warning("数据库配置未指定数据库名，无法确定允许操作的数据库")
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            )
        return database_name

    @classmethod
    def ensure_allowed_database(cls, database: str | None) -> str:
        """校验目标数据库是否为配置声明的数据库，返回最终使用的库名。

        空值表示“使用配置库”。其它名称必须与配置库完全一致（区分大小写），
        即使主机、账号、密码相同也不允许切换到配置文件之外的数据库。
        """
        allowed = cls.configured_database()
        target = (database or "").strip()
        if not target or target == allowed:
            return allowed
        logger.warning(
            "拒绝操作配置文件之外的数据库 target=%s allowed=%s",
            target,
            allowed,
        )
        raise KmvException(error=database_table_exc.DATABASE_SCOPE_FORBIDDEN_ERROR)

    @staticmethod
    def _registered_table_names() -> set[str]:
        names: set[str] = set()
        for model in registered_orm_models():
            table_name = getattr(model, "__tablename__", None)
            if table_name:
                names.add(str(table_name))
        return names

    @classmethod
    async def _current_table_names(cls) -> list[str]:
        """只在默认连接上读取当前库表名，不建立任何临时连接。"""
        storage = DefaultStorage.instance()
        if not storage.has_db_session():
            storage.init_db_session()
        try:
            return await read_database_table_names(storage)
        except KmvException:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.warning("读取数据库表清单失败: %s", exc, exc_info=exc)
            raise KmvException(
                error=database_table_exc.DATABASE_CONNECTION_INVALID_ERROR
            ) from exc

    @classmethod
    async def list_table_names(cls, database: str) -> dict[str, Any]:
        """读取配置库的全部表名，并标注 ORM 注册情况。"""
        scope_name = cls.ensure_allowed_database(database)
        table_names = await cls._current_table_names()
        registered_names = cls._registered_table_names()
        items = [
            {"name": name, "registered": name in registered_names}
            for name in table_names
        ]
        return {"database": scope_name, "items": items, "total": len(items)}

    @classmethod
    async def build_catalog(cls) -> dict[str, Any]:
        """返回配置库的目录信息（含表数量与 ORM 注册数）。

        结果恒为一条：配置文件声明的数据库。不再枚举同一服务上的其它库。
        """
        scope_name = cls.ensure_allowed_database(None)
        storage = DefaultStorage.instance()
        if not storage.has_db_session():
            storage.init_db_session()

        database_config = storage.database_config
        info = describe_database_url(database_config.url if database_config else "")
        dialect = str(info["dialect"] or storage.engine.dialect.name)

        table_names = await cls._current_table_names()
        registered_names = cls._registered_table_names()
        registered_count = len(registered_names.intersection(table_names))

        return {
            "server": {
                "dialect": dialect,
                "version": "",
                "host": str(info["host"] or ""),
                "port": int(info["port"] or 0),
                "username": str(info["username"] or ""),
                "default_database": scope_name,
            },
            "items": [
                {
                    "name": scope_name,
                    "is_default": True,
                    "is_system": False,
                    "connectable": True,
                    "dialect": dialect,
                    "size_bytes": None,
                    "table_count": len(table_names),
                    "registered_table_count": registered_count,
                    "owner": None,
                    "encoding": None,
                    "preview_tables": table_names[: cls._PREVIEW_LIMIT],
                    "inspected": True,
                }
            ],
            "total": 1,
            "business_total": 1,
        }