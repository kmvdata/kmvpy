# i18n、Kmv 错误与可访问性

在新增用户可见文案、错误提示、表格列、选项、通知、对话框、aria/alt 文本或键盘交互时读取本文件。

## i18n

- 只维护 `zh-CN` 与 `en-US`，新增或修改 key 时两端结构必须一致。
- 页面文本、按钮、placeholder、校验、空态、错误态、通知、Dialog、tooltip、`aria-label`、`alt` 和 API fallback 全部走 i18n。
- 通用动作放 `common`；页面文案按业务域组织；同一业务概念保留一份权威 key。
- 切换语言后需要立即变化的数组、表格列、筛选项、导航显示值和派生说明使用 `computed` 或在 locale 变化时重建，不能在模块加载时固化翻译。
- 不把内部实现、CSS 说明或开发者清单写成用户可见帮助文本，除非产品需求明确要求。

## Kmv 错误

- 后端错误翻译位于 `src/i18n/<locale>/kmvApiError.ts` 的 `api.kmv.codes.<code>`。
- 使用 `extractKmvApiErrorPayload`、`resolveKmvApiUserMessage` 或 `useKmvApiErrorMessage` 形成统一提取与翻译链。
- 页面不得自行拼 Kmv code key，也不得直接显示未经解析的 `error.message` 或后端 `msg`。
- resolver 在未知 code 时可以按其集中策略回退后端 msg；这个行为不是页面绕开 i18n 的许可。
- 新增后端错误码时，两种语言同时增加相同 code key；后端错误定义同时遵循 `py-dev`。
- 保留 `ApiResponseError` 等结构化错误，不用普通 `Error` 覆盖 code/envelope。

## 可访问性

- icon-only 操作提供翻译后的可访问名称，通常同时提供 tooltip；装饰图标应避免制造无意义朗读。
- 自定义可点击元素必须支持键盘 Enter/Space、可见 focus 状态和正确语义；能用 Quasar button/link 时优先使用原生组件语义。
- 表单控件有可感知 label、错误说明和合理焦点顺序；Dialog 打开、确认和关闭行为可用键盘完成。
- 状态、风险和选中态不只依赖颜色；用文本、图标、形状或 ARIA 状态补充。
- 图片与品牌标记提供符合用途的 `alt`；纯装饰图像使用空 alt 或隐藏语义。
- 检查放大字体、窄屏和长文本下的阅读顺序、截断与点击目标。

## 检查方式

- 比较两套 locale 的 key 集合，防止结构漂移。
- 搜索新增的字符串字面量，区分用户文案、稳定协议值和开发日志。
- 对新增交互进行键盘遍历，并检查 focus-visible、可访问名称和错误反馈。
