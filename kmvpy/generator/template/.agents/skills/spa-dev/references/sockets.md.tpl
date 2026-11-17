# Socket.IO、多标签页与页面恢复

在修改实时连接、认证同步、路由连接资格、多标签页选主、页面刷新、订阅或离线补偿时读取本文件。涉及后端行为时同时使用 `py-dev`。架构解释、配置与验收复现见仓库 [Web 实时连接文档](../../../../docs/web-realtime.md)；验证入口见主 Skill 的 `verification.md`。

## 当前职责与传输契约

| 权限域 | Namespace | 底层 transport path | 通知 | 页面消费 hook |
|---|---|---|---|---|
| user | `/ws` | `/ws/socket.io` | `api_notice` | `onSocketPageMessages` |
| admin | `/admin_ws` | `/ws/socket.io` | `api_notice` | `onAdminSocketPageMessages` |

- `src/network/realtime/manager.ts` 统一管理所有权、校验、握手、续签、重试、转发和订阅；`client.ts` 创建每域实例。原 `socket` / `admin_socket` 保留域 wrapper、消息 store 和 active-page bridge，不复制选主实现。
- Namespace 与 path 不能混用。`forceNew: true`、`multiplex: false` 保证两域各有独立 Engine.IO transport；`autoConnect: false`、`reconnection: false` 让管理器控制连接与恢复。
- 握手使用对应域 `auth.authorization` 与 cookie；`recovery`、`tab_id` 只作观测提示，后台独立鉴权。
- 页面只注册消费者和订阅意图，不直接 `io()`，不操作管理器内部状态。普通业务 API 不控制连接；认证 wrapper 同步对应域 authorization/logout。

## 登录身份与连接数量

- 稳定登录会话为 JWT `sid`，用户身份为字符串 `sub`，token 的 `jti`/`exp` 可续签，Socket.IO/Engine.IO SID 每次连接产生；三者不可互换。JWT 客户端解码只作协调提示。
- 协调键是 `JSON.stringify([VITE_AUTH_STORAGE_KEY, domain, sub, sid])`；普通 token 更新不改键，重新登录/切换账号建立新边界，并隔离旧任务、消息与退出广播。
- 同源、同浏览器配置、同存储分区、同登录会话内，正常稳态每个有合格页面的域共享一条连接；两域同时活跃为 user 1 + admin 1，主标签可不同。
- 没有合格页面的域为 0。交接可能短暂重叠；不同浏览器/隐私分区/登录会话不承诺共享。两种转发均失败时每个合格标签独立连接，不保证单连接。

## 资格与取消顺序

- `lifecycle.ts` 的 `routeAuthDomain(route.matched)` 与 guard 共用 `requiresAuth` / `requiresAdminAuth`；使用成功导航后的已解析路由与 `router.isReady()`，不按 URL 前缀推断。
- 标签必须属于对应受保护域、有登录会话、可见、在线且生命周期有效，才参与选主、主动续签和重试。公开页/登录页不会因有 token 而主动建连。
- 路由、visibility、online/offline、pagehide/pageshow、freeze/resume 驱动资格；页面 composable 额外处理 mounted/activated/deactivated/unmounted。保持懒加载、重定向、历史恢复和 KeepAlive 的一致性。
- 失去资格或所有权：先取消校验、恢复/订阅任务和锁等待，再关闭 transport，最后释放所有权。获得锁、校验后、创建连接前重查会话、资格与任务版本；取消之外仍需迟到结果隔离。

## 所有权与真实异常降级

- 转发可用时优先 Web Locks 独占锁；只有持锁标签能建连，等待带可取消 AbortSignal。持锁期间广告租约过期不构成抢占依据。
- Locks 缺失、同步抛错或异步拒绝时，租约/心跳与标签 ID 确定性排序尽力收敛；不能宣称与独占锁有同等保证。
- BroadcastChannel 构造/发送失败时使用 storage event。正常广播也向可写存储发送同一消息 ID，以支持部分标签降级；接收方去重，避免 storage 回声循环。
- 存储不可用但广播可用时，内存状态与广播仍协作；两者都不能转发时跳过共享锁，各合格标签独立连接，避免永远等待主标签。
- 消息校验协议版本、来源、ID、域、稳定会话、完整协调键与 payload；拒绝旧会话/重复消息。不提供恰好一次传输保证。
- `StorageOverlay` 对写入/删除失败建立内存覆盖，退出 tombstone 遮蔽残留凭据。覆盖只存在于当前 document；整页刷新可能再读旧磁盘值，仍须后台校验。只读存储不能可靠传播新登录，接管可通过 HTTP 校验恢复同会话 token。

## 校验、续签与重试

- 首次、重建、接管与新登录先 `POST /api/{user|admin}/socket/session`；必须满足 `ApiResponse.code === 0` 且 `data.valid === true`，HTTP 2xx 本身不够。
- 同域同会话由所有者共享一个在途校验；连续 token 更新、storage 与恢复事件不能造成重复校验或握手。
- 健康连接和未超时、凭据未过期的握手不会被普通 token 更新拆除。续期点依据当前 transport 实际握手/已确认 `auth_update` 的 token，存储中的新 token 不能延后旧连接续期。
- 到续期点 HTTP 校验，使用有效期前进的最新凭据发送 `auth_update` 并等待 ACK，在原 transport 上更新。相同/倒退结果不覆盖新凭据；未推进有效期时等原到期点，避免零延迟循环。
- 结构化 `token_expired` 可主动恢复；明确 `session_invalid` 只退出对应域。HTTP 401 还须角色、失效标记和当前请求凭据一致；超时、transport 故障、503、429 保留登录并退避，不能靠错误文案判断退出。HTTP 细节见主 Skill 的 network reference。
- 每个旧事件/ACK/校验结果检查连接对象、会话与任务版本；旧连接和旧 HTTP 响应不能关闭新连接或影响另一域。
- 管理器统一指数退避，500ms 起点、±20% 抖动、最终上限 30s，成功重置；普通 token 更新不跳过故障退避，真正资格恢复可合并提前尝试。基线 HTTP 5s、握手 8s、协调心跳 5s、租约 15s、合并 60ms、续期提前 60s。
- 协调心跳、传输 ping 和登录续期分别管理；不以鼠标/键盘空闲断连，也不承诺浏览器睡眠或代理故障下永不断线。

## 页面同步与通知消费

- `api_notice` 是变化提示，权威数据通过鉴权 HTTP 读取。页面业务状态不跨标签缓存。
- 可恢复的资源读取使用 `usePageRefresh(domain, resource, { read, apply, error })`。资源键必须包含区分读取结果所需的资源/筛选/分页身份，同键消费者应使用等价读取契约；`read` 通过 API wrapper 传递 AbortSignal。
- 返回函数用于首次流程之外的手动刷新与通知同步意图；首次、资源切换、手动、通知、重试与恢复都走统一资格门禁，不另设无条件 fetch。
- 隐藏、离线、停用时记录 dirty/最高目标、取消请求，保留已有显示；重新合格时处理累积需求。可见、联网、pageshow 和连接恢复合并；已有同身份校准不再额外排快照，无需求时不轮询。
- 同 document 内同会话/资源共享在途读取，完成即丢弃；请求期间的新变化保留必要尾随刷新。应用响应前检查资源、会话、请求 generation、生命周期和当前资格。
- `RefreshCoordinator` 提供 `versionOf`、`complete`、`requiresCalibration`、`calibrate` 扩展；未来增量适配器必须完成必要分页，校准完成后才推进 loadedVersion。当前工单页面无版本协议，用 null 基线与完整 HTTP 校准，不虚构版本/分页接口。
- 使用对应域通知 hook；`ctx.getApiNotices(...)` 按准确最终 `api_uri` 过滤，详情同时匹配字符串化 `kid_for_api`。合并通知，成功记录同步意图后按策略 `ctx.removeConsumed(messages)`；失败重试由协调器保留需求。
- bridge 仅向合格活跃页面消费，store 上限 200 并按 `api_uri + kid_for_api` 去重；不直接操作内部 store，也不把通知当 API 响应。

## 订阅与遗漏补偿

- 所有者汇总有效页面的 `resource/baseline` 意图；同资源去重，基线取最慢有效页面，任一未知则为 null。只有最后一个消费者退出才真正 unsubscribe。
- subscribe/unsubscribe 都需 ACK、超时与失败处理；拒绝不记为已确认。重连/交接恢复意图，`calibrate: true` ACK 向对应资源传达校准需求，补偿快照与入房之间的间隙。
- 隐藏/停用暂停意图，重新加入必须校准。通用资源房间当前是扩展边界，既有业务通知仍走私有房间；订阅成功不授予业务资源权限。
- user 保留重新鉴权后补发、离线消息表与 `POST /api/user/socket/messages/pull`；SPA 尚无该 pull wrapper/主动调用。admin 无用户离线表，通过权威校准补偿。不要为所有广播自动增加逐用户离线存储。

## 双端变更与部署

修改 path、namespace、event、会话错误、订阅 ACK、`api_uri` 或补偿策略时检查 Python router/service/hub、Redis 与前端 manager/types/hooks。改 URL 时搜索发送方与全部通知过滤器。

允许 polling 的多 worker/节点部署须同 Engine.IO SID 亲和性；Redis 通知适配器不替代它。核对独立 Socket.IO CORS、cookie、升级头和大于传输心跳总时长的代理超时。握手中止/HTTP 400 需要响应正文、结构化错误和服务端对应记录，取证须脱敏。
