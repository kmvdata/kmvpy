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
- 当前 `package.json` 没有单元测试脚本；不要声称运行了不存在的测试。新增测试基础设施需要独立理由和任务范围。
- `bun run format` 会批量写文件，不把它当作只读检查；只在用户要求或变更范围可控时运行，并审阅 diff。
- 不通过关闭 strict、ESLint、checker 或规则来让检查通过。

## 契约与行为检查

- 路由：直接访问、刷新、鉴权跳转、安全 redirect、query/hash、fallback 和具名路由引用。
- HTTP：URL、方法、user/admin/generic HTTP client 选择、请求/响应泛型、nullable、KID string、empty data 和结构化错误。
- i18n：两种语言 key 集合一致；新文案、API fallback、aria/alt、Dialog/Notify 均已翻译。
- Auth：user/admin token、401、续签、logout、跨标签和登录回跳互不污染。
- Socket：path/namespace/event、过滤、KID 比较、去重、消费、刷新失败、重连和多标签行为。
- 页面：首次 loading、refresh、submit、empty、error、success、重复点击和请求竞态。

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
