from __future__ import annotations

import threading

from kmvpy.common.infra.korm_storage import KOrmStorage
from kmvpy.common.kmv import kosmos


class DefaultStorage(KOrmStorage):

    def __init__(self, *args, **kwargs) -> None:
        # 连接池统一由 kmvpy 的应用 lifespan 初始化/释放；构造期不建立任何连接。
        super().__init__(*args, **kwargs)

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
        """返回进程内唯一的 Storage 实例。

        首次调用时必须能取到配置：可显式传入 ``AppConfig``（推荐在
        ``gen_asgi_app`` 中传入，避免依赖全局状态），否则回退到 ``kosmos.config``。
        后续调用一律复用已创建的实例，传入的 ``config`` 被忽略。
        """
        if cls.__storage is not None:
            return cls.__storage
        with cls.__lock:
            if cls.__storage is None:
                resolved_config = config or kosmos.config
                if resolved_config is None:
                    raise RuntimeError("Storage 尚未初始化，且当前没有可用的应用配置")
                database_config = resolved_config.get_default_storage_database_config()
                redis_config = resolved_config.get_default_storage_redis_config()
                if database_config is None:
                    raise RuntimeError("数据库未配置")
                cls.__storage = cls(
                    database_config=database_config,
                    redis_config=redis_config,
                    timezone=resolved_config.timezone,
                )
        return cls.__storage
