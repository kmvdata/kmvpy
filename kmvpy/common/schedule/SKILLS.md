# KMVPy Schedule Skills

本文件用于帮助 AI 快速理解 `kmvpy.common.schedule` 的当前架构、真实行为和推荐改法。目标不是重复 API 文档，而是让 AI 在新增、排查、重构 schedule 时尽快抓住关键约束。

## 何时使用本说明

当用户提出以下需求时，应先按本文件理解再行动：

- 新增一个定时任务
- 修改 schedule 的注册方式
- 调整 `kid` / `cron` / `name`
- 支持同一个任务类型的多实例注册
- 接入 FastAPI 生命周期
- 排查任务没有执行、重复执行或无法关闭
- 改进 `ScheduleManager`、`ScheduleConfig`、装饰器或相关测试

## 架构总览

当前 schedule 模块由 4 个核心角色组成：

1. `Schedule`
   负责定义单个任务的执行逻辑与统一执行入口。
2. `ScheduleConfig`
   负责描述单个任务的静态配置，如 `kid`、`cron`、`name`。
3. `ScheduleManager`
   负责保存已注册任务、激活 APScheduler cron 任务、启动型任务和统一启停。
4. `schedule_task`
   用于把无参异步函数包装成可注册的 `Schedule`。

当前模型是“任务声明 + 类级调度器”：

- 调度器使用类属性保存全局状态，不是实例化后再传递
- `ScheduleManager.start()` / `shutdown()` 操作的是类级全局调度器
- `init_schedule_manager()` 和 `get_schedule_manager()` 只是兼容别名，最终都返回 `ScheduleManager`

## 核心事实

### 1. `Schedule` 是任务抽象

新增任务时，默认应继承 `Schedule`。

推荐分工：

- 任务类里只实现 `async def caller(self) -> None`
- `ScheduleConfig` 在实例化时显式传入
- 注册动作放在接入层，而不是任务类内部

推荐写法：

```python
from kmvpy.common.schedule import Schedule, ScheduleConfig


class DemoSchedule(Schedule):
    async def caller(self) -> None:
        ...


task = DemoSchedule(
    ScheduleConfig(
        kid="demo_schedule",
        cron="*/5 * * * *",
        name="演示任务",
    )
)
```

### 2. `ScheduleConfig` 是单任务配置模型

字段只有这几个：

- `kid`: 任务唯一标识，不能为空
- `cron`: cron 表达式，`None` 表示启动型任务
- `name`: 展示/日志名称，可为空，为空时回退为类名或函数名

重要约束：

- `kid` 会在校验阶段去空白，不能为空字符串
- `cron` 为空字符串会报错
- `cron` 非空时会立即按 APScheduler 的 crontab 规则校验
- `name` 如果给了，就不能是空字符串

### 3. `ScheduleManager` 是唯一推荐注册入口

统一使用 `ScheduleManager.register()`，不要在业务侧私自复制注册逻辑。

它只支持直接注册实例。

#### 直接注册实例

```python
ScheduleManager.register(
    DemoSchedule(
        ScheduleConfig(
            kid="demo_schedule",
            cron="*/5 * * * *",
            name="演示任务",
        )
    )
)
```

### 4. 同一个 `Schedule` 类型可以注册多次

只要每次创建实例时使用不同的 `kid`，就可以被多次创建和加载。

示例：

```python
ScheduleManager.register(
    DemoSchedule(ScheduleConfig(kid="demo_a", cron="*/5 * * * *"))
)
ScheduleManager.register(
    DemoSchedule(ScheduleConfig(kid="demo_b", cron="*/10 * * * *"))
)
```

这两个任务会被视为两个独立任务。

禁止：

- 使用同一个 `kid` 重复注册
- 依赖“同类任务自动去重”的假设

真实行为：

- 如果 `kid` 已存在，`register()` 会抛 `ValueError`

## 两类任务语义

### Cron 任务

当 `cron is not None` 时：

- 会在 `start()` 后注册到 APScheduler
- 通过 `task.build_trigger()` 构造 `CronTrigger`
- 调度器会把 `task.run` 作为执行入口

### 启动型任务

当 `cron is None` 时：

- 不会进入 APScheduler
- 会在 `start()` 后立刻用 `asyncio.create_task()` 启动一次
- 是否短暂执行还是常驻运行，完全由 `caller()` 决定

示例：

```python
import asyncio

from kmvpy.common.schedule import Schedule, ScheduleConfig


class WorkerSchedule(Schedule):
    async def caller(self) -> None:
        while True:
            await do_work()
            await asyncio.sleep(1)


worker = WorkerSchedule(
    ScheduleConfig(
        kid="worker_schedule",
        cron=None,
        name="常驻任务",
    )
)
```

关键理解：

- `cron=None` 不等于“循环任务”
- 它只是“启动时触发一次”
- 想持续运行，必须在 `caller()` 内自己循环并响应取消

## 任务执行生命周期

`Schedule.run()` 是调度器真正调用的统一入口，默认行为如下：

1. 加锁，避免同一任务实例并发重入
2. 记录开始日志
3. 执行 `caller()`
4. 成功后记录完成日志
5. 失败后记录错误日志并重新抛出异常
6. 最后清理当前线程绑定的 `kosmos.sessions`

这意味着：

- 不建议绕过 `run()` 直接调 `caller()`
- 执行前后的补充日志直接写在 `caller()` 中
- 如需补充异常上下文，优先扩展 `_on_error(error)`
- 线程清理逻辑是当前实现的一部分，改动时要明确验证副作用

## 启停与生命周期接入

标准启停方式：

```python
from kmvpy.common.schedule import ScheduleConfig, ScheduleManager

ScheduleManager.register(
    DemoSchedule(ScheduleConfig(kid="demo_schedule", cron="*/5 * * * *"))
)
await ScheduleManager.start()
await ScheduleManager.shutdown()
```

接入 FastAPI 时，通常在 `lifespan` 中：

1. 应用启动阶段先完成任务注册
2. 然后调用 `await ScheduleManager.start()`
3. 应用关闭阶段调用 `await ScheduleManager.shutdown()`

必须理解的行为：

- `start()` 重复调用时会直接跳过
- `shutdown()` 会取消所有启动型任务句柄
- 若 APScheduler 正在运行，会执行 `scheduler.shutdown(wait=True)`
- 当前 `shutdown()` 不会清空 `_tasks`
- 因此如果同一进程内要重新启动且不想保留旧注册，业务侧需要自行决定是否清理或复用

## 装饰器模式

如果任务逻辑非常简单，也可以使用 `schedule_task`：

```python
from kmvpy.common.schedule import ScheduleManager, schedule_task


@schedule_task(kid="heartbeat", cron="*/1 * * * *", name="心跳任务")
async def heartbeat() -> None:
    ...


heartbeat.register()
await ScheduleManager.start()
```

装饰器的限制和事实：

- 只支持无参异步函数
- 会内部生成一个 `Schedule` 子类
- `wrapper.register()` 最终仍然调用 `ScheduleManager.register(build_task())`
- 如果需求变复杂，优先回到显式的 `Schedule` 子类

## 推荐改法

### 新增任务

默认流程：

1. 明确任务是否应为 cron 任务还是启动型任务
2. 定义一个 `Schedule` 子类
3. 只在类里实现 `caller()`
4. 在接入层实例化时构造 `ScheduleConfig`
5. 在业务接入层调用 `ScheduleManager.register(...)`
6. 补最小必要测试

### 复用同一任务类型创建多个实例

优先复用类型，并在创建实例时传入不同配置：

```python
ScheduleManager.register(SyncSchedule(ScheduleConfig(kid="sync_a", cron="*/5 * * * *")))
ScheduleManager.register(SyncSchedule(ScheduleConfig(kid="sync_b", cron="*/30 * * * *")))
```

不要为了多个实例复制多个几乎相同的 `Schedule` 子类。

### 修改注册架构

如果用户要调整项目内 schedule 的接入方式：

- 优先保持 `kmvpy.common.schedule` 作为通用能力层
- 业务项目自己的“任务清单”和“注册声明”应放在业务侧
- 不要把业务注册清单硬编码回通用库

## 常见坑

### 1. 把 `cron=None` 误解成 APScheduler 周期任务

错。它是启动后触发一次的 `asyncio.Task`。

### 2. 忘记 `kid` 是全局唯一

同一个 manager 下，`kid` 冲突会直接报错。

### 3. 以为 `shutdown()` 会清空全部注册任务

错。当前实现会关调度器、取消启动型任务，但不会清空 `_tasks`。

### 4. 用阻塞 I/O 直接写进 `caller()`

如果存在同步阻塞调用，优先考虑异步化；必要时可用 `asyncio.to_thread(...)`。

### 5. 改了 manager 行为但没补测试

这个模块行为比较集中，改动后应至少验证：

- cron 任务能注册并启动
- 启动型任务只在启动时触发一次
- 多实例注册可生效
- `kid` 冲突和配置校验行为未被破坏

## AI 修改本模块时的工作顺序

1. 先读 `base.py`
2. 再读 `config.py`
3. 再读 `manager.py`
4. 如涉及装饰器，再读 `decorator.py`
5. 最后读 `test_schedule_manager.py`

这样能先理解模型，再理解行为，再理解回归保护。

## 何时先提问，不要直接改

遇到以下情况，应先向用户确认：

- 新任务到底是 cron 任务还是启动型任务
- `kid` 是否允许一个类型对应多个实例
- `shutdown()` 是否需要顺带清空 `_tasks`
- 是否要支持持久化、分布式锁、动态热更新等超出当前能力边界的需求
- 业务项目里到底由谁负责注册清单

## 最小测试建议

改动本模块后，优先补或运行围绕这些行为的测试：

- `ScheduleConfig` 校验
- `ScheduleManager.register()` 基本注册
- `ScheduleManager.register()` 多实例注册
- `ScheduleManager.start()` 对 cron 任务的激活
- `ScheduleManager.start()` 对启动型任务的触发
- `ScheduleManager.shutdown()` 的关闭行为

## 一句话总结

`kmvpy.common.schedule` 的当前核心是：任务类只负责执行逻辑，`ScheduleConfig` 在实例化时传入，类级 `ScheduleManager` 统一负责注册和启停；`cron=None` 是启动型任务；同一个任务类型可以通过不同 `kid` 的多个实例被重复注册。
