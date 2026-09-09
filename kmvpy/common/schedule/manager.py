"""
全局调度管理器
"""
from __future__ import annotations

import asyncio
import logging
from collections.abc import Iterable

from apscheduler.executors.asyncio import AsyncIOExecutor
from apscheduler.job import Job
from apscheduler.schedulers.asyncio import AsyncIOScheduler

from kmvpy.common.kmv import kosmos
from kmvpy.common.schedule.base import Schedule
from kmvpy.common.tool import logger


class ScheduleManager:
    """
    统一管理所有调度任务的类级调度器。

    - `cron is not None` 的任务由 APScheduler 按周期调度
    - `cron is None` 的任务会在调度器启动后立即以 `asyncio.Task` 方式执行一次
    """

    DEFAULT_TIMEZONE = 'Asia/Shanghai'
    DEFAULT_COALESCE = True
    DEFAULT_MAX_INSTANCES = 1
    DEFAULT_MISFIRE_GRACE_TIME = 5

    _scheduler: AsyncIOScheduler | None = None
    _tasks: dict[str, Schedule] = {}
    _startup_handles: dict[str, asyncio.Task[None]] = {}
    _started = False

    @classmethod
    def get_timezone(cls) -> str:
        config = getattr(kosmos, 'config', None)
        timezone = getattr(config, 'timezone', None)
        if isinstance(timezone, str) and timezone.strip():
            return timezone
        return cls.DEFAULT_TIMEZONE

    @classmethod
    def _build_scheduler(cls) -> AsyncIOScheduler:
        logging.getLogger('apscheduler.executors.default').propagate = False
        return AsyncIOScheduler(
            executors={'default': AsyncIOExecutor()},
            job_defaults={
                'coalesce': cls.DEFAULT_COALESCE,
                'max_instances': cls.DEFAULT_MAX_INSTANCES,
                'misfire_grace_time': cls.DEFAULT_MISFIRE_GRACE_TIME,
            },
            timezone=cls.get_timezone(),
        )

    @classmethod
    def _ensure_scheduler(cls) -> AsyncIOScheduler:
        if cls._scheduler is None:
            cls._scheduler = cls._build_scheduler()
            logger.info('ScheduleManager 初始化完成')
        return cls._scheduler

    @classmethod
    def get_scheduler(cls) -> AsyncIOScheduler:
        return cls._ensure_scheduler()

    @classmethod
    def started(cls) -> bool:
        return cls._started

    @classmethod
    def register(
        cls,
        task: Schedule,
    ) -> Schedule:
        if not isinstance(task, Schedule):
            raise TypeError('register() 只接受 Schedule 实例')
        if task.kid in cls._tasks:
            raise ValueError(f'任务 kid 已存在: {task.kid}')

        cls._tasks[task.kid] = task
        logger.info(f'调度任务已注册: {task.name} (kid={task.kid})')

        if cls._started:
            cls._activate_task(task)

        return task

    @classmethod
    def register_many(cls, tasks: Iterable[Schedule]) -> list[Schedule]:
        return [cls.register(task) for task in tasks]

    @classmethod
    def enable(cls, task: Schedule) -> Schedule:
        return cls.register(task)

    @classmethod
    def get_task(cls, kid: str) -> Schedule | None:
        return cls._tasks.get(kid)

    @classmethod
    def get_tasks(cls) -> list[Schedule]:
        return list(cls._tasks.values())

    @classmethod
    def get_job(cls, kid: str) -> Job | None:
        if cls._scheduler is None:
            return None
        return cls._scheduler.get_job(kid)

    @classmethod
    def get_jobs(cls) -> list[Job]:
        if cls._scheduler is None:
            return []
        return list(cls._scheduler.get_jobs())

    @classmethod
    def pause_job(cls, kid: str) -> None:
        cls._ensure_scheduler().pause_job(kid)
        logger.info(f'已暂停 cron 调度任务: {kid}')

    @classmethod
    def resume_job(cls, kid: str) -> None:
        cls._ensure_scheduler().resume_job(kid)
        logger.info(f'已恢复 cron 调度任务: {kid}')

    @classmethod
    def disable(cls, kid: str) -> None:
        task = cls._tasks.pop(kid, None)
        if task is None:
            return

        if task.is_startup_task:
            handle = cls._startup_handles.pop(kid, None)
            if handle is not None and not handle.done():
                handle.cancel()
        elif cls._scheduler is not None:
            job = cls._scheduler.get_job(kid)
            if job is not None:
                cls._scheduler.remove_job(kid)

        logger.info(f'已移除调度任务: {kid}')

    @classmethod
    async def start(cls) -> None:
        if cls._started:
            logger.info('ScheduleManager 已启动，跳过重复启动')
            return

        scheduler = cls._ensure_scheduler()
        scheduler.start()
        cls._started = True

        for task in cls._tasks.values():
            cls._activate_task(task)

        logger.info(f'ScheduleManager 已启动，当前任务数={len(cls._tasks)}')

    @classmethod
    async def shutdown(cls) -> None:
        startup_handles = list(cls._startup_handles.values())
        cls._startup_handles.clear()

        for handle in startup_handles:
            if not handle.done():
                handle.cancel()

        if startup_handles:
            await asyncio.gather(*startup_handles, return_exceptions=True)

        if cls._scheduler is not None and cls._scheduler.running:
            cls._scheduler.shutdown(wait=True)

        cls._scheduler = None
        cls._started = False
        logger.info('ScheduleManager 已关闭')

    @classmethod
    def _activate_task(cls, task: Schedule) -> None:
        if task.is_startup_task:
            cls._launch_startup_task(task)
            return

        scheduler = cls._ensure_scheduler()
        if scheduler.get_job(task.kid) is not None:
            return

        scheduler.add_job(
            func=task.run,
            trigger=task.build_trigger(timezone=cls.get_timezone()),
            id=task.kid,
            name=task.name,
            replace_existing=False,
        )
        logger.info(f'cron 调度任务已激活: {task.name} (kid={task.kid}, cron={task.cron})')

    @classmethod
    def _launch_startup_task(cls, task: Schedule) -> None:
        handle = cls._startup_handles.get(task.kid)
        if handle is not None and not handle.done():
            return

        async_task = asyncio.create_task(task.run(), name=f'schedule:{task.kid}')
        cls._startup_handles[task.kid] = async_task
        async_task.add_done_callback(lambda finished: cls._on_startup_task_done(task, finished))
        logger.info(f'启动型任务已激活: {task.name} (kid={task.kid})')

    @classmethod
    def _on_startup_task_done(cls, task: Schedule, handle: asyncio.Task[None]) -> None:
        cls._startup_handles.pop(task.kid, None)
        if handle.cancelled():
            logger.info(f'启动型任务已取消: {task.name} (kid={task.kid})')
            return

        error = handle.exception()
        if error is not None:
            logger.error(
                f'启动型任务执行失败: {task.name} (kid={task.kid}) error={error}',
                exc_info=error,
            )
            return

        logger.info(f'启动型任务已退出: {task.name} (kid={task.kid})')


GlobalScheduler = ScheduleManager
SchedulerManager = ScheduleManager


def init_schedule_manager() -> type[ScheduleManager]:
    """
    初始化全局调度器。

    现在调度器采用类方法工作模式，该函数仅保留兼容语义。
    """
    return ScheduleManager


def get_schedule_manager() -> type[ScheduleManager]:
    """
    获取全局调度器。
    """
    return ScheduleManager