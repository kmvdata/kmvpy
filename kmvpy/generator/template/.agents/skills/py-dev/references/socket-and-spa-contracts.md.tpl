# Socket.IO、会话与 SPA 契约

在修改 user/admin 实时鉴权、续期、订阅、Redis 资源保护，或 SPA 可见 URL、HTTP 方法、DTO、nullable、KID、API 方法时读取本文件。编辑 SPA 同时使用 `spa-dev`。完整架构、当前配置和本机验收见 [Web 实时连接文档](../../../../docs/web-realtime.md)。

## 传输与身份边界

- 底层 path 为 `/ws/socket.io`；user namespace `/ws`，admin namespace `/admin_ws`。Namespace 不是 transport path，SPA 用 `forceNew` / `multiplex: false` 让两域底层连接独立。
- `core/main/__init__.py` 注册两域 handlers、HTTP 观测中间件与 CORS；同一 Redis 通知适配器可承载两域广播，但鉴权、会话与额度按域隔离。
- JWT 稳定登录 `sid`、可续签 access 的 `jti`/`exp`、Socket.IO namespace SID / Engine.IO SID / 保护用唯一连接 ID 不可混用。普通续签保留登录边界，重新登录产生新 `sid`。
- `common/infra/realtime_auth.py` 通过 `AuthSessionService` 验签，并校验角色、cookie 和 Redis 登录会话。客户端 `tab_id`、恢复提示或解码身份只用于协调/观测，不能作为权限或唯一额度依据。
- 前端正常稳态同浏览器分区每个有合格页面的域共享一条连接，无合格页面可为 0；后台必须独立支持正常多设备与交接短暂重叠，不实行全球单用户一条。

`RealtimeService` 提供技术入口，`RealtimeHub` 管理传输登记、同会话鉴权更新、订阅与额度；Infra 封装鉴权适配、Redis 原子保护和 HTTP 指标。现有 Socket Service 的技术兼容路径不构成普通 Service-to-Service 或越层访问的通用例外；新增业务判断仍遵守主 Skill。

## 校验、续签与结构化错误

| 契约 | 行为 |
|---|---|
| `POST /api/user/socket/session` / `/api/admin/socket/session` | 使用对应 `auth_user` / `auth_admin`；成功 `ApiResponse` 为 `code: 0, data: {valid: true}`，续签走既有 HTTP 响应头 |
| `auth_update` | `{authorization}` 输入；独立鉴权且同域/用户/稳定 sid 才接受，仅推进有效期；ACK `{ok: true, expires_at}`，原 transport 更新到期任务 |
| `auth_status` / 连接拒绝 / ACK 错误 | 使用结构化 `kind` 分类，旧任务与回调检查当前连接登记身份 |
| HTTP 明确登录失效 | 401 + `WWW-Authenticate: Bearer` + `X-Auth-Role` + `X-Auth-Error: session_invalid` |
| access 到期但登录有效 | HTTP 尝试恢复；Socket `token_expired` 允许客户端校验后重建 |
| 暂时故障或资源限制 | `temporary`、`rate_limited`，HTTP 503/429；保留登录，不能伪装为会话失效 |

- 首次/重建/接管由前端先 HTTP 校验，再握手；HTTP 成功状态不能替代成功 envelope。
- 客户端以 transport 实际使用 token 的到期时间续期，新存储 token 不延后旧连接续期；不能要求每次续签重建 transport 或中止有效慢握手。
- Redis 会话存储不可用且 access 已过期时返回 503。既有未过期、验签通过的 JWT 可按当前认证降级路径继续，但此时无法保证即时撤销；资源保护降级不扩大认证权限。
- `python-socketio` 连接拒绝用消息与 data 两个参数传递 `kind`，避免结构化错误退化为文本。不要靠错误文案包含 `401` 退出登录，也不要记录完整 JWT/cookie。
- 改动鉴权依赖同时读取 `http-api.md`；错误与配置细节见 `config-and-errors.md`（均由主 Skill 直接链接）。

## 通知、订阅与补偿

- 两域事件均为 `api_notice`，只表达变化/校准，页面通过鉴权 HTTP 权威读取。用户 payload 为 `user_kid`、`api_uri`、`kid_for_api`；admin 为 `api_uri`、`kid_for_api`，保持 snake_case，新增 KID 用字符串。
- 用户投递失败保留 `UserSocketMessage`、重新鉴权补发和 `POST /api/user/socket/messages/pull`；admin 不使用用户离线表。SPA 当前没有主动 pull wrapper，不能声称已有全套 HTTP 拉取接入。
- `subscription` 输入 `{action: 'subscribe'|'unsubscribe', resource, baseline}`；校验资源长度与安全整数/null 基线，ACK 成功才能更新客户端确认表，失败返回 `ok: false, kind`。
- 服务端通用房间按已鉴权域、用户和 resource hash 构造，不能接受任意客户端 room。订阅意图不授予业务资源权限；未来向通用资源房间发布业务通知需补充真实资源授权。
- 主标签按最慢有效消费者汇总基线，任一未知为 null；重连/交接恢复订阅。当前无业务版本协议，ACK `calibrate: true` 要求资源 HTTP 校准，既有通知仍走原私有房间。
- 保留既有 ACK/补偿机制，不承诺传输恰好一次；隐藏/停用重入与断线遗漏用校准补偿，不自动为所有广播新增逐用户离线存储。

## 共享保护与观测

- `common/infra/realtime_guard.py` 在对应域认证成功后执行。额度键按 domain / 已鉴权用户 / 稳定登录 sid，使用同 Redis Cluster hash slot 的 Lua 原子操作与 Redis TIME，不使用进程内计数代替共享准入。
- 每次连接生成唯一 ID；原子准入、续租、TTL 与只释放自身成员覆盖初始化失败回滚、断开、退出和进程崩溃。过期迟到续租不得复活成员，旧连接清理不得删除新连接或其他域状态。
- 连接数/尝试频率/订阅量与操作频率/鉴权 HTTP 频率均由 `AppConfig.realtime_protection` 配置；`off|observe|enforce` 与存储失败策略见 `config-and-errors.md`。没有生产容量证据时保持默认 observe，额度预留正常设备与交接余量。
- `realtime_http.py` 记录鉴权 HTTP 状态、响应字节、耗时；Redis 观测连接/恢复/续签/订阅、超额、等待与失败，指标 TTL 24h。只记录安全标识与统计，不保存业务正文、完整 token 或敏感凭据。
- Redis 故障时按 allow/deny 处理已鉴权资源分配；故障期间共享指标不可靠，采集节流故障日志。资源放行不跳过认证。

## 部署与排障

当前 develop/release 均为 1 worker；部署改变时重新核对实际进程数。生产或多进程用户 Socket.IO 仍要求 `auth_config.user.redis`。允许 polling 的多节点/worker 必须保持同 Engine.IO SID 的 polling/upgrade 请求亲和性，Redis 通知适配器不能替代传输亲和性。

核对 Socket.IO 自身与 FastAPI CORS、cookie、续签/结构化错误响应头暴露、HTTP/1.1 Upgrade/Connection 及代理读写超时。当前生成 Nginx 模板为 300s，大于 Engine.IO 默认 25s ping + 20s timeout；以实际部署为准，不把模板核实描述为生产验证。握手中止/HTTP 400 需脱敏响应正文、结构化错误及对应服务端记录。

## HTTP/DTO 契约同步

- 以后端 `APIRouter.prefix + route.path` 为最终 URL，前端字符串与 HTTP 方法必须完全一致。
- Python DTO 与 TypeScript transport DTO 保持同一语义和兼容字段集合；JSON 两端 snake_case。
- 后端 `T | None` 对应前端 `T | null`；仅协议允许缺失时使用可选字段。
- 对外 BIGINT/KID 使用字符串；Router handler 为 `api_snake_case`、TypeScript API 方法为 camelCase，DTO 为 PascalCase `XxxReq`/`XxxRes`；代码命名差异不表示 JSON 转换。

| 后端变更 | SPA 检查位置（`__SPA_PROJECT_NAME__/src` 下） |
|---|---|
| user/admin DTO/API | `network/dto/{user,admin}`、`network/api/{user,admin}` |
| 鉴权、会话或实时传输 | `boot/axios*.ts`、`network/realtime`、`network/socket`、`network/admin_socket` |
| 页面同步、订阅与补偿 | `composables/usePageRefresh.ts`、对应 notice hooks/bridge 与业务消费者 |
| Kmv 错误 | `i18n/kmv` 与语言包错误映射 |

列出最终 URL/方法/输入/响应/结构化错误与鉴权角色后同步双端，搜索旧字段、发送方和通知过滤器。按受影响行为验证隔离、续期、ACK/校准和真实多进程保护；读取主 Skill 的 `verification.md`，前端验证遵循 `spa-dev`。
