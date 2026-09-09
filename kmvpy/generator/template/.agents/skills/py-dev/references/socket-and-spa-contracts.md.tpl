# Socket.IO 与 SPA 契约

在修改用户/管理端 Socket.IO，或任何会改变 SPA 可见 URL、HTTP 方法、DTO 字段、nullable、KID、API 方法名的后端变更时读取本文件。实际修改 `__SPA_PROJECT_NAME__` 时同时使用 `spa-dev` Skill。

## Socket.IO 固定契约

- Socket.IO 对外 path 为 `/ws/socket.io`。
- 用户 namespace 为 `/ws`；管理端 namespace 为 `/admin_ws`。
- 用户与管理端刷新事件名均为 `api_notice`。
- 连接前校验对应角色 token；不要把用户 token 与管理员 token 混用。
- 用户端投递失败时写入 `UserSocketMessage`，通过 `POST /api/user/socket/messages/pull` 补偿拉取。
- 管理端 socket 只广播刷新，不使用用户离线消息表。
- ASGI 创建时从 `core/main/__init__.py` 注册用户和管理端 socket handlers。
- 生产或多进程用户 Socket.IO 要求配置 `auth_config.user.redis`。

`api_notice` 使用稳定的 snake_case transport payload：

- 用户端：`user_kid`、`api_uri`、`kid_for_api`。
- 管理端：`api_uri`、`kid_for_api`。
- 新增或修改 KID 值时统一传字符串；兼容遗留 number 联合类型时在边界尽早归一化。

Socket transport 模块负责连接、鉴权、房间/会话、投递和补偿，不承载普通业务规则。不要把现有 Socket Service 的技术性实现当作普通 Service-to-Service 或 Service 越层访问的通用例外；新增业务判断仍按主 Skill 下沉 Hub。

## HTTP/DTO 契约同步

- 以后端 `APIRouter.prefix + route.path` 为最终 URL，前端字符串必须完全一致。
- HTTP 方法必须一致；后端 POST 对应 `postUserApi`/`postAdminApi` 等 POST wrapper，GET 对应 GET wrapper。
- Python DTO 与 TypeScript transport DTO 保持同一语义和兼容字段集合。
- JSON 传输字段两端都使用 `snake_case`，例如 `verify_code`、`user_type`、`create_time`。
- 后端 `T | None` 对应前端 `T | null`；不要用缺失字段暗示 nullable，除非协议明确可选。
- 对外 BIGINT/KID 使用字符串。
- Python Router handler 使用 `api_snake_case`；TypeScript API 类方法使用 `camelCase`。这两个是代码标识符命名差异，不表示 JSON 字段转换。
- DTO 类/接口使用 PascalCase，并保持 `XxxReq`/`XxxRes` 语义一致。

## 同步位置

| 后端变更 | SPA 检查位置 |
|---|---|
| user DTO/API | `src/network/dto/user`、`src/network/api/user` |
| admin DTO/API | `src/network/dto/admin`、`src/network/api/admin` |
| 用户 Socket | `src/network/socket`、相关 composable/page bridge |
| 管理 Socket | `src/network/admin_socket`、相关 composable/page bridge |
| Kmv 错误 | `src/i18n/kmv` 与语言包错误映射 |

## 变更步骤

1. 列出后端最终 URL、方法、请求、响应、错误和鉴权角色。
2. 更新 Python DTO/Router/Service 后，更新对应 TypeScript DTO 与 API wrapper。
3. 全局搜索旧 URL 和旧字段名，覆盖页面、store、socket notice predicate 与测试。
4. 对 Socket 变更同时验证连接、重连、鉴权失败、广播、离线补偿和多进程行为。
5. 使用 `spa-dev` 要求的类型检查与前端验证，并读取 `verification.md` 完成后端检查。
