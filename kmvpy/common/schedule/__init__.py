"""
KMVPy 异步定时任务模块

提供基于 APScheduler AsyncIOScheduler 的异步定时任务调度功能。
"""

from kmvpy.common.schedule.base import Schedule
from kmvpy.common.schedule.config import ScheduleConfig
from kmvpy.common.schedule.decorator import schedule_task
from kmvpy.common.schedule.manager import (
    GlobalScheduler,
    ScheduleManager,
    SchedulerManager,
    get_schedule_manager,
    init_schedule_manager,
)

__all__ = [
    'Schedule',
    'GlobalScheduler',
    'ScheduleManager',
    'SchedulerManager',
    'ScheduleConfig',
    'schedule_task',
    'get_schedule_manager',
    'init_schedule_manager',
]