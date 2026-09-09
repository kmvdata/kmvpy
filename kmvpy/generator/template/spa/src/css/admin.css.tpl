/* ===== 管理端：与首页同色板、字体与营销变量（见 app.css 的 .signal-tracker-page 令牌块）===== */
.signal-tracker-page.signal-tracker-admin.admin-layout {
  /* Fallbacks mirror AdminLayout constants; runtime style keeps them easy to adjust. */
  --admin-drawer-width: 260px;
  --admin-layout-gap: 8px;
  --admin-layout-hidden-page-x: 138px;
}

.signal-tracker-page.signal-tracker-admin.admin-login-page .q-page-container,
.signal-tracker-page.signal-tracker-admin.admin-login-page .q-page {
  position: relative;
  z-index: 1;
}

@media (min-width: 1025px) {
  .signal-tracker-page.signal-tracker-admin.admin-layout .q-page-container>.spa-page {
    transition:
      padding-left 0.12s ease,
      padding-right 0.12s ease;
  }

  .signal-tracker-page.signal-tracker-admin.admin-layout--drawer-open .q-page-container>.spa-page {
    padding-left: var(--admin-layout-gap);
    padding-right: var(--admin-layout-gap);
  }

  .signal-tracker-page.signal-tracker-admin.admin-layout--drawer-hidden .q-page-container>.spa-page {
    padding-left: var(--admin-layout-hidden-page-x);
    padding-right: var(--admin-layout-hidden-page-x);
  }

  .signal-tracker-page.signal-tracker-admin.admin-layout .q-page-container>.spa-page>.spa-shell {
    width: 100%;
    max-width: none;
    margin-right: 0;
    margin-left: 0;
  }
}

.signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title {
  padding-left: 0;
  min-width: 0;
  white-space: normal;
}

/* 顶栏分区标题 */
.signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title .section-header-wrapper {
  margin-bottom: 0;
  min-width: 0;
}

.signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title .section-title {
  margin: 0 0 6px;
  font-size: var(--spa-font-size-page-title);
  font-weight: 700;
  line-height: var(--spa-line-height-tight);
}

/* 管理端任意区域：渐变标题字（顶栏与业务页共用） */
.signal-tracker-page.signal-tracker-admin .gradient-text {
  background: var(--accent-gradient);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

/* 业务页（.spa-page）分区标题：与顶栏结构一致时可复用 section-* 类名 */
.signal-tracker-page.signal-tracker-admin .spa-page .section-header-wrapper {
  margin-bottom: 14px;
}

.signal-tracker-page.signal-tracker-admin .spa-page .section-label {
  display: inline-block;
  font-size: var(--spa-font-size-caption);
  font-weight: 600;
  letter-spacing: 0.12em;
  text-transform: uppercase;
  color: var(--accent-1);
  margin-bottom: 6px;
}

.signal-tracker-page.signal-tracker-admin .spa-page .section-title {
  margin: 0 0 8px;
  font-size: var(--spa-font-size-page-title);
  font-weight: 700;
  line-height: var(--spa-line-height-tight);
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .spa-page .section-sub {
  margin: 0;
  font-size: var(--spa-font-size-small);
  color: var(--text-secondary);
  line-height: 1.5;
}

@media (max-width: 599px) {
  .admin-layout .admin-layout__logo-link .app-logo__wordmark {
    display: none;
  }

  .admin-layout .admin-layout__logo-link .app-logo {
    padding-inline: 0;
  }

  .signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title .section-sub {
    display: none;
  }

  .signal-tracker-page.signal-tracker-admin .spa-page .section-title {
    font-size: var(--spa-font-size-section-title);
  }

  .signal-tracker-page.signal-tracker-admin .spa-page .section-sub {
    font-size: var(--spa-font-size-overline);
  }
}

.signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title .section-sub {
  margin: 0;
  font-size: var(--spa-font-size-small);
  color: var(--text-secondary);
  line-height: var(--spa-line-height-body);
}

@media (max-width: 599px) {
  .signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title .section-title {
    font-size: var(--spa-font-size-section-title);
  }

  .signal-tracker-page.signal-tracker-admin .admin-layout__toolbar-title .section-sub {
    font-size: var(--spa-font-size-overline);
  }
}

.signal-tracker-page.signal-tracker-admin .admin-layout__logo-link {
  display: inline-flex;
  align-items: center;
  color: inherit;
  text-decoration: none;
}

.signal-tracker-page.signal-tracker-admin .q-header.spa-header {
  /* 勿用 position:relative，否则会破坏 Quasar q-header 的 fixed 顶栏行为 */
  z-index: 2;
  background: color-mix(in srgb, var(--bg-primary) 85%, transparent);
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  border-bottom: 1px solid var(--border);
}

.signal-tracker-page.signal-tracker-admin .spa-brand__eyebrow {
  color: var(--accent-1);
}

.signal-tracker-page.signal-tracker-admin .spa-brand__title {
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .sidebar {
  display: flex;
  flex-direction: column;
  min-height: 100%;
  padding: 10px 0 12px;
}

.signal-tracker-page.signal-tracker-admin .sb-section {
  padding: 0 8px 8px;
}

.signal-tracker-page.signal-tracker-admin .admin-layout__nav-section--system {
  order: 6;
}

.signal-tracker-page.signal-tracker-admin .admin-nav-section-label {
  color: var(--accent-1);
  font-size: var(--spa-font-size-small);
  font-weight: 600;
  letter-spacing: 0.08em;
  margin: 2px 0;
  padding-inline: 2px;
}

.signal-tracker-page.signal-tracker-admin .admin-nav-section-label:focus-visible {
  outline: 2px solid color-mix(in srgb, var(--accent-1) 50%, transparent);
  outline-offset: 2px;
}

.signal-tracker-page.signal-tracker-admin .nav-item {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 2px 0;
  padding: 10px 10px;
  border-radius: var(--spa-radius-xl);
  color: var(--text-secondary);
  text-decoration: none;
  cursor: pointer;
  user-select: none;
  transition:
    background 0.15s ease,
    color 0.15s ease;
}

.signal-tracker-page.signal-tracker-admin .nav-item:hover {
  color: var(--text-primary);
  background: var(--glow-green);
}

.signal-tracker-page.signal-tracker-admin .nav-item.active {
  color: var(--text-primary) !important;
  font-weight: 600;
  background: var(--bg-card);
  box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent-1) 28%, transparent);
}

.signal-tracker-page.signal-tracker-admin .nav-icon {
  flex-shrink: 0;
  width: 22px;
  height: 22px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: var(--accent-1);
}

.signal-tracker-page.signal-tracker-admin .nav-label {
  flex: 1;
  min-width: 0;
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-tight);
}

.signal-tracker-page.signal-tracker-admin .nav-chevron {
  font-size: 18px;
  width: 18px;
  height: 18px;
  flex-shrink: 0;
  opacity: 0.75;
  transition: transform 0.18s ease;
}

.signal-tracker-page.signal-tracker-admin .nav-item.is-expanded .nav-chevron,
.signal-tracker-page.signal-tracker-admin .admin-nav-section-label.is-expanded .nav-chevron,
.signal-tracker-page.signal-tracker-admin .nav-chevron.is-expanded {
  transform: rotate(90deg);
}

.signal-tracker-page.signal-tracker-admin .admin-layout__avatar-trigger {
  flex-shrink: 0;
}

.signal-tracker-page.signal-tracker-admin .admin-layout__avatar-trigger:focus-visible {
  outline: 2px solid color-mix(in srgb, var(--accent-1) 55%, transparent);
  outline-offset: 2px;
}

/* 管理端主内容：三主题共用语义变量。 */
.admin-layout,
.signal-tracker-admin-dialog {
  --text-muted: var(--workspace-text-muted);
  --spa-text-subtle: var(--workspace-text-muted);
}

:root:not([data-kfw-theme="dark"]) .admin-layout .app-logo {
  --logo-wordmark-gradient: var(--accent-gradient);
}

.admin-layout :is(.q-btn, .q-item, .nav-item, .q-tab):focus-visible {
  outline: 2px solid var(--control-primary);
  outline-offset: -2px;
}
.signal-tracker-page.signal-tracker-admin .spa-page {
  background: transparent;
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .spa-card {
  background: var(--bg-card);
  border-color: var(--border) !important;
  box-shadow: var(--spa-shadow-none) !important;
}

.signal-tracker-page.signal-tracker-admin .spa-section-title {
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .spa-section-subtitle {
  color: var(--text-secondary);
}

.signal-tracker-page.signal-tracker-admin .spa-card__label {
  color: var(--text-muted);
}

.signal-tracker-page.signal-tracker-admin .spa-card__value {
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .spa-card__hint {
  color: var(--text-secondary);
}

.signal-tracker-page.signal-tracker-admin .spa-banner--info {
  background: var(--status-info-bg);
  border-color: var(--status-info-border);
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .spa-banner--success {
  background: var(--status-success-bg);
  border-color: var(--status-success-border);
  color: var(--accent-1);
}

.signal-tracker-page.signal-tracker-admin .spa-banner--error {
  background: var(--status-error-bg);
  border-color: var(--status-error-border);
  color: var(--status-error-text);
}

.signal-tracker-page.signal-tracker-admin .spa-separator {
  background: var(--border) !important;
}

.signal-tracker-page.signal-tracker-admin .spa-inline-alert--error {
  background: var(--status-error-bg);
  color: var(--status-error-text);
  border-color: var(--status-error-border);
}

.signal-tracker-page.signal-tracker-admin .spa-inline-alert--warning {
  background: var(--status-warning-bg);
  color: var(--status-warning-text);
  border-color: var(--status-warning-border);
}

.signal-tracker-page.signal-tracker-admin .spa-inline-alert--success {
  background: var(--status-success-bg);
  color: var(--accent-1);
  border-color: var(--status-success-border);
}

.signal-tracker-page.signal-tracker-admin .spa-empty-state {
  background: var(--bg-secondary);
  border-color: var(--border);
  color: var(--text-secondary);
}

.signal-tracker-page.signal-tracker-admin .spa-muted {
  color: var(--text-secondary);
}

/* data-table/HTML 表格「操作」列表头与单元格居中（详见 .admin-table-th--actions / .admin-table-td--actions） */
.signal-tracker-page.signal-tracker-admin th.admin-table-th--actions {
  text-align: center;
}

.signal-tracker-page.signal-tracker-admin td.admin-table-td--actions {
  text-align: center;
  vertical-align: middle;
}


.signal-tracker-page.signal-tracker-admin .spa-card .q-item {
  color: var(--text-primary);
}

.signal-tracker-page.signal-tracker-admin .spa-card .q-item__label--caption {
  color: var(--text-secondary);
}

/* Teleport 弹窗不在 .signal-tracker-page 内：用令牌类挂接同一套变量与表面 */
.signal-tracker-admin-dialog.spa-card {
  background: var(--bg-card);
  border-color: var(--border) !important;
  color: var(--text-primary);
}

/* 后台弹窗主题：Teleport 出页面后仍复用三主题令牌 */
.signal-tracker-admin-dialog.spa-dialog-card {
  background: var(--bg-card);
  border-color: var(--border) !important;
  color: var(--text-primary);
  box-shadow: var(--shadow-dark);
}

/* 标题和分割线跟随当前主题 */
.signal-tracker-admin-dialog.spa-dialog-card .spa-dialog-card__title {
  color: var(--text-primary);
}

.signal-tracker-admin-dialog.spa-dialog-card .q-separator {
  background: var(--border) !important;
}

.signal-tracker-admin-dialog.spa-card.admin-dialog--scroll {
  max-height: 80vh;
  overflow-y: auto;
}

.signal-tracker-admin-dialog .spa-section-title {
  color: var(--text-primary);
}

.signal-tracker-admin-dialog .spa-muted {
  color: var(--text-secondary);
}

.signal-tracker-admin-dialog .spa-separator {
  background: var(--border) !important;
}
