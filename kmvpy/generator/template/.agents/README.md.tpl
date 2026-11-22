# Codex Project Agent Assets

本文件只是人工索引，不参与 Codex skill 的触发、执行或调度。

本目录同时提供两种 Codex 兼容入口：
本目录提供 Codex skill 入口：

- `.agents/skills/*/SKILL.md`：项目内直接加载的 Skill 入口，依赖 frontmatter 的 `name` 和 `description`。

## Skill 矩阵

| Skill | 作用 | 使用时机 | 示例 Prompt |
| --- | --- | --- | --- |
| `py-dev` | `__PY_PROJECT_NAME__` 后端 API、DTO、router、service、hub、配置、业务异常和用户/管理端 Socket.IO 基础规则。 | 修改后端接口、配置、业务异常、Socket.IO、跨层边界，或评审后端实现时使用。 | `新增管理端系统设置接口，补 DTO、service 和错误码` |
| `py-orm` | SQLAlchemy ORM 表模型、共享类型、`DefaultStorage`、数据库/Redis 初始化、`_REGISTERED_ORM_MODELS` 注册和跨 SQLite/MySQL/PostgreSQL 兼容。 | 新增/修改 `common/infra/orm` 表模型，或调整 `common/infra/storage`、数据库表初始化、底层资源生命周期时使用。 | `新增 audit_event 表模型并注册，确保 Boolean 默认值兼容 PostgreSQL` |
| `py-schedule` | `__PY_PROJECT_NAME__/__PROJECT_NAME__/core/main/schedule` 下定时任务文件、`ScheduleConfig`、直接注册、cron/kid/name、幂等和错误处理。 | 新增或调整 APScheduler/KMVPy schedule 任务时使用。 | `新增每天凌晨清理过期 socket 消息的 schedule` |
| `spa-dev` | `__SPA_PROJECT_NAME__` 共享前端架构、bun 脚本、boot、路由守卫、Axios wrapper、DTO/API 基础、i18n/Kmv 错误基础和 Socket.IO client 基础。 | 调整前端基础设施、依赖、boot、network、DTO/API 公共规则、i18n 基础或 socket client 基础时使用。 | `调整 axios_admin 的错误处理，并确认 bun build 仍可用` |
| `spa-user` | 普通用户 `/app` 页面：`src/pages/app`、`UserLayout.vue` 导航、`requiresAuth` 路由、user DTO/API、用户端 socket 页面刷新。 | 新增/修改用户中心、工单、帮助等普通用户页面和导航时使用。 | `新增 /app/personal/security 用户安全设置页并接入用户 API` |
| `spa-admin` | 管理端 `/admin` 页面：`src/pages/admin`、`AdminLayout.vue` 导航、`requiresAdminAuth` 路由、admin DTO/API、审计操作和管理端 socket 刷新。 | 新增/修改管理后台页面、表格、设置、数据库工具或管理端 API 对接时使用。 | `新增 /admin/audit-events 管理页，接入 admin API 并支持刷新通知` |
| `spa-ui` | 前端 UI 与交互：Quasar 组件、页面状态、响应式、CSS 分层、`spa-*`/`kfw-*` token、主题与字号模式、可访问文案。 | 做界面设计、交互优化、样式重构、主题/字号适配、loading/空态/错误态完善时使用。 | `优化管理端工单列表的筛选栏、空态和移动端布局` |
| `fullstack-contract` | 后端/SPA 契约同步：router path/method、Pydantic DTO、TS DTO/API wrapper、Kmv 错误翻译、Socket.IO `api_notice` payload、BIGINT/KID 精度。 | 任一后端 API、DTO、错误码或 socket payload 会影响前端调用/展示时使用。 | `同步用户工单详情接口到前端 DTO/API，并补 Kmv 错误翻译` |
| `fullstack-feature` | 端到端功能开发协调：选择后端/ORM/schedule/用户端/管理端/UI/契约/验证技能并安排实现顺序。 | 一个需求同时涉及后端和前端，或需要从数据到页面完整落地时使用。 | `实现管理端可查看用户登录记录的完整功能` |
| `fullstack-qa` | 验证与测试：后端语法、导入与配置初始化，前端 bun lint/build/typecheck，以及 skill frontmatter、译文、README 覆盖和过时路径搜索。 | 交付前验证代码或 skill 文件自身，或规划该跑哪些检查时使用。 | `验证本次 skill 矩阵更新，检查 frontmatter、译文和 README 覆盖` |
| `kmvpy-skill-creator` | 创建、拆分、合并、删除或维护 `.agents/skills` 项目 skills，支持 `py-*`、`spa-*`、`fullstack-*` 命名和双语同步。 | 从项目指南、当前代码事实或中文维护稿创建/更新 skill，并同步索引时使用。 | `根据当前前端路由事实拆分 spa-dev 并更新 README` |

## 使用建议

- 单层任务优先使用最小技能：后端 API 用 `py-dev`，用户页用 `spa-user`，管理页用 `spa-admin`，UI polish 用 `spa-ui`。
- 数据基础设施和 schedule 不要塞进通用后端技能：分别使用 `py-orm` 与 `py-schedule`。
- API、DTO、错误码或 socket 影响前后端两边时，使用 `fullstack-contract` 做精确同步。
- 完整功能需求先用 `fullstack-feature` 划分范围，再叠加具体技能。
- 交付前用 `fullstack-qa` 选择和报告验证命令。
