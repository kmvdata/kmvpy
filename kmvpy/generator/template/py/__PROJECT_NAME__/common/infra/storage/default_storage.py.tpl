from __future__ import annotations

import threading
from typing import Any

from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.kmv import kosmos


class DefaultStorage(KOrmStorage):

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
    def instance(cls, config: Any | None = None) -> DefaultStorage:
        if cls.__storage is None:
            with cls.__lock:
                if cls.__storage is None:
                    config = config if config is not None else kosmos.config
                    database_config = config.get_default_storage_database_config()
                    redis_config = config.get_default_storage_redis_config()
                    cls.__storage = cls(
                        database_config=database_config,
                        redis_config=redis_config,
                        timezone=config.timezone,
                    )
        return cls.__storage
