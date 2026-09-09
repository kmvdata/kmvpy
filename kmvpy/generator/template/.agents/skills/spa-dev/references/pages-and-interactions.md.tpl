# Vue 页面、组件与交互状态

在创建或修改页面、表单、列表、详情、Dialog、通知、Pinia 状态或响应式交互时读取本文件。

## Vue 与状态边界

- 优先使用 `<script setup lang="ts">`、Composition API 和 `import type`。
- 避免 `any`；对运行时外部数据先作为 `unknown` 缩窄，不把可信的编译期 JSON import 一概声明为 unknown。
- 页面局部状态使用 `ref/reactive/computed`；只有多个独立页面需要共享且生命周期确实跨页时才引入 Pinia store。
- 页面负责加载、刷新、提交、选择和反馈；可复用组件通过 props/events/slots 工作，不自行拼业务 URL。
- 抽取 composable 时让它封装可复用生命周期或状态机，不用它隐藏访问域或网络边界。

## 内容页结构

- 挂载在 User/Admin Layout 下的内容页以 `q-page` 为根，并复用 `.spa-page`、`.spa-shell`、`.spa-shell--wide` 或现有业务 shell。
- 公开页和独立登录页可使用与其外壳匹配的结构，不机械套用内容页模板。
- 第一屏直接呈现任务、数据或自然空态；用户/管理工作台不增加与任务无关的营销外壳。
- Layout 只提供外壳；业务表单、列表、详情和加载逻辑留在 page/component。

## 异步状态

每个数据流程按实际需要区分：

- 首次 loading：没有可展示的旧数据。
- refresh：保留旧内容，给出轻量刷新状态。
- submit/action pending：只禁用受影响动作，防止重复提交。
- empty：说明当前没有数据，并在存在自然下一步时提供动作。
- error：显示经 Kmv/i18n 解析的反馈，并在可恢复时提供重试。
- success：稳定更新本地内容，并给出与操作重要性匹配的反馈。

使用 `try/catch/finally` 或等价状态机保证成功、失败和取消路径都恢复 pending 状态。避免请求竞态让旧响应覆盖新筛选条件；需要时用请求序号、AbortController 或现有去重机制。

## Quasar 与交互

- 优先使用现有 Quasar form/table/dialog/notify/navigation 组件和项目语义类，不自造第二套 primitive。
- 不可逆或高影响操作用 `Dialog.create` 明确说明对象和影响；确认按钮使用风险语义，取消保持安全默认。
- 成功操作使用 `$q.notify` 或现有统一反馈；静默刷新不反复弹通知。
- icon-only button 提供 i18n `aria-label` 和 tooltip；固定工具栏、计数器和操作位保持尺寸稳定，避免 loading 文案造成跳动。
- 表单显示字段级校验，提交失败保留用户输入；只在成功后重置或关闭。
- 列表/表格的筛选、分页、选择和详情状态要在移动端仍可到达；列无法折叠时使用有意设计的横向滚动容器。
- 跳转优先使用具名 Vue Router 目标；链接行为不要伪装成普通 button，反之亦然。

## 响应式与文案

- 同时设计窄屏和桌面布局，不用 viewport 宽度缩放字体。
- 工具栏、筛选区、分页、Dialog 和主要动作在窄屏下不被遮挡；普通页面避免整体横向滚动。
- 长英文、长中文、空值、异常值和大字号模式下仍保持信息层级。
- 用户可见文本、校验、通知、tooltip 和可访问名称全部遵循 `i18n-and-accessibility.md`。
