"""
调度任务声明配置
"""
from __future__ import annotations

from apscheduler.triggers.cron import CronTrigger
from pydantic import BaseModel, ConfigDict, Field, field_validator


class ScheduleConfig(BaseModel):
    """描述单个 schedule 任务的静态配置。"""

    model_config = ConfigDict(frozen=True)

    kid: str = Field(description='任务唯一标识')
    cron: str | None = Field(
        default=None,
        description='cron 表达式；为 None 时表示应用启动后立即执行一次',
    )
    name: str | None = Field(default=None, description='任务显示名称')

    @field_validator('kid')
    @classmethod
    def validate_kid(cls, value: str) -> str:
        if not isinstance(value, str):
            raise TypeError('kid 必须是字符串')
        normalized = value.strip()
        if not normalized:
            raise ValueError('kid 不能为空')
        return normalized

    @field_validator('cron')
    @classmethod
    def validate_cron(cls, value: str | None) -> str | None:
        if value is None:
            return None
        if not isinstance(value, str):
            raise TypeError('cron 必须是 cron 表达式字符串或 None')
        normalized = value.strip()
        if not normalized:
            raise ValueError('cron 不能为空字符串')
        CronTrigger.from_crontab(normalized)
        return normalized

    @field_validator('name')
    @classmethod
    def validate_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        if not normalized:
            raise ValueError('name 不能为空字符串')
        return normalized

    def resolve_name(self, default_name: str) -> str:
        return self.name or default_name

    def build_trigger(self, timezone: str | None = None) -> CronTrigger:
        if self.cron is None:
            raise ValueError(f'任务 {self.kid} 未配置 cron 表达式')
        return CronTrigger.from_crontab(self.cron, timezone=timezone)