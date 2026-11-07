# Codex Project Agent Assets

本文件只是人工索引，不参与 Codex skill 的触发、执行或调度。

本目录提供 Codex skill 入口：

- `.agents/skills/*/SKILL.md`：项目内直接加载的 Skill 入口，依赖 frontmatter 的 `name` 和 `description`。

## Skill 矩阵

| Skill | 作用 | 使用时机 | 示例 Prompt |
| --- | --- | --- | --- |
| `py-dev` | `__PY_PROJECT_NAME__` 后端 API、DTO、router、service、hub、配置、业务异常和用户/管理端 Socket.IO 基础规则。 | 修改后端接口、配置、业务异常、Socket.IO、跨层边界，或评审后端实现时使用。 | `新增管理端系统设置接口，补 DTO、service 和错误码` |
| `spa-dev` | `__SPA_PROJECT_NAME__` 共享前端架构、bun 脚本、boot、路由守卫、Axios wrapper、DTO/API 基础、i18n/Kmv 错误基础和 Socket.IO client 基础。 | 调整前端基础设施、依赖、boot、network、DTO/API 公共规则、i18n 基础或 socket client 基础时使用。 | `调整 axios_admin 的错误处理，并确认 bun build 仍可用` |

## 使用建议

- 后端 API、持久化、调度和 Socket.IO 工作使用 `py-dev`，按其 reference 路由读取当前任务所需文档。
- `__SPA_PROJECT_NAME__` 的前端工作使用 `spa-dev`，涉及后端契约时同时读取 `py-dev`。
- 两个 Skill 的 `references/verification.md` 提供对应验证入口。
