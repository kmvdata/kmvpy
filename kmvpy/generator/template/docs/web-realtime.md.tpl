# Web 实时连接、多标签页和页面恢复

本实现沿用 Quasar SPA / Vue 3 / Vue Router / Axios / Socket.IO client，以及 FastAPI / kmvpy / python-socketio / Redis。没有新增业务模型、SharedWorker、跨标签页业务缓存或广播离线表；不涉及生产部署、真实账号和敏感配置。

## 架构职责与身份边界

- `network/realtime/manager.ts` 是每个权限域的统一连接管理器，管理所有权、HTTP 校验、握手、续签、退避、消息转发与订阅 ACK。`socket/user_socket.ts` 和 `admin_socket/admin_socket.ts` 只创建对应域实例。
- `realtime/lifecycle.ts` 与鉴权守卫共用 `routeAuthDomain`，根据匹配路由记录的 `requiresAuth` / `requiresAdminAuth` 判断受保护域。最终路由导航和 `router.isReady()` 后更新；兼容懒加载、重定向、历史恢复和 KeepAlive 页面停用。
- `realtime/session.ts` 提供登录会话解析及存储覆盖。JWT 的 `sub` 保持字符串，避免 BIGINT 精度损失。客户端解码只辅助协调，服务器独立验签并校验登录会话与 cookie。
- `RefreshCoordinator` / `usePageRefresh` 把同步意图和 HTTP 读取分开；两个现有工单页面的列表、详情、首次加载、切换、手动刷新、通知与恢复都接入它。其余业务页面没有在本轮改写数据模型或加载逻辑。
- Python 的 `RealtimeHub` 承担会话与订阅协调；`RealtimeService` 提供入口；Infra 提供 Cookie/HTTP 适配、Redis 原子保护和 HTTP 指标。保留已有用户私有房间、离线消息表与 HTTP pull，管理通知不写用户离线表。

三种身份彼此独立：

| 身份 | 生命周期 | 用途 |
| --- | --- | --- |
| 登录会话 JWT `sid` | 重新登录或切换账号时变化 | 协调和认证会话边界 |
| access JWT `jti` / `exp` | 同一登录会话中可续签 | HTTP 与握手凭据 |
| Socket.IO namespace SID / Engine.IO SID | 每次真实连接变化 | 传输会话与连接清理 |

协调键为 `JSON.stringify([VITE_AUTH_STORAGE_KEY, domain, sub, sid])`。两域拥有独立登录存储、锁、广播、消息、订阅、校验、重试和退出生命周期。切换登录会话会通知旧会话失效并取消旧任务。正常 token 更新不会改变协调身份，也不会主动拆除健康连接或未超时的握手。

## 连接数量与资格

| 场景（同源、同一浏览器配置和存储分区） | 正常稳态真实连接数 |
| --- | --- |
| 公开页、登录页、未登录，或某域没有合格页面 | 对应域 0 |
| 多个合格用户页、同一用户登录会话 | user 1 |
| 多个合格管理页、同一管理登录会话 | admin 1 |
| 两域均有合格页面 | user 1 + admin 1，主标签可不同 |
| 广播与存储都无法转发 | 每个合格标签页各 1；不保证单连接 |
| 不同浏览器、独立配置、隐私分区、不同登录会话 | 独立协调，不承诺共享 |

只有当前已解析受保护域、有效登录会话、可见、在线且生命周期有效的页面参与选主和主动续签。全局 boot 初始化不等于建连。`visibilitychange`、online/offline、pagehide/pageshow、freeze/resume 与路由结果共同驱动资格。

失去资格先取消校验和订阅任务、取消锁等待，关闭真实连接，再释放所有权。页面刷新也先取消请求并增加生命周期版本；显示数据保留。其他合格标签可接管；最后一个合格页面离开时允许连接数为零。关闭和接管在服务端观察上可能短暂重叠，没有“任何时刻绝对一条”的承诺。

用户 namespace `/ws`，管理 namespace `/admin_ws`；两者的底层 transport path 都是 `/ws/socket.io`。`forceNew: true`、`multiplex: false` 明确建立两个独立 Engine.IO transport；namespace 不是 transport path。

## 所有权与降级

支持且转发可用时使用 Web Locks 独占锁；锁持有回调退出才释放所有权。获得锁、HTTP 校验后、建连前均检查资格、会话和任务版本。排队请求带 AbortSignal，退出或离开页面后不能迟到建连。锁持有者不会因为广告租约过期或收到另一条租约被撤销。

BroadcastChannel 构造或发送异常会落到 storage event；正常广播也向可写存储转发同一消息 ID，使部分标签故障时仍可互通并去重。消息包含协议版本、消息 ID、来源标签、权限域、会话和完整协调键；校验结构，拒绝旧会话和重复消息。维护广播、通知和本地存储事件不会形成回声循环。

Web Locks 缺失、同步抛错或异步拒绝时，采用租约、心跳和标签 ID 排序竞争，稳态收敛，但属于尽力协调。存储不可用而广播正常时仍能用内存和广播协调。二者都不可转发时跳过共享锁，各合格标签独立连接，确保有通知通道。

写失败会建立内存覆盖，包括退出 tombstone；读取不会回退到残留磁盘凭据。内存覆盖随当前 document 消失：整页刷新后，失败删除的旧凭据可能重新出现，服务器仍会校验真实会话。只读存储下跨标签正常续签可在接管后的 HTTP 校验恢复最新 token；新登录无法依赖磁盘传播，其他标签可能需要重新登录。广播本身不作为权限依据。

降级中的消息转发不持久化业务数据，不提供恰好一次交付。锁获取失败、广播构造失败、发送失败、读写失败均有实际行为测试。

## 校验、续签与错误

两个域分别提供 `POST /api/{user|admin}/socket/session`，使用与业务 API 相同的 HTTP 鉴权依赖和自动续签响应头。首次连接、断线重建、接管和新会话都先校验，再用最新凭据握手。

单个所有者最多一个在途校验，超时/失去资格可取消。Socket.IO 内建重连关闭；外层统一退避。续签依据是当前 transport 握手或已确认 `auth_update` 实际使用的 JWT 到期时间，存储中出现更晚 token 不能推迟它。

到续签点进行 HTTP 校验；token 有效期确实前进后，用带 ACK 的 `auth_update` 在原 transport 上更新鉴权。服务器验证角色、签名、cookie、Redis 登录会话以及身份不变，再替换到期任务。相同/倒退续签结果不能覆盖更新 token；无有效期推进时等到原到期点，避免零延迟循环。网络故障时健康连接可继续到原凭据到期，失败不会无期限延长旧凭据。

| 错误 | 行为 |
| --- | --- |
| access 到期 | HTTP 用有效登录会话恢复；Socket 返回 `token_expired` 可重建 |
| 明确会话或权限失效 | HTTP 401 + `X-Auth-Role` + `X-Auth-Error: session_invalid`，或 Socket 结构化 `session_invalid`，只退出相应域 |
| 超时、普通 transport、503、429、代理错误 | 保留登录，指数退避与抖动 |
| Redis 临时故障且 access 已过期 | HTTP 503，保留客户端登录并等待恢复 |

既有认证在 Redis 故障时允许验签通过的未过期 JWT 短暂降级；无法提供即时撤销检查，access 到期后必须等待 Redis 恢复。资源保护的 allow/deny 策略在认证之后执行，不跳过验签或角色检查。

不通过错误文本中的 `401` 判断退出。HTTP 请求保留所用凭据快照；旧 token 的迟到 401 和旧登录的续签头不会影响新凭据。续签头需同一会话并推进 JWT `exp`。连接事件和 ACK 校验 transport 对象、会话和任务版本，旧连接无法断开新连接。

## 页面刷新和订阅补偿

默认 `api_notice` 仅表达变化，页面通过鉴权 HTTP 权威读取。页面隐藏、离线或停用时记录 dirty 和最高目标版本；不发起首次、通知、恢复或重试读取。再次合格时合并恢复事件执行必要读取；没有 dirty 不轮询。

60ms 合并窗口；同一浏览器标签内同一会话/资源的消费者共享在途读取，读取完成即丢弃流程结果，没有跨标签业务缓存。已有校准中的恢复事件不重复安排快照；请求期间的新变化保留一次必要尾随读取。响应应用前检查资源、会话、请求 generation、生命周期和当前资格，忽略迟到数据。

未来版本协议的可插拔边界为 `versionOf`、`complete`、`requiresCalibration`、`calibrate`。`read` 适配器必须完成必要增量分页后才返回完整结果；未完成、版本不可信、倒退、未追上目标或 reset 时调用权威校准。在校准完成前不推进 loadedVersion。当前业务没有版本握手，基线为 null，使用完整权威读取；合成测试验证了不完整/重置结果的校准和版本推进。

主标签汇总有效页面的订阅意图，按 resource 去重；有版本时取最落后基线，任一未知基线则用 null。其他页面仍需要资源时不会 unsubscribe。订阅/取消都有 ACK 和超时，拒绝不记为成功，失败后再协调；重连清空确认表并恢复意图。

服务端通用订阅房间按已鉴权域、用户和资源 hash 构造，不直接接受客户端任意房间名。订阅意图本身不授予业务权限。当前业务通知仍走原用户/管理私有房间；通用资源房间是将来通知适配的边界。ACK 返回 `calibrate: true` 并向相应资源消费者转发校准需求，避免在订阅确认前读取完快照导致间隙；当前页面在连接恢复/重新激活时也通过 HTTP 校准，补偿 admin 无离线表及隐藏期间的遗漏。新业务若发布特定资源通知，仍需在业务授权层校验资源访问权限，不可把订阅成功视为授权。

## 时序配置与资源保护

前端基线（`ManagerOptions` 可配置）：HTTP 校验 5s，Socket 握手 8s，退避起点 500ms、±20% 抖动、上限 30s，心跳 5s、租约 15s，事件合并 60ms，续签提前 60s。传输 ping 与登录续签独立；没有鼠标/键盘操作不会断连。普通 token 更新不会跳过故障退避，真实资格恢复可提前合并尝试。浏览器睡眠、代理和网络故障仍可能断连。

`AppConfig.realtime_protection` 示例（只展示配置契约，本轮未改实际部署配置）：

```yaml
realtime_protection:
  mode: observe                 # off | observe | enforce
  failure: allow                # allow | deny；仅 enforce 执行拒绝
  connections: 8               # 每域/用户/登录会话，不是全球单用户一条
  attempts_per_minute: 60
  subscriptions: 200
  subscription_ops_per_minute: 240
  http_per_minute: 300
  ttl_seconds: 90
```

默认 observe，因为没有生产容量或压力证据；额度预留正常交接与多设备余量，两个域不共用额度。enforce 才返回结构化限制（Socket `rate_limited` / HTTP 429）；Redis 故障时默认 allow，配置 deny 可拒绝资源分配，不清理有效登录。

Redis 使用服务器 TIME、Lua 原子准入/频率/订阅额度、唯一随机连接标识、续租和 TTL。同身份键位于同一 Redis Cluster hash slot。初始化失败回滚、主动断开与正常退出释放自身成员；进程消失靠 TTL；迟到续租不复活过期成员，旧清理不能删除新连接。不同真实进程共享同一 Redis 额度。

观测记录连接尝试、初始化、接受、断开、初始化失败、重建尝试/成功、续签、订阅/取消/频率、超额，以及权威 HTTP 次数、响应字节、耗时、原子操作等待和失败。活跃连接/订阅由 TTL 有序集合读取。重建标记和 tab ID 仅为客户端辅助排障提示，不作为鉴权或额度依据。共享存储故障降级有节流日志；故障期间无法把指标可靠写入 Redis，需采集进程日志。指标保存 24h，不记录完整 JWT、cookie 或业务正文。

## 部署核实与排障

仓库 develop/release 配置实际均为 1 worker。`biu` 使用已安装 kmvpy Nginx 模板：HTTP/1.1、Upgrade/Connection 升级头、proxy_read_timeout/proxy_send_timeout 都为 300s；当前 Engine.IO 默认 ping_interval 25s + ping_timeout 20s，300s 明显更大。history 路由需要 SPA index 回退。FastAPI 和独立 Socket.IO 的 CORS 现在使用相同允许来源策略，响应头暴露续签字段与结构化认证字段。

当前允许 polling 再升级 WebSocket。未来多节点/多 worker 必须把同一 Engine.IO SID 的 polling/upgrade 请求送至同一处理节点；Redis pub/sub 通知适配器不能替代会话亲和性。没有在本轮搭建或验证生产负载均衡。

握手中止或 HTTP 400 应保存请求 path、namespace、transport、HTTP 状态与响应正文中的结构化错误，并关联服务端时间与连接标识；仅凭浏览器堆栈无法确定原因。日志和取证必须脱敏凭据。资料：[Socket.IO client options](https://socket.io/docs/v4/client-options/)、[多节点会话亲和性](https://socket.io/docs/v4/using-multiple-nodes/)、[Web Locks 取消等待](https://developer.mozilla.org/en-US/docs/Web/API/LockManager/request)。

## 验证证据与复现

2026-10-03，本机完成：

- 前端 26 个行为用例：两域共享/隔离、路由/隐藏/离线资格、锁排队取消、交接、广告租约不能撤销原生锁、实际接口异常降级、慢握手续签、原续期点、旧事件/HTTP 响应隔离、ACK 拒绝、慢消费者基线、只读退出、消息结构/去重，以及刷新合并、尾随请求、迟到结果、版本校准。
- 后端 11 个行为用例：临时签名 JWT + cookie + Redis 会话，撤销与过期恢复、Redis 故障 503、同会话续签、初始化失败回滚，原子连接/订阅/HTTP 额度和策略隔离；8 个独立 Python 进程并发准入（上限 3 时恰好 3 成功），TTL 清理和过期续租拒绝，并实际终止正在续租的独立进程验证崩溃回收。
- 真实 Chromium + polling/WebSocket Socket.IO + Redis，本机合成服务 21 项断言：四标签两域各 1、两个独立 Engine.IO SID、公开页 0、真实 ACK、通知后各页面必要读取、关闭接管、路由离开/返回、真实 offline/online、撤销域隔离、锁拒绝/广播构造/发送/只读存储降级与完全隔离时两标签各 1。
- pagehide/pageshow 在无头浏览器中通过显式事件注入覆盖；无头 Chromium 的原生前后台可见性/系统睡眠/BFCache 缓存命中没有验收。本机合成服务使用测试 cookie 名称与临时密钥，省略现有业务离线表 hook，没有把它描述为真实账号或生产 Cookie/CORS 验证。
- ESLint、strict Vue/TypeScript checker + Quasar build、Python compileall、git diff --check 完成。构建保留原有 boot 模块同时静态/动态导入警告，没有关闭 checker 或降低依赖。

复现（独立 Redis 端口 16389，不使用已有业务 Redis）：

```sh
redis-server --bind 127.0.0.1 --port 16389 --save '' --appendonly no
cd __PY_PROJECT_NAME__
PYTHONPATH=. .venv/bin/python -m unittest discover -s tests -p test_realtime.py
PYTHONPATH=. .venv/bin/python tests/realtime_fixture.py
```

另开本机终端：

```sh
cd __SPA_PROJECT_NAME__
bun run test
bun run lint
VITE_API_BASE_URL=http://127.0.0.1:18761 VITE_AUTH_STORAGE_KEY=__PROJECT_NAME__-realtime-test bun run build
PLAYWRIGHT_MODULE=/absolute/path/to/playwright node tests/browser-acceptance.mjs
```

浏览器脚本可通过 `CHROME_EXECUTABLE` 指定本机 Chromium；Playwright 可用时直接用默认模块名。合成服务只绑定 127.0.0.1:18761，不读取部署 yaml、真实密钥或账号；现有工单接口只返回空列表，没有虚构新业务系统。

未执行：真实账号、生产 HTTPS/CORS/代理、线上多 worker 亲和性、Safari/Firefox/隐私分区、原生可见性/系统睡眠、业务离线表数据库回放及压力测试。没有生产容量结论，也不承诺永不断线、恰好一次或跨存储分区单连接。未来资源授权/版本/增量分页协议需使用上述适配边界和真实业务契约验证。
