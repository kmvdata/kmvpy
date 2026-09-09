# 调度任务

在修改 `core/main/schedule`、新增 cron 任务、注册 Schedule 或设计幂等/失败处理时读取本文件。

## 架构位置

把 Schedule 视为与 Router 并列的入口适配器：`Schedule -> Service -> Hub -> Infra`。

- 在 `caller()` 中调用 Service 完成业务流程，不直接访问 ORM、Storage、Redis、Config 或含 `session` 的 Hub 方法。
- 不在 Schedule 中创建数据库 session；事务仍由 Service 定义。
- 只把定时触发、输入准备、调用、日志和任务级错误上下文留在 Schedule。
- 不通过 Schedule 绕开 Service/Hub 边界。现有遗留调用不是新增代码的先例。

## 文件与注册

- 每个 `schedule_<topic>.py` 文件定义一个聚焦的 `Schedule` 子类。
- 实现 `async def caller(self) -> None`；任务类不注册自己，也不构造 `ScheduleConfig`。
- 在 `core/main/schedule/__init__.py` 导入任务类，并在 `register_app_schedule_jobs()` 中集中注册。
- 在 `__init__.py` 构造 `ScheduleConfig`、实例化 Schedule、调用 `ScheduleManager.register(...)`。
- 同一 Schedule 类可以注册多个实例，但每个实例使用唯一 `kid`。

```python
from kmvpy.common.schedule import ScheduleConfig, ScheduleManager

from .schedule_demo import ScheduleHelloDemo


def register_app_schedule_jobs() -> None:
    ScheduleManager.register(
        ScheduleHelloDemo(
            ScheduleConfig(
                kid="schedule_hello_demo",
                cron="* * * * *",
                name="__PROJECT_NAME__ schedule demo",
            )
        )
    )
```

## 实现规则

- 先明确频率、时区、输入来源、幂等键、并发策略、失败重试与可观测性。
- 使用异步 IO；无法替换的阻塞 IO 包在 `asyncio.to_thread(...)` 中。
- 日志包含任务 `kid`、关键输入、安全的结果摘要和异常上下文；不得记录密码、token 或密钥。
- 需要用户可见业务错误时引用 `__PROJECT_NAME__.common.exception`，不要内联错误三元组。
- 仅在确需补充任务上下文时覆盖 `_on_error()`；优先沿用基类行为。

## 新增流程

1. 定义任务职责、触发规则、幂等性和失败策略。
2. 如涉及业务数据，先提供符合分层规则的 Service/Hub 能力。
3. 创建 `schedule_<topic>.py` 并实现 `caller()`。
4. 在 `schedule/__init__.py` 导入并注册。
5. 编写聚焦测试，验证重复执行和失败路径。
6. 交付前读取 `verification.md`。
