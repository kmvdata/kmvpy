"""
定时任务装饰器
"""
from __future__ import annotations

import inspect
from collections.abc import Awaitable, Callable
from functools import wraps
from typing import Any, Protocol

from kmvpy.common.schedule.base import Schedule
from kmvpy.common.schedule.config import ScheduleConfig
from kmvpy.common.schedule.manager import ScheduleManager, get_schedule_manager


class ScheduleCallable(Protocol):
    def __call__(self, *args: Any, **kwargs: Any) -> Awaitable[Any]:
        ...

    def build_task(self) -> Schedule:
        ...

    def register(self, manager: type[ScheduleManager] | None = None) -> Schedule:
        ...


def schedule_task(
    *,
    kid: str,
    cron: str | None,
    name: str | None = None,
) -> Callable[[Callable[[], Awaitable[Any]]], ScheduleCallable]:
    """
    将一个无参异步函数包装成可注册的调度任务。
    """

    def decorator(func: Callable[[], Awaitable[Any]]) -> ScheduleCallable:
        signature = inspect.signature(func)
        if signature.parameters:
            raise TypeError('schedule_task 仅支持无参异步函数')

        task_config = ScheduleConfig(
            kid=kid,
            cron=cron,
            name=name or func.__name__,
        )

        class DecoratedSchedule(Schedule):
            async def caller(self) -> None:
                await func()

        @wraps(func)
        async def wrapper(*args: Any, **kwargs: Any) -> Any:
            return await func(*args, **kwargs)

        def build_task() -> Schedule:
            return DecoratedSchedule(task_config.model_copy())

        def register(manager: type[ScheduleManager] | None = None) -> Schedule:
            active_manager = manager or get_schedule_manager()
            return active_manager.register(build_task())

        setattr(wrapper, 'build_task', build_task)
        setattr(wrapper, 'register', register)
        return wrapper  # type: ignore[return-value]

    return decorator