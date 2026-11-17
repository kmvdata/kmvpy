# SPA 验证与交付

实现任务交付前、代码评审形成结论前读取本文件。纯解释任务仅在用户要求测试或合规方案时读取。

## 变更前后核对

- 明确 home/app/admin 域、受影响路由、API 契约、i18n、Socket 与样式层。
- 搜索直接调用方、具名路由、DTO 消费者、Socket `api_uri` 过滤器和共享 CSS token 使用方。
- 把现有违规视为遗留债务；不复制，也不在无关任务中扩大重构。
- 检查最终 diff 只包含任务相关文件，并保留用户已有修改。

## 静态检查

从仓库根目录执行：

```bash
cd __SPA_PROJECT_NAME__
bun run lint
bun run build
```

- `build` 同时覆盖 Quasar/Vite 构建与配置中的 Vue TypeScript checker。
- 当前 `bun run test` 运行 `tests/realtime.test.js`；修改鉴权、实时协作或刷新调度时运行并按受影响行为补充用例。纯文档改动核对路径/契约与 diff 即可，不为未变实现重复构建。
- `bun run format` 会批量写文件，不把它当作只读检查；只在用户要求或变更范围可控时运行，并审阅 diff。
- 不通过关闭 strict、ESLint、checker 或规则来让检查通过。

## 契约与行为检查

- 路由：直接访问、刷新、鉴权跳转、安全 redirect、query/hash、fallback 和具名路由引用。
- HTTP：URL、方法、user/admin/generic HTTP client 选择、请求/响应泛型、nullable、KID string、empty data 和结构化错误。
- i18n：两种语言 key 集合一致；新文案、API fallback、aria/alt、Dialog/Notify 均已翻译。
- Auth：user/admin token、401、续签、logout、跨标签和登录回跳互不污染。
- Socket：path/namespace/event、过滤、KID 比较、去重、消费、刷新失败、重连和多标签行为。
- 页面：首次 loading、refresh、submit、empty、error、success、重复点击和请求竞态。

## 实时与恢复验证

从 `__SPA_PROJECT_NAME__` 运行 `bun run test`。用例应验证可观察行为，不能只匹配源码字符串：

- 同会话多标签稳态共享、两域底层独立；一域退出/故障不影响另一域，公开页 0、路由离开/隐藏/离线/关闭后交接。
- 并发独占、等待锁取消、持锁不受广告租约抢占；Locks 抛错/拒绝、BroadcastChannel 构造/发送失败、存储读写失败与完全不能转发的实际行为。
- 慢握手连续续签、原 transport 续期点、故障退避不被 token 更新跳过；旧 Socket 事件、旧 HTTP 401/续签、旧登录会话隔离与只读退出。
- 隐藏/停用恢复不请求、返回补偿、多恢复事件合并、在途读取共享、必要尾随刷新、资源/生命周期迟到结果拒绝。
- subscribe/unsubscribe 拒绝/超时不记成功，最慢有效基线保留，交接/断线/重新加入与校准 ACK 的遗漏补偿；未来版本适配只用合成契约验证，不伪造业务协议。

真实浏览器验收入口是 `tests/browser-acceptance.mjs`，配套 `__PY_PROJECT_NAME__/tests/realtime_fixture.py`、临时签名密钥/测试 cookie 和独立本机 Redis。按仓库 [Web 实时连接文档](../../../../docs/web-realtime.md) 启动并构建对应测试环境；可用 `PLAYWRIGHT_MODULE` / `CHROME_EXECUTABLE` 指定已安装运行时。合成服务仅本机使用，不发布或连接真实账号配置，验收后关闭自己启动的服务。

模拟运行时测试不能代替真实浏览器/实时传输。报告分别说明合成服务、真实账号、生产代理与压力测试；注入 pagehide/pageshow 不等于原生后台可见性、BFCache 命中或系统睡眠已验收。记录实际断言与未执行原因，不固化历史测试数量或推断生产容量。

## 视觉与交互检查

UI 或 CSS 变化后运行应用并实际检查，而不只依赖 build：

- 至少覆盖一个桌面宽度和一个窄屏宽度；复杂表格/toolbar 增加临界宽度。
- 覆盖 `normal`、`large` 字号，以及 `light`、`dark`、`eye` 三种主题中所有受影响状态。
- 检查长文本、空值、错误、loading、Dialog、菜单、focus-visible、键盘路径和 icon-only 名称。
- 观察整体与局部横向滚动、布局跳动、遮挡、截断、对比度和点击目标。
- 有可用浏览器自动化时用它复现关键流程并保存必要截图；不要把截图检查替代真实交互断言。

## 分层复核

- 页面/组件没有 raw Axios、`fetch` 或手写鉴权头。
- user/admin client、auth、guard、login 和 Socket 没有交叉。
- API wrapper 没有 UI 状态、Dialog、Notify、业务缓存或普通业务 Socket 副作用。
- Layout 没有业务表单、列表、详情和数据加载。
- transport DTO 保持 snake_case、正确 nullable 与 KID string；共享 DTO 没有重复定义。
- 用户可见错误通过 Kmv/i18n 链解析，没有新增单语言 fallback。
- CSS 改动位于正确层，未把通用设计值散落到 scoped style。

## 交付

从仓库根目录运行 `git diff --check`，检查 `git status --short` 和最终 diff。说明实际运行的命令、结果、未执行项及剩余风险；不要引用不存在的 `fullstack-qa` 或其他验证 Skill。
