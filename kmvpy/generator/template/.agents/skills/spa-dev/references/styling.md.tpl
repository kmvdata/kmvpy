# CSS、主题、字号与响应式

在修改颜色、排版、间距、组件尺寸、共享 class、主题、字号模式或响应式布局时读取本文件。

## 样式层职责

- `layout-normal.css`：基础排版、字号、行高、间距、尺寸、布局、边框宽度/样式和结构 token。
- `layout-large.css`：large 字号模式的变量和必要几何覆盖。
- `theme-light.css`：浅色视觉变量与状态色基线。
- `theme-dark.css`、`theme-eye.css`：相对浅色主题的必要视觉覆盖。
- `app.css`：Quasar/遗留桥接、共享 `.spa-*`/`.kfw-*` 语义类和全局结构衔接。
- `home.css`：公开首页与认证域样式。
- `user.css`、`admin.css`：对应访问域的共享 layout/page 样式。
- Vue `<style scoped>`：单个页面或组件特有的结构、网格、高度和响应式例外。

不要把颜色、阴影或渐变放入 layout 字号层，也不要把通用尺寸、间距或定位放入 theme 层。

## 动态模式

`framework_style` boot 通过 `src/utils/frameworkStyle.ts` 动态加载：

- `layout-normal.css` 或 `layout-large.css`；
- `theme-light.css`、`theme-dark.css` 或 `theme-eye.css`。

新主题必须加入 `themeFiles`/`ThemeName`，新字号模式必须加入对应映射和类型，并检查 localStorage 兼容。普通页面不要自行插入主题 stylesheet。

## 放置决策

1. 先复用 Quasar props/utilities、现有 CSS 变量、`.spa-*` 和 `.kfw-*`。
2. 页面独有的网格列、局部高度、画布、图表、固定图标盒和断点可以放 scoped style。
3. 多页面会复用的结构、字号、间距或控件尺寸提升到 `layout-normal.css` 或 `app.css`。
4. large 模式差异写入 `layout-large.css`，不要用 viewport 直接缩放字体。
5. 颜色和状态视觉先进入 `theme-light.css`，再为 dark/eye 只覆盖必要值。
6. 只服务单一访问域的共享 selector 放 `user.css` 或 `admin.css`。

“禁止硬编码”针对重复设计值和主题/字号语义，不禁止确有局部含义的几何常量。若同一值跨页面重复、随主题变化或随字号模式变化，应提取为 token。

## 设计与响应式规则

- app/admin 界面保持可扫描、行为可预测，优先现有视觉语言，不新增第二套 design system。
- 避免 card 套 card；card 用于重复项、独立工具或 Dialog 中被框定的内容。
- focus-visible 必须可见；状态不能只靠颜色；对比度在三种主题中都可辨认。
- 普通页面不产生整体横向滚动；确实无法折叠的表格使用局部 overflow wrapper。
- grid/flex 设置清晰的 min/max 与换行策略；toolbar action、filter 和 pagination 在窄屏仍可操作。
- 验证 `normal|large` 与 `light|dark|eye` 的组合，检查按钮、tab、表格、Dialog、菜单和长文本溢出。
- 新 class 名表达访问域和语义，不只描述孤立视觉；不要复制明显属于遗留产品的 selector 作为新命名规范。

## 修改顺序

先完成 DOM/交互结构，再选择已有 token/class，最后新增最小样式。修改共享 token 后搜索所有消费者，并对 home/app/admin 三域做回归；不要为修一个页面无意改变全站主题语义。
