import asyncio

import pytest

from kmvpy.common.conf import BaseConfig
from kmvpy.common.kmv import kosmos
from kmvpy.common.schedule.base import Schedule
from kmvpy.common.schedule.config import ScheduleConfig
from kmvpy.common.schedule.manager import ScheduleManager, init_schedule_manager


class _NoopSchedule(Schedule):
    async def caller(self) -> None:
        return None


class _TemplateSchedule(Schedule):
    async def caller(self) -> None:
        return None


@pytest.fixture(autouse=True)
def reset_schedule_manager():
    had_config = "config" in vars(kosmos)
    previous_config = getattr(kosmos, "config", None)
    ScheduleManager._scheduler = None
    ScheduleManager._tasks.clear()
    ScheduleManager._startup_handles.clear()
    ScheduleManager._started = False
    yield
    ScheduleManager._scheduler = None
    ScheduleManager._tasks.clear()
    ScheduleManager._startup_handles.clear()
    ScheduleManager._started = False
    if had_config:
        kosmos.config = previous_config
    elif "config" in vars(kosmos):
        delattr(kosmos, "config")


def test_schedule_config_requires_non_empty_kid_and_valid_cron():
    with pytest.raises(ValueError, match='kid 不能为空'):
        ScheduleConfig(kid='  ', cron='*/5 * * * *')

    with pytest.raises(ValueError, match='Wrong number of fields'):
        ScheduleConfig(kid='demo', cron='*/5 * * *')


def test_schedule_manager_registers_cron_job():
    async def scenario() -> None:
        manager = init_schedule_manager()
        task = _NoopSchedule(
            ScheduleConfig(kid='cron_job', cron='*/5 * * * *', name='cron-job')
        )
        manager.register(task)

        await manager.start()

        job = manager.get_job('cron_job')
        assert job is not None
        assert job.name == 'cron-job'
        assert manager.get_task('cron_job') is task

        await manager.shutdown()

    asyncio.run(scenario())


def test_schedule_manager_uses_config_timezone():
    async def scenario() -> None:
        kosmos.config = BaseConfig.model_validate(
            {
                "general": {"debug": False, "env": "test", "timezone": "UTC"},
                "logging": {"level": "INFO"},
            }
        )
        manager = init_schedule_manager()
        task = _NoopSchedule(
            ScheduleConfig(kid='cron_job', cron='*/5 * * * *', name='cron-job')
        )
        manager.register(task)

        await manager.start()

        job = manager.get_job('cron_job')
        assert job is not None
        assert ScheduleManager.get_timezone() == 'UTC'
        assert str(job.trigger.timezone) == 'UTC'

        await manager.shutdown()

    asyncio.run(scenario())


def test_schedule_manager_registers_multiple_schedule_instances():
    async def scenario() -> None:
        manager = init_schedule_manager()
        first = manager.register(
            _TemplateSchedule(
                ScheduleConfig(kid='template_job_a', cron='*/5 * * * *', name='template-job-a')
            )
        )
        second = manager.register(
            _TemplateSchedule(
                ScheduleConfig(kid='template_job_b', cron='*/10 * * * *', name='template-job-b')
            )
        )

        await manager.start()

        first_job = manager.get_job('template_job_a')
        second_job = manager.get_job('template_job_b')
        assert first.kid == 'template_job_a'
        assert second.kid == 'template_job_b'
        assert first_job is not None
        assert second_job is not None
        assert first_job.name == 'template-job-a'
        assert second_job.name == 'template-job-b'

        await manager.shutdown()

    asyncio.run(scenario())


def test_schedule_manager_runs_startup_task_once():
    async def scenario() -> None:
        started = asyncio.Event()
        released = asyncio.Event()

        class StartupSchedule(Schedule):
            async def caller(self) -> None:
                started.set()
                await released.wait()

        manager = init_schedule_manager()
        manager.register(
            StartupSchedule(ScheduleConfig(kid='startup_job', cron=None, name='startup-job'))
        )

        await manager.start()
        await asyncio.wait_for(started.wait(), timeout=1)
        assert 'startup_job' in manager._startup_handles

        released.set()
        await asyncio.wait_for(manager._startup_handles['startup_job'], timeout=1)
        await manager.shutdown()

    asyncio.run(scenario())
