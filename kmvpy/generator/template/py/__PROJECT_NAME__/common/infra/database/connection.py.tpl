# coding: utf-8
"""数据库连接地址的描述与解析（只读，不含密码）。"""

import os
from typing import Any

from kmvpy.common.conf import DatabaseConfig
from sqlalchemy.engine import make_url


def describe_database_url(database_url: str) -> dict[str, Any]:
    """解析连接 URL 中的服务地址信息（不含密码）。"""
    if not database_url:
        return {
            "dialect": "",
            "host": "",
            "port": 0,
            "username": "",
            "database": "",
        }
    url = make_url(database_url)
    return {
        "dialect": url.get_backend_name(),
        "host": url.host or "",
        "port": url.port or 0,
        "username": url.username or "",
        "database": url.database or "",
    }


def database_name_of(database_config: DatabaseConfig | None) -> str:
    """从数据库配置中提取当前库名称；SQLite 返回文件名。"""
    if database_config is None or not database_config.url:
        return ""
    url = make_url(database_config.url)
    database = url.database or ""
    if url.get_backend_name() == "sqlite":
        if database in ("", ":memory:"):
            return database or ""
        return os.path.basename(database)
    return database