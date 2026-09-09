# 账户偏好与三主题改造验收记录

日期：2026-09-04。范围仅为 `__SPA_PROJECT_NAME__`，未修改后端、网络层、路由、鉴权存储或 Socket。

## 项目事实与边界

- 仓库及可读取父目录未找到 AGENTS.md；执行了仓库 spa-dev Skill 及对应 references。
- HomeLayout、UserLayout、AdminLayout 原本已经引用 AccountStyleMenu，继续使用这些调用方和 `accountKind` 域参数、`actions` 插槽，未复制菜单。
- 现有默认值仍为 `en-US / normal / dark`。存储键、framework_style boot、语言持久化接口均未改变。
- 当前没有 ConfigDisplayPreferencePage、darkMode 设置开关，也没有持仓、市场、知识库、analytics、subscription 或 SVG 业务图表。未新增这些页面、设置页或路由。“设置页三主题对齐/恢复默认”在本仓库不适用。
- 原工作区的 `.agents/skills/gen-prompt/SKILL.md` 删除与 `.vscode/settings.json` 修改未触碰。

## 待审 diff 分组

| 模块 | 文件 | 已实现内容 |
| --- | --- | --- |
| 共用账户菜单 | `src/components/AccountStyleMenu.vue` | 保留头像、身份、域专属导航和原退出分支；增加资料加载、错误/重试展示；移除三个 QSelect 和旧 controls 样式 |
| 二级菜单 | `src/components/AccountPreferenceItem.vue`（新增） | 三类偏好共用 QMenu/QItem；单项展开；勾选和 aria-checked；Enter/Space、上下键、左右键、Escape；焦点返回；窄屏预留展开区域以保持其他入口可点击；QResizeObserver 跟随字号变化重定位 |
| 偏好适配 | `src/composables/useStylePreferences.ts`（新增） | 读取既有偏好函数，以 MutationObserver 同步 DOM 偏好属性；卸载时 disconnect；所有选项文本 computed；语言使用全局 i18n，不建立第二个持久化状态源 |
| 共享主题 | `src/css/theme-{light,dark,eye}.css`、`src/css/app.css` | 补齐控件、前景、焦点、遮罩、tooltip、可读边框/次要文字语义；修复状态色别名；桥接 Quasar 表单、表格、浮层与通知；不启用 Quasar Dark |
| 字号及域外壳 | `src/css/layout-{normal,large}.css`、`src/css/{user,admin}.css` | 菜单尺寸 token；large 控件高度；域内字体桥接优先级；窄屏收紧 logo 展示、允许标题换行、隐藏重复副标题；浅色/护眼工作台 logo 使用主题渐变 |
| 用户页面 | `PersonalProfilePage.vue`、`UserWorkTicketsPage.vue` | 头像前景、消息两侧背景/文字、时间戳、状态色和固定灰色替换；字号语义；工单刷新/弹窗关闭可访问名称 |
| 管理页面 | `AdminLoginPage.vue`、`AdminUserListPage.vue`、`AdminWorkTicketsPage.vue`、`AdminDatabaseTablesPage.vue` | 登录页接入同一 CSS 桥接及密码按钮 aria；头像、通知动作、工单、状态徽章和表格语义配色 |
| 文案 | `src/i18n/{en-US,zh-CN}/index.ts` | 账户菜单可访问名称准确描述账户菜单，继续复用已有偏好与选项 key |

## 实际静态检查

所有 lint/build 均从 `__SPA_PROJECT_NAME__` 运行，未运行全仓格式化。

| 批次 | 命令 | 结果 |
| --- | --- | --- |
| 1：共用二级菜单 | `bun run lint`、`bun run build` | 首次 lint 通过；首次 build 指出菜单 anchor 类型不精确，修正后两项通过 |
| 2：共享主题/域样式 | `bun run lint`、`bun run build` | 通过 |
| 3：现有 personal / work-tickets / management / system 页面 | `bun run lint`、`bun run build` | 通过 |
| 4：浏览器发现的问题修正 | `bun run lint`、`bun run build` | 多轮复查通过；修复快速键盘焦点竞态、窄屏入口位移、字号改变后定位和控件字号覆盖 |
| 最终 | `bun run lint`、`bun run build`、`git diff --check` | 通过 |

- 仅对 AccountStyleMenu、AccountPreferenceItem、useStylePreferences 运行定向 Prettier。
- Bun 递归比较 i18n：英文 593 个叶子 key，中文 593 个，差集均为空。
- 扫描用户/管理页面（模板、脚本、scoped CSS）及 user.css/admin.css：无剩余颜色字面量、固定 white/black/grey 调色值；`dark` 只作为主题枚举/选择器保留。
- 全源变量名称扫描无颜色变量缺失、无直接自引用。Home IndexPage 原有 `--spa-font-size-h3`、`--spa-font-size-h4` 使用字号 fallback，未改变。静态名称覆盖不等同于所有登录页面的运行时作用域验收。
- 新增 8 个颜色语义 token 均在 light、dark、eye 显式定义。深色保留原背景、主文字和主色基调。
- AppLogo 的原品牌渐变保留用于公开页与原深色品牌表现，不承担状态或业务信息；浅色/护眼工作台覆盖为主题渐变。没有需要固定白色背景的外部文档画布消费者，未新增无用途的图表/文档 token。
- 未发现旧调色板组件；没有可删除的旧组件文件。旧账户 controls CSS 已移除，组件/Layout 无残留 QSelect 偏好控件。
- 构建仍提示已有 boot 模块静态/动态混用导入不会拆包，以及插件耗时提示；不影响构建成功，未为此改动网络层。
- package.json 没有测试脚本，未声称或执行项目单元测试。

## 实际浏览器覆盖

使用本项目独立开发服务 `http://localhost:9002`。9000 是另一个项目，未计入验证。9001 被占用，Quasar 自动选择 9002。

| 页面/流程 | 实际覆盖 |
| --- | --- |
| Home `/` | 已登录与早期未登录菜单展示；最终 light/dark/eye × normal/large × 1280×900、390×844 共 12 个组合的偏好值、勾选、菜单边界、整页宽度检查；公开内容回归 |
| User `/app/personal/profile` | 使用现有用户会话；同样的 12 个主题/字号/尺寸组合；资料与状态可读；直接深链与刷新后仍登录，保留偏好 |
| 三种偏好菜单 | 鼠标直接切换语言/字体/风格；窄屏子菜单下方展开且其他入口可点击；Enter/Space 选择、右键展开、左键/Escape 返回、上下移动；返回主入口和账户按钮；aria-expanded、aria-checked 与可访问名称 |
| 语言 | 中文/英文即时切换；当前值、选项、域导航同时更新；未固化初始化翻译 |
| User 工单 | 现有工单详情、双方历史消息、输入区、窄屏布局；新建 Dialog 打开/关闭与空提交本地必填提示；没有发送或创建工单 |
| User 帮助 | 现有帮助内容及直接路由正常展示；护眼大字号桌面抽查 |
| Admin 登录 | `/admin/users` 无管理员会话时跳转 `/admin/login?redirect=/admin/users`；管理员登录页三主题、大字号、1280×720 实际加载与配色检查 |
| 同页偏好同步 | 临时无 API、无登录绕过的双实例浏览器夹具：第一实例改 light、第二实例改 normal、第一实例改中文后两处均显示 `light / normal / zh-CN`；卸载重挂后两处一致；刷新后仍为已保存值 |

浏览器回归曾发现并修正：窄屏子菜单遮挡相邻入口、mousedown 关闭造成下一入口位移、快速键盘操作被延迟 focus 抢回、字号变化后菜单短暂越界。最终组合断言在浏览器绘制后检查真实尺寸，不以请求设定尺寸代替实际 viewport。

## 未执行项与验收限制

- 没有管理员登录会话，因此 AdminLayout 账户菜单、后台表格/数据库管理、管理工单及系统操作 Dialog 仅完成源码/构建检查，未冒充登录后的浏览器验证。
- 未测试用户/管理员退出（避免破坏会话），未由代理提交登录凭据；管理员 guard 跳转已检查，用户登录提交/回跳未独立操作。
- 未专门制造网络故障测试资料加载失败，也未触发真实业务 Notify；这些路径的语义样式已修改，仍需带相应状态进行现场验收。
- 工单不是完整的 12 组合逐项验收；实际消息和 Dialog 的深入视觉抽查主要为护眼/大字号/窄屏。管理员登录页不是管理员工作台验收。
- 本项目没有显示偏好设置页，因此菜单与设置页同步、设置页恢复默认不适用；双实例验证的是共享 composable 行为。
- 没有持仓/市场/知识库/业务 SVG 图表模块，不以其他项目或测试假数据冒充这些页面。

## 清理

- 原始偏好已恢复为英文、常规字号、深色，并在真实 Home 菜单中复核。
- 临时双实例 HTML/TS 夹具已删除；浏览器临时标签页和 viewport override 已清理。
- 未退出、清除或互借任何域的凭据，未修改工单数据。
