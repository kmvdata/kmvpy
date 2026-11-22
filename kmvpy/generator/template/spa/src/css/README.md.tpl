# KFW CSS Framework

## 目录结构

```text
src/css/
  app.css
  layout-normal.css
  layout-large.css
  theme-light.css
  theme-dark.css
  theme-eye.css
src/utils/frameworkStyle.ts
src/boot/framework_style.ts
```

## 使用方式

`framework_style` boot 文件会在应用启动时自动插入动态样式：

- `#kfw-font-size-link`：加载 `layout-normal.css` 或 `layout-large.css`
- `#kfw-theme-link`：加载 `theme-light.css`、`theme-dark.css` 或 `theme-eye.css`

页面代码中可直接调用：

```ts
import { setFontSizeMode, setTheme } from 'src/utils/frameworkStyle';

setFontSizeMode('large');
setTheme('eye');
```

选择会写入 `localStorage`，下次打开页面自动恢复。

## 新增主题

1. 复制 `theme-light.css` 为 `theme-your-name.css`。
2. 只修改 `:root` 中的视觉变量和必要的状态色透明度。
3. 不要在主题文件中新增尺寸、间距、定位或字体大小。
4. 在 `src/utils/frameworkStyle.ts` 中引入新文件并加入 `themeFiles`。

## 修改字体大小

- 通用结构、尺寸、间距和常规字体 token 改 `layout-normal.css`。
- 增大字体版优先只覆盖 CSS 变量；确实需要扩大控件内部元素时，才补少量同名结构选择器。
- 页面文字使用 `spa-page-title`、`spa-section-title`、`spa-list-meta` 等语义类，避免局部硬编码字号。
- 不要在字体大小文件中写颜色、背景、阴影、渐变。

## 修改配色

- 背景、文字、边框色、阴影、遮罩、状态色只改 `theme-*.css`。
- 主题文件应能与 `layout-normal.css` 和 `layout-large.css` 任意组合。
- 如需兼容旧页面，优先通过 `app.css` 的 `--spa-*` 变量桥接，不要重复写业务页面选择器。

## 常见问题

- 切换后无变化：确认 `framework_style` 已加入 `quasar.config.ts` 的 `boot` 数组。
- 字体只变行高不变大小：检查页面或 Quasar 组件是否写死了 `font-size`，应改用 `spa-*` 语义类或 token。
- 某个组件颜色不对：检查主题文件是否遗漏该组件状态，或旧页面是否使用了未桥接的业务变量。
- 移动端横向滚动：表格请包一层 `.kfw-table-wrap`；普通栅格在移动端会自动变为单列。
- 增大字体版点击区域过小：检查是否使用了原生控件但没有套用 `.kfw-button`、`.kfw-checkbox`、`.kfw-radio` 或 `.kfw-switch`。
