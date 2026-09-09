# Socket.IO 与页面刷新信号

在修改实时连接、认证同步、多标签页协作、页面刷新通知、离线补偿或 Socket 相关 API 时读取本文件。涉及后端行为时同时使用 `py-dev`。

## 当前契约

| 域 | Namespace | Path | Event | 页面 hook |
|---|---|---|---|---|
| user | `/ws` | `/ws/socket.io` | `api_notice` | `onSocketPageMessages` |
| admin | `/admin_ws` | `/ws/socket.io` | `api_notice` | `onAdminSocketPageMessages` |

- 握手通过 `auth.authorization` 传递对应域 token。
- user/admin 各有独立 client、auth helper、BroadcastChannel/localStorage leader、连接状态和 page-message store。
- `api_notice` 只表达“权威资源需要刷新”，不承载页面业务数据；页面收到后重新调用 API。
- 页面消息最多保留 200 条，并按 `api_uri + kid_for_api` 去重。

## 页面处理

1. 使用与访问域匹配的 composable 注册 handler。
2. 用 `ctx.getApiNotices(...)` 按准确 `api_uri` 过滤；详情页按需同时匹配 `kid_for_api`。
3. route params、DTO KID 和 `kid_for_api` 统一用 `String(...)` 比较。
4. 合并同一批通知，避免每条消息触发一次重复请求。
5. handler 已接受并排定刷新后调用 `ctx.removeConsumed(messages)`；若设计依赖失败后重试，则等刷新成功再移除。
6. 组件卸载/停用清理由 composable 处理，不另建重复监听器。

不要把 Socket payload 当成 API 响应，也不要让页面直接操作内部 page-message store。

## user 与 admin 差异

- user 通知可由服务端在重新鉴权后自动补发滞留消息。
- 后端另有 user HTTP pull 能力，但 SPA 当前没有对应 DTO/API wrapper 或主动调用；只有明确接入任务时才新增，不能假设已经存在。
- admin 通知只向在线管理员广播，不使用用户离线消息表。
- 管理页面不得使用 user hook/client，用户页面也不得使用 admin hook/client。

## 多标签页与鉴权生命周期

- 现有 manager 已处理 leader 选举、租约、心跳、去重、online/visibility/pageshow、重连和跨标签 logout。
- 除非任务明确修改基础设施，不重写或旁路这套机制，也不在每个页面建立独立 Socket 连接。
- 登录、token 续签、401 和 logout 必须只通知对应域 client。
- 认证 API wrapper 按既有边界同步 Socket authorization/logout 是允许的网络会话例外；普通业务 API 不操作 Socket 生命周期。

## 契约变更

- 修改 path、namespace、event、`api_uri`、KID 或离线策略时，先核对后端 namespace、emit 调用、Redis/存储和 SPA constants/types/handlers。
- `api_uri` 使用最终后端路由字符串；改 URL 时搜索 Socket 发送方和所有页面过滤器。
- 新通知仍应保持“刷新信号”语义；需要实时业务流时另行设计明确协议，不挤入 `api_notice`。
- 验证单标签、多标签、断线重连、token 变化、logout、页面切换、去重和失败重试行为。
