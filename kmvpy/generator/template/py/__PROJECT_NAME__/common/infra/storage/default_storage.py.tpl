from __future__ import annotations

import threading

from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.kmv import kosmos


class DefaultStorage(KOrmStorage):

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)
        self.init_db_session()
        if self.redis_config is not None:
            self.init_redis_client()

    def has_redis_client(self) -> bool:
        return super().has_redis_client()

    @property
    def redis_client(self):
        return super().redis_client

    def set_redis_client(self, redis_client) -> None:
        super().set_redis_client(redis_client)

    def init_redis_client(self):
        return super().init_redis_client()

    async def dispose(self) -> None:
        await super().dispose()

    __storage: DefaultStorage | None = None
    __lock = threading.Lock()

    @classmethod
    def instance(cls) -> DefaultStorage:
        if cls.__storage is None:
            with cls.__lock:
                if cls.__storage is None:
                    config = kosmos.config
                    database_config = config.get_default_storage_database_config()
                    redis_config = config.get_default_storage_redis_config()
                    if database_config is None:
                        raise RuntimeError("数据库未配置")
                    cls.__storage = cls(
                        database_config=database_config,
                        redis_config=redis_config,
                    )
        return cls.__storage
