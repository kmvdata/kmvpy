# coding: utf-8
"""在既有数据库连接上做只读内省。

只接受调用方已经持有一个 KOrmStorage（即默认连接），不接受库名参数，
因此无法借此切换到配置文件之外的数据库。
"""

from kmvpy.common.infra.korm_storage import KOrmStorage
from sqlalchemy import inspect as sa_inspect


async def read_database_table_names(storage: KOrmStorage) -> list[str]:
    """读取当前连接所在库的全部表名。"""
    if not storage.has_db_session():
        storage.init_db_session()

    def _names(sync_conn) -> list[str]:
        return sorted(str(name) for name in sa_inspect(sync_conn).get_table_names())

    async with storage.engine.connect() as conn:
        return await conn.run_sync(_names)