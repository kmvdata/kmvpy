---
name: py-dev
description: Use for designing, implementing, reviewing, or explaining any __PY_PROJECT_NAME__ backend change under __PY_PROJECT_NAME__/__PROJECT_NAME__ — including FastAPI/kmvpy HTTP APIs, DTO/router/service/hub boundaries, AppConfig, business exceptions, user/admin Socket.IO behavior, ORM table models, DefaultStorage, database sessions, schedule tasks, smoke tests, and SPA API contract synchronization. This is the single authoritative skill for all Python backend work.
---

# __PY_PROJECT_NAME__ 后端开发

把本 Skill 作为 `__PY_PROJECT_NAME__/__PROJECT_NAME__` 后端工作的唯一架构与流程入口。先应用本文件中的核心约束，再按任务范围读取所需 reference；不要为方便而复制仓库中的遗留越层实现。

## 使用协议

1. 先识别本次任务涉及的层、入口域、数据资源和外部契约。
2. 根据下表读取所有匹配的 reference；多项命中时全部读取，且在行动前完整读完。
3. 先检查现有实现和直接调用方，再设计或修改；把现有违规视为技术债，不把它当作新范式。
4. 只实现受影响的层，不机械执行与任务无关的全栈步骤。
5. 实现或评审任务在交付前读取 `verification.md`；纯解释任务按需读取。

## Reference 路由

| 任务范围 | 必读 reference |
|---|---|
| 定位目录、创建/移动/重命名文件、选择 user/admin/public、命名或注册点 | [`references/repository-map.md`](references/repository-map.md) |
| DTO、HTTP Router、鉴权、审计、响应包装、Router 注册 | [`references/http-api.md`](references/http-api.md) |
| Service、Hub、业务判断、事务边界、多个 Hub 编排 | [`references/service-hub.md`](references/service-hub.md) |
| ORM、SQLAlchemy、Storage、Redis、session、模型注册、数据库兼容 | [`references/persistence.md`](references/persistence.md)；涉及事务时同时读取 `service-hub.md` |
| AppConfig、环境配置 helper、业务错误、`KmvException` | [`references/config-and-errors.md`](references/config-and-errors.md) |
| Schedule、cron、任务注册、幂等与失败处理 | [`references/schedules.md`](references/schedules.md) |
| Socket.IO 或任何 SPA 可见的 URL/方法/DTO/KID/nullable 变更 | [`references/socket-and-spa-contracts.md`](references/socket-and-spa-contracts.md) |
| 实现交付、代码评审、测试方案、分层合规检查 | [`references/verification.md`](references/verification.md) |

## 技术基线

- 使用 Python >= 3.11、FastAPI + kmvpy、Pydantic v2、SQLAlchemy 2.x 异步 ORM。
- 开发使用 SQLite，生产主要使用 MySQL；新增数据层代码同时关注 PostgreSQL 兼容性。
- 主包位于 `__PY_PROJECT_NAME__/__PROJECT_NAME__`，冒烟测试位于 `__PY_PROJECT_NAME__/app/st_test`。
- 后端契约影响 `__SPA_PROJECT_NAME__` 时同步修改；实际编辑 SPA 时同时使用 `spa-dev` Skill。

## 核心架构

严格保持单向依赖：

```text
HTTP / Socket Router ─┐
Schedule ─────────────┴─> Service ─> Hub ─> Infra
                                      ├─> Config
                                      └─> Exception
```

| 层 | 职责 | 可调用 |
|---|---|---|
| Router | HTTP/Socket 入口、鉴权、参数绑定、响应包装 | Service |
| Schedule | 定时触发、输入准备、任务日志 | Service |
| Service | 事务生命周期、无条件调用顺序、底层异常转换、DTO 组装 | Hub、DTO、Exception；以及仅用于 `session_scope()` 的 `DefaultStorage` |
| Hub | 业务判断、校验、规范化、聚合操作、数据访问、配置读取 | Infra、Config、Exception |
| Infra | ORM、Storage、Redis、RPC、AI 等技术资源 | 不调用上层 |
| Config | 配置模型与安全读取 | 不调用上层 |
| Exception | 错误常量与 builder | 不调用 Router、Service、Hub 或 Infra |

### Service 与业务逻辑

- 让 Service 只定义事务、按固定顺序调用一个或多个 Hub、转换明确的底层异常并组装 DTO。
- 禁止在 Service 中根据业务数据编写 `if`/`match`/条件循环；权限、状态、存在性和流程决策全部放入 Hub。
- 若上一步结果决定下一步，封装为一个粗粒度 Hub 操作；不要在 Service 中“查询后判断再调用”。
- 禁止 Service 调用另一个 Service。共享业务能力下沉 Hub；`service/common` 不是例外。
- 禁止 Service 直接操作 ORM、Storage 查询/cache helper、Redis、RPC、AI 或 Config。
- 允许 Service 调用 `DefaultStorage.instance().session_scope()`，但这只是事务生命周期的唯一 Infra 例外。
- 返回 DTO 或稳定结构，绝不把 ORM 实例暴露给 Router。

### Hub 与 session 边界

- 按业务主题组织无状态 `@staticmethod` Hub；Hub 不依赖 FastAPI、Pydantic DTO、Router 或 Service。
- 让需要数据库访问的 Hub 方法显式接受 Service 传入的 `session`；Hub 不创建 session，不提交或回滚事务。
- **任何签名含 `session` 的 Hub 方法不得调用其他签名含 `session` 的 Hub 方法**，包括当前 Hub 和其他 Hub。
- 含 `session` 的 Hub 方法可以调用不含 `session` 的纯校验、规范化或计算方法。
- 一个含 `session` 的粗粒度操作需要多表联动时，在当前方法内直接使用该 session 访问相关 ORM/Infra。
- 多个含 `session` 的 Hub 方法需要共享事务时，只能由 Service 创建同一个 session 并逐一调用。
- 不含 `session` 的 Hub 方法也不得自行创建 session 后转调含 `session` 的 Hub 方法。

## 红线

- [ ] Router 未调用 Hub、Infra 或 Config；Schedule 未绕过 Service 执行业务流程。
- [ ] Service 未调用 Service，未直接查询 Infra/Config，且只通过 `session_scope()` 管理事务。
- [ ] Service 没有业务分支；所有业务判断位于 Hub。
- [ ] 含 `session` 的 Hub 方法没有调用任何其他含 `session` 的 Hub 方法。
- [ ] Hub 没有 FastAPI、DTO、Router 或 Service 依赖，也没有自行管理事务。
- [ ] ORM 未穿透到 Router/API 响应；对外 BIGINT/KID 使用 `str`。
- [ ] 错误三元组只定义于 `common/exception/*_errors.py`，调用点没有内联。
- [ ] 新 ORM 已加入 `_REGISTERED_ORM_MODELS`；新 Router/Schedule 已完成集中注册。
- [ ] SPA 可见契约的 URL、方法、DTO、nullable、KID 和 Socket 行为已同步。

## 条件式开发流程

1. 明确入口域、业务主题、事务边界、错误语义和受影响契约。
2. 读取所有匹配的 reference，并检查同主题现有代码、测试和调用方。
3. 如需数据模型，先设计 ORM/约束并完成注册；如需错误或配置，同时定义稳定入口。
4. 在 Hub 实现业务规则和数据访问；遵守 session 方法隔离。
5. 在 Service 定义事务和固定调用顺序，捕获明确异常并组装 DTO。
6. 在 Router/Schedule 暴露入口，不把业务逻辑带回入口层。
7. 如契约对 SPA 可见，同步前端 DTO/API/Socket 使用方。
8. 读取 `verification.md`，运行与风险匹配的检查并审阅最终 diff。
