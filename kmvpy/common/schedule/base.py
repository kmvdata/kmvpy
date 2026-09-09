"""
调度任务抽象基类
"""
from __future__ import annotations

import asyncio
import threading
from abc import ABC, abstractmethod

from apscheduler.triggers.cron import CronTrigger

from kmvpy.common.kmv import kosmos
from kmvpy.common.schedule.config import ScheduleConfig
from kmvpy.common.tool import logger


class Schedule(ABC):
    """
    调度任务抽象基类。

    具体任务在实例化时显式传入 `ScheduleConfig`，
    调度器侧统一通过 `ScheduleManager.register(YourSchedule(...))` 注册。
    """

    config: ScheduleConfig

    def __init__(self, config: ScheduleConfig) -> None:
        if not isinstance(config, ScheduleConfig):
            raise TypeError('Schedule 初始化时必须显式传入 ScheduleConfig')

        self.config = config
        self._run_lock = asyncio.Lock()

    @property
    def kid(self) -> str:
        return self.config.kid

    @property
    def cron(self) -> str | None:
        return self.config.cron

    @property
    def name(self) -> str:
        return self.config.resolve_name(self.__class__.__name__)

    @property
    def is_startup_task(self) -> bool:
        return self.cron is None

    def build_trigger(self, timezone: str | None = None) -> CronTrigger:
        return self.config.build_trigger(timezone=timezone)

    async def _on_error(self, error: Exception) -> None:
        logger.error(
            f'调度任务执行失败: {self.name} (kid={self.kid}) error={error}',
            exc_info=error,
        )

    @abstractmethod
    async def caller(self) -> None:
        """
        任务执行主逻辑。
        """

    async def run(self) -> None:
        """
        调度器统一调用的执行入口。
        """
        async with self._run_lock:
            try:
                logger.info(f'调度任务开始执行: {self.name} (kid={self.kid})')
                await self.caller()
                logger.info(f'调度任务执行完成: {self.name} (kid={self.kid})')
            except asyncio.CancelledError:
                logger.info(f'调度任务已取消: {self.name} (kid={self.kid})')
                raise
            except Exception as error:
                await self._on_error(error)
                raise
            finally:
                self._cleanup_thread_session()

    @staticmethod
    def _cleanup_thread_session() -> None:
        thread_id = threading.current_thread().ident
        if thread_id is None:
            return
        sessions = getattr(kosmos, 'sessions', None)
        if isinstance(sessions, dict) and thread_id in sessions:
            del sessions[thread_id]