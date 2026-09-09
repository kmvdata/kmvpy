---
name: spa-dev
description: Use for designing, implementing, reviewing, or explaining any __SPA_PROJECT_NAME__ frontend change — including Quasar/Vue 3/TypeScript pages, home/user/admin routes and layouts, navigation, DTO/API/auth contracts, i18n and Kmv errors, Socket.IO behavior, CSS/theme/font-size layers, responsive interaction, accessibility, dependencies, and build verification. This is the authoritative skill for all work under __SPA_PROJECT_NAME__.
---

# __SPA_PROJECT_NAME__ 前端开发

把本 Skill 作为 `__SPA_PROJECT_NAME__` 工作的唯一前端架构与流程入口。先应用主文件中的边界，再按任务读取匹配的 reference；不要把仓库中的遗留硬编码、旧路由或越域实现复制成新范式。

## 使用协议

1. 先识别访问域 `home|app|admin`，以及是否涉及 route、contract、auth、socket、i18n、interaction 或 styling。
2. 根据下表完整读取所有匹配的 reference；多项命中时全部读取，并在行动前读完。
3. 先检查真实文件、直接调用方和最终后端契约，再设计或修改；`package.json`、lockfile、Quasar 配置和实际代码优先于 README。
4. 只实现受影响范围，不顺带重写 Socket、多标签页、全局 CSS 或其他遗留债务。
5. 任何 `__PY_PROJECT_NAME__` 编辑都同时使用 `py-dev`；后端可见契约变更必须双端同步。
6. 实现或评审任务交付前读取 `verification.md`；纯解释任务按需读取。

## Reference 路由

| 任务范围 | 必读 reference |
|---|---|
| 定位文件、依赖、Bun、Quasar/Vite、boot、环境变量、运行基线 | [`references/repository-map.md`](references/repository-map.md) |
| route、guard、redirect、Layout、drawer、导航、页面入口 | [`references/routing-and-navigation.md`](references/routing-and-navigation.md) |
| DTO、API wrapper、Axios、ApiResponse、auth、URL/方法、后端契约 | [`references/network-and-contracts.md`](references/network-and-contracts.md) |
| i18n、Kmv 错误、用户文案、aria/alt、键盘与 focus | [`references/i18n-and-accessibility.md`](references/i18n-and-accessibility.md) |
| Socket.IO、`api_notice`、页面刷新、多标签页、离线补偿 | [`references/sockets.md`](references/sockets.md)；涉及 API 时同时读取 network reference |
| Vue 页面、组件、表单、列表、状态、Dialog、Notify、响应式交互 | [`references/pages-and-interactions.md`](references/pages-and-interactions.md) |
| CSS、token、主题、字号模式、访问域样式与视觉响应式 | [`references/styling.md`](references/styling.md) |
| 实现交付、代码评审、构建、契约和视觉检查 | [`references/verification.md`](references/verification.md) |

## 技术基线

- 使用 Quasar SPA、Vue 3、TypeScript strict、Vite、Vue Router、Pinia、Axios、Vue I18n 和 Socket.IO client。
- 默认使用 Bun，Node >= 22.22.0；以当前 `package.json`、`bun.lock` 和 `quasar.config.ts` 为准。
- 保持 `App.vue` 作为顶层 router outlet，页面入口集中于 `src/router/routes.ts`。
- 优先复用 Quasar、现有组件、composable、DTO、API、i18n key 和 CSS token；不引入第二套 UI/样式/状态框架。
- 不关闭 TypeScript、ESLint 或 Quasar checker，也不降级依赖来绕过错误。

## 核心架构

```text
route -> guard -> layout -> page/component -> ApiXxx -> user/admin/generic HTTP client -> Axios -> backend
socket api_notice -----------------------> page handler -> authoritative API refresh
```

| 层 | 职责 |
|---|---|
| Router/Guard | 集中页面入口、Layout 绑定、鉴权和安全 redirect |
| Layout | toolbar、drawer、导航、当前标题与 `router-view` |
| Page/Component | 页面状态、交互、数据呈现和反馈 |
| DTO/API | 后端传输形状、URL/方法、对应身份的 HTTP client 与结构化错误 |
| Socket | 刷新信号、对应域鉴权、多标签页协作 |
| i18n/CSS | 用户文案、错误翻译、语义样式、主题与字号模式 |

## 访问域边界

| 域 | 主要路径 | 身份边界 |
|---|---|---|
| `home` | `/`、`/auth`、`/login` | 公开外壳；认证动作仍选择对应 user/admin client |
| `app` | `/app/**` | user guard、auth helper、API client、Socket `/ws` |
| `admin` | `/admin/login`、`/admin/**` | admin guard、auth helper、API client、Socket `/admin_ws` |

- 严格隔离 user/admin 的 API client、鉴权存储、登录跳转、route guard、Socket 和 logout 生命周期。
- DTO 是传输契约，不是权限能力：完全相同的跨域形状保留一个权威定义；域专属形状不得冒充共享契约。
- transport JSON 字段保持后端 `snake_case`，nullable 使用 `T | null`，KID/BIGINT 使用 `string`；TypeScript 方法和本地状态使用 `camelCase`。
- 页面只调用 API wrapper，不直接调用 raw Axios/`fetch` 或手写鉴权头；API wrapper 不管理 UI 状态、Dialog、Notify、路由或业务缓存。
- 认证 wrapper 可以按既有边界同步对应域 Socket authorization/logout；普通业务 API 不操作 Socket 生命周期。
- Socket `api_notice` 只触发 API 刷新，不作为业务数据源；页面处理后按策略移除已消费消息。
- Layout 不承载业务表单、列表、详情或页面请求。
- 所有用户可见文本和错误都经 i18n/Kmv 链处理，两种语言同步维护。
- 样式遵循 layout/theme/app/access-area/scoped 分层；访问区共享样式分别落在 `home.css`、`user.css`、`admin.css`，并验证 `normal|large`、`light|dark|eye` 与窄屏/桌面。

## 红线

- [ ] user/admin client、auth、guard、login、Socket 与 logout 未交叉。
- [ ] 页面入口只在 `routes.ts` 注册，Layout 没有业务 UI 或数据加载。
- [ ] 页面/组件没有 raw Axios、`fetch`、手写 auth/device header 或后端 URL。
- [ ] DTO 的 snake_case、nullable、KID 和共享权威定义与后端一致。
- [ ] API wrapper 没有 UI/业务状态，结构化错误未被普通 `Error` 覆盖。
- [ ] 用户文案、fallback、Kmv code、aria/alt 在 `zh-CN` 与 `en-US` 中一致。
- [ ] Socket 仍是刷新信号，页面使用正确域 hook 并处理消费/去重。
- [ ] CSS 进入正确层，未新增第二套视觉体系，主题/字号/响应式可用。
- [ ] strict、lint、build/checker 未被关闭；验证结果和未测风险明确。

## 条件式工作流

1. 明确访问域、用户任务、页面状态、后端契约和受影响入口。
2. 读取所有匹配 reference，检查同主题页面、组件、API、DTO、i18n、Socket 与样式消费者。
3. 先同步 DTO/API 与后端契约，再实现页面状态和交互；没有后端变化时不要假设新字段或路由。
4. 注册 route；只有需要稳定入口时才更新 Layout 导航。
5. 补齐两种语言、Kmv 错误、可访问名称和危险操作反馈。
6. 仅在后端会发送刷新通知时接入对应域 Socket handler。
7. 按样式分层实现视觉与响应式，不让局部修复污染共享 token。
8. 读取 `verification.md`，运行与风险匹配的检查并审阅最终 diff。
