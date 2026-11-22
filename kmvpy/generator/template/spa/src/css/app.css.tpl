/* Quasar/legacy bridge: structure and typography reference framework/theme tokens. */
:root {
  --spa-font-family: var(--kfw-font-family, Inter, 'PingFang SC', 'Microsoft YaHei', sans-serif);
  --spa-mono-font-family: 'Space Mono', ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
  --spa-bg: var(--bg-card, #ffffff);
  --spa-page-bg: var(--bg-main, #f3f6f4);
  --spa-surface: var(--bg-card, #ffffff);
  --spa-surface-mint: var(--bg-table-zebra, #ecfdf3);
  --spa-surface-muted: var(--bg-table-header, #f8fafc);
  --spa-surface-subtle: var(--border-light, #f1f5f9);
  --spa-border: var(--border-normal, #d1e7dd);
  --spa-border-strong: var(--primary, #a7d7c1);
  --spa-border-muted: var(--border-light, #e2e8f0);
  --spa-text: var(--text-main, #0f172a);
  --spa-text-strong: var(--text-main, #111827);
  --spa-text-heading: var(--text-main, #1f2937);
  --spa-text-body: var(--text-secondary, #4b5563);
  --spa-text-muted: var(--text-secondary, #64748b);
  --spa-text-subtle: var(--text-light, #9ca3af);
  --spa-primary: var(--primary, #15803d);
  --spa-primary-strong: var(--primary-active, #14532d);
  --spa-primary-hover: var(--primary-hover, #166534);
  --spa-primary-foreground: var(--text-on-primary, #ffffff);
  --spa-primary-soft: var(--bg-table-zebra, #dcfce7);
  --spa-primary-soft-2: var(--bg-table-header, #bbf7d0);
  --spa-primary-tint: var(--bg-table-zebra, #ecfdf3);
  --spa-accent: var(--primary-hover, #22c55e);
  --spa-info: var(--info, #0f766e);
  --spa-info-brand: var(--info, #0d9488);
  --spa-focus-ring: var(--focus-ring);
  --spa-danger: var(--status-error-text);
  --spa-danger-brand: var(--error, #dc2626);
  --spa-danger-bg: var(--status-error-bg);
  --spa-danger-soft: var(--status-error-bg);
  --spa-danger-border: var(--status-error-border);
  --spa-warn: var(--status-warning-text);
  --spa-warn-brand: var(--warning, #ca8a04);
  --spa-warn-bg: var(--status-warning-bg);
  --spa-warn-border: var(--status-warning-border);
  --spa-success: var(--success, #16a34a);
  --spa-success-strong: var(--status-success-text);
  --spa-success-bg: var(--status-success-bg);
  --spa-neutral-bg: var(--bg-table-header);
  --spa-neutral-text: var(--text-secondary);
  --spa-radius-xs: 4px;
  --spa-radius-sm: 6px;
  --spa-radius-md: 8px;
  --spa-radius-lg: 10px;
  --spa-radius-xl: 12px;
  --spa-shadow-none: var(--shadow-light, none);
  --spa-space-page-x: var(--kfw-space-md, 16px);
  --spa-space-page-y: var(--kfw-space-xl, 32px);
  --spa-space-content: var(--kfw-space-lg, 20px);
  --spa-font-size-display: var(--kfw-font-size-display, 32px);
  --spa-font-size-page-title: var(--kfw-font-size-page-title, 18px);
  --spa-font-size-section-title: var(--kfw-font-size-section-title, 16px);
  --spa-font-size-card-title: var(--kfw-font-size-card-title, 18px);
  --spa-font-size-card-value: var(--kfw-font-size-card-value, 20px);
  --spa-font-size-caption: var(--kfw-font-size-caption, 12px);
  --spa-font-size-overline: var(--kfw-font-size-overline, 10px);
  --spa-font-size-meta: var(--kfw-font-size-meta, 13px);
  --spa-font-size-small: var(--kfw-font-size-small, 12px);
  --spa-font-size-body: var(--kfw-font-size-body, 14px);
  --spa-font-size-title: var(--kfw-font-size-card-title, 18px);
  --spa-line-height-tight: var(--kfw-line-height-tight, 1.3);
  --spa-line-height-body: var(--kfw-line-height-body, 1.6);
  --spa-line-height-relaxed: var(--kfw-line-height-relaxed, 1.75);
  --spa-font-weight-regular: var(--kfw-font-weight-regular, 400);
  --spa-font-weight-medium: var(--kfw-font-weight-medium, 500);
  --spa-font-weight-bold: var(--kfw-font-weight-bold, 700);
  --spa-chart-green-1: var(--spa-primary-strong);
  --spa-chart-green-2: var(--spa-primary);
  --spa-chart-green-3: var(--spa-success);
  --spa-chart-green-4: var(--spa-accent);
  --spa-chart-teal: var(--spa-info);
  --bg-primary: var(--bg-main, #ffffff);
  --bg-secondary: var(--bg-header, #f8f9fa);
  --text-primary: var(--text-main, #333333);
  --text-muted: var(--text-light, #999999);
  --border: var(--border-normal, #eeeeee);
  --accent-1: var(--primary, #1677ff);
  --accent-2: var(--info, #0891b2);
  --accent-3: #7c3aed;
  --accent-gradient: linear-gradient(135deg, var(--accent-1), var(--accent-2), var(--accent-3));
  --accent-gradient-h: linear-gradient(90deg, var(--accent-1), var(--accent-2), var(--accent-3));
  --glow-green: rgba(22, 119, 255, 0.10);
  --glow-blue: rgba(8, 145, 178, 0.10);
  --glow-purple: rgba(124, 58, 237, 0.10);
  --surface-glass: rgba(255, 255, 255, 0.86);
  --surface-glass-strong: rgba(255, 255, 255, 0.94);
  --surface-field: rgba(255, 255, 255, 0.92);
  --surface-hover: rgba(22, 119, 255, 0.08);
  --surface-grid-line: rgba(15, 23, 42, 0.05);
  --status-info-text: #0958d9;
  --status-info-bg: rgba(22, 119, 255, 0.08);
  --status-info-border: rgba(22, 119, 255, 0.20);
  --status-success-text: #15803d;
  --status-success-bg: rgba(22, 163, 74, 0.10);
  --status-success-border: rgba(22, 163, 74, 0.24);
  --status-error-text: #b91c1c;
  --status-error-bg: rgba(220, 38, 38, 0.08);
  --status-error-border: rgba(220, 38, 38, 0.22);
  --status-warning-text: #b45309;
  --status-warning-bg: rgba(202, 138, 4, 0.10);
  --status-warning-border: rgba(202, 138, 4, 0.24);
  --admin-stat-accent: var(--accent-1);
  --admin-stat-positive: var(--success, #52c41a);
  --admin-stat-caution: var(--warning, #faad14);
  --admin-stat-info: var(--accent-2);
  --admin-stat-violet: var(--accent-3);
  --admin-border-mint: rgba(22, 119, 255, 0.24);
  --admin-border-info: rgba(8, 145, 178, 0.24);
  --tier-basic: #22c55e;
  --tier-pro: #eab308;
  --tier-vip: #ef4444;
}

html,
body,
#q-app {
  min-height: 100%;
}

body {
  margin: 0;
  color: var(--spa-text);
  font-family: var(--spa-font-family);
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-body);
  background: var(--spa-page-bg);
}

.spa-layout {
  background: var(--spa-page-bg);
}

.spa-header {
  background: var(--spa-bg);
  border-bottom: 1px solid var(--spa-border);
}

/* Teleported account menus share typography, colors and viewport bounds. */
.account-style-menu {
  width: var(--account-menu-width);
  max-width: calc(100vw - 16px);
  max-height: calc(100dvh - 16px);
  overflow-x: hidden;
  border: 1px solid var(--border-normal);
  box-shadow: var(--shadow-middle);
}

.account-style-menu__submenu {
  width: var(--account-submenu-width);
}

/* Keep sibling preference entries reachable below a narrow-screen popup. */
.account-style-menu__submenu-space {
  height: calc(var(--kfw-btn-medium-height) * var(--account-submenu-rows) + 14px);
}

.account-style-menu__trigger {
  min-width: 40px;
  min-height: 40px;
  flex-shrink: 0;
}

.account-style-menu__avatar {
  color: var(--text-on-primary);
  background: var(--control-primary);
}

.account-style-menu .q-item,
.account-style-menu .q-btn {
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-body);
  min-height: var(--kfw-btn-medium-height);
}

.account-style-menu .q-item__label--caption {
  font-size: var(--spa-font-size-caption);
  color: var(--text-secondary);
}

.account-style-menu .q-item__section--main {
  min-width: 0;
  overflow-wrap: anywhere;
}

.account-style-menu .q-item__section--avatar {
  min-width: 36px;
}

.account-style-menu .q-item__section--side {
  color: var(--text-secondary);
}

.account-style-menu [aria-checked="true"] .q-icon {
  color: var(--control-primary);
}

.account-style-menu :focus-visible,
.account-style-menu__trigger:focus-visible {
  outline: 2px solid var(--primary);
  outline-offset: -3px;
}

.spa-toolbar {
  padding: 10px 20px;
}

.home-layout__toolbar,
.user-layout__toolbar {
  gap: 12px;
}

.spa-toolbar__actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  margin-right: 12px;
}

.spa-brand {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.spa-brand__eyebrow {
  font-size: var(--spa-font-size-overline);
  letter-spacing: 0.28em;
  text-transform: uppercase;
  color: var(--spa-primary);
}

.spa-brand__title {
  font-size: var(--spa-font-size-section-title);
  font-weight: var(--spa-font-weight-bold);
  color: var(--spa-text);
}

.spa-page {
  padding: var(--spa-space-page-y) var(--spa-space-page-x) 48px;
}

.spa-shell {
  max-width: 1100px;
  margin: 0 auto;
}

.spa-hero {
  padding: 28px 32px;
  border: 1px solid var(--spa-border);
  border-radius: var(--spa-radius-xl);
  background: var(--spa-bg);
}

.spa-badge {
  display: inline-flex;
  padding: 4px 10px;
  border: 1px solid var(--spa-border-strong);
  border-radius: var(--spa-radius-sm);
  color: var(--spa-primary);
  font-size: var(--spa-font-size-caption);
  font-weight: 600;
  letter-spacing: 0.06em;
  text-transform: uppercase;
  background: var(--spa-surface-mint);
}

.spa-title {
  margin: 16px 0 8px;
  font-size: var(--spa-font-size-display);
  line-height: var(--spa-line-height-tight);
  color: var(--spa-text);
}

.spa-subtitle {
  max-width: 760px;
  font-size: var(--spa-font-size-body);
  color: var(--spa-text-muted);
  line-height: var(--spa-line-height-relaxed);
}

.spa-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  margin-top: 20px;
}

.spa-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
  gap: 16px;
  margin-top: 20px;
}

.spa-grid--home {
  grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
}

.spa-grid--auth-page,
.spa-grid--dashboard {
  grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
}

.spa-card {
  border-radius: var(--spa-radius-xl);
  background: var(--spa-surface);
  border-color: var(--spa-border) !important;
  box-shadow: var(--spa-shadow-none) !important;
}

.spa-card__label {
  font-size: var(--spa-font-size-caption);
  color: var(--spa-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.1em;
  font-weight: var(--spa-font-weight-medium);
}

.spa-card__value {
  margin-top: 8px;
  font-size: var(--spa-font-size-card-value);
  line-height: var(--spa-line-height-tight);
  font-weight: var(--spa-font-weight-bold);
  color: var(--spa-text);
}

.spa-card__hint {
  margin-top: 8px;
  color: var(--spa-text-muted);
  line-height: var(--spa-line-height-body);
  font-size: var(--spa-font-size-body);
}

.spa-dialog-card {
  width: min(100vw - 24px, 480px);
}

.spa-dialog-card--sm {
  width: min(100vw - 24px, 360px);
}

.spa-dialog-card--md {
  width: min(100vw - 24px, 520px);
}

.spa-auth-card {
  width: 100%;
}

/* 轻量信息条：替代深色 bg-dark */
.spa-banner {
  font-size: var(--spa-font-size-body);
  border: 1px solid var(--spa-border);
  color: var(--spa-text);
}

.spa-banner--info {
  background: var(--spa-surface-mint);
  border-color: var(--spa-border);
}

.spa-banner--success {
  background: var(--spa-primary-soft);
  border-color: var(--spa-border-strong);
  color: var(--spa-success-strong);
}

.spa-banner--error {
  background: var(--spa-danger-bg);
  border-color: var(--spa-danger-border);
  color: var(--spa-danger);
}

.spa-separator {
  background: var(--spa-border) !important;
}

.spa-inline-alert--error {
  background: var(--spa-danger-bg);
  color: var(--spa-danger);
  border: 1px solid var(--spa-danger-border);
}

.spa-inline-alert--warning {
  background: var(--spa-warn-bg);
  color: var(--spa-warn);
  border: 1px solid var(--spa-warn-border);
}

.spa-inline-alert--success {
  background: var(--spa-success-bg);
  color: var(--spa-success-strong);
  border: 1px solid var(--spa-border-strong);
}

/* 业务页内容区（列表/仪表等） */
.spa-content-area {
  flex: 1;
  overflow-y: auto;
  padding: var(--spa-space-content);
  background: var(--spa-page-bg);
}

.spa-section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 12px;
}

.spa-section-title {
  margin: 0;
  color: var(--spa-text-heading);
  font-size: var(--spa-font-size-section-title);
  line-height: var(--spa-line-height-tight);
  font-weight: var(--spa-font-weight-bold);
}

.spa-section-subtitle {
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-meta);
  line-height: var(--spa-line-height-body);
}

.spa-page-title,
.spa-dialog-title,
.spa-card-title,
.spa-list-title {
  margin: 0;
  color: var(--spa-text-heading);
  line-height: var(--spa-line-height-tight);
  font-weight: var(--spa-font-weight-bold);
}

.spa-page-title {
  font-size: var(--spa-font-size-page-title);
}

.spa-dialog-title,
.spa-section-title,
.spa-list-title {
  font-size: var(--spa-font-size-section-title);
}

.spa-card-title {
  font-size: var(--spa-font-size-card-title);
}

.spa-page-subtitle,
.spa-list-meta,
.spa-meta,
.spa-field-label,
.spa-field-value {
  color: var(--spa-text-muted);
  font-size: var(--spa-font-size-meta);
  line-height: var(--spa-line-height-body);
}

.spa-page-subtitle {
  margin: 0;
}

.spa-list-title {
  font-weight: var(--spa-font-weight-medium);
}

.spa-field-label {
  display: block;
  font-size: var(--spa-font-size-caption);
}

.spa-field-value {
  display: block;
  color: var(--spa-text-body);
  font-size: var(--spa-font-size-body);
}

.spa-overline {
  font-size: var(--spa-font-size-overline);
  font-weight: var(--spa-font-weight-bold);
  letter-spacing: 0.12em;
  text-transform: uppercase;
}

.spa-empty-state {
  padding: 32px 16px;
  color: var(--spa-text-muted);
  text-align: center;
  background: var(--spa-surface);
  border: 1px dashed var(--spa-border);
  border-radius: var(--spa-radius-xl);
}

.spa-muted {
  color: var(--spa-text-muted);
}

.spa-subtle {
  color: var(--spa-text-subtle);
}

.spa-btn-soft {
  color: var(--spa-primary);
  background: var(--spa-primary-soft);
  border-radius: var(--spa-radius-sm);
}

.spa-btn-soft:hover {
  background: var(--spa-primary-soft-2);
}

.spa-status,
.spa-risk {
  border-radius: 999px;
  font-size: var(--spa-font-size-caption);
  font-weight: var(--spa-font-weight-medium);
  padding: 2px 6px;
}

.spa-status--success,
.spa-risk--low {
  background: var(--spa-success-bg);
  color: var(--spa-success-strong);
}

.spa-status--warning,
.spa-risk--medium {
  background: var(--spa-warn-bg);
  color: var(--spa-warn);
}

.spa-status--danger,
.spa-risk--high {
  background: var(--spa-danger-bg);
  color: var(--spa-danger);
}

.spa-status--neutral {
  background: var(--spa-neutral-bg);
  color: var(--spa-neutral-text);
}

.spa-border-left--success {
  border-left-color: var(--spa-primary) !important;
}

.spa-border-left--warning {
  border-left-color: var(--spa-warn) !important;
}

.spa-border-left--danger {
  border-left-color: var(--spa-danger) !important;
}

.spa-progress-track {
  overflow: hidden;
  height: 6px;
  background: var(--spa-border-muted);
  border-radius: var(--spa-radius-xs);
}

.spa-progress-bar {
  height: 100%;
  border-radius: var(--spa-radius-xs);
}

.spa-progress-bar--g1 {
  background: var(--spa-chart-green-1);
}

.spa-progress-bar--g2 {
  background: var(--spa-chart-green-2);
}

.spa-progress-bar--g3 {
  background: var(--spa-chart-green-3);
}

.spa-progress-bar--g4 {
  background: var(--spa-chart-green-4);
}

.spa-progress-bar--teal {
  background: var(--spa-chart-teal);
}

.spa-table {
  color: var(--spa-text);
}

.spa-table .q-table thead th {
  color: var(--spa-text-muted);
  font-weight: 600;
  background: var(--spa-surface-muted);
}

.spa-table .q-table tbody td {
  color: var(--spa-text-body);
}

.spa-form-field .q-field__control,
.q-field--outlined.spa-form-field .q-field__control {
  background: var(--spa-surface);
  border-radius: var(--spa-radius-md);
}

.spa-form-field.q-field--focused .q-field__control::after {
  box-shadow: 0 0 0 2px var(--spa-focus-ring);
}

/* Extend the existing CSS bridge; do not enable Quasar Dark or alter Home. */
:where(.user-layout, .admin-layout, .account-style-menu, .q-dialog, .q-notifications) {
  --q-primary: var(--control-primary);
  --q-secondary: var(--accent-2);
  --q-accent: var(--accent-3);
  --q-positive: var(--status-success-text);
  --q-negative: var(--status-error-text);
  --q-info: var(--status-info-text);
  --q-warning: var(--status-warning-text);
}

:where(.user-layout, .admin-layout, .q-dialog, .q-menu) .q-btn.bg-primary,
.text-on-primary {
  color: var(--text-on-primary) !important;
}

:where(.user-layout, .admin-layout, .q-dialog, .q-notifications)
  :is(.bg-negative, .bg-positive, .bg-warning, .bg-info),
.text-on-status {
  color: var(--text-on-status) !important;
}

.text-main { color: var(--text-main) !important; }
.text-neutral { color: var(--workspace-text-muted) !important; }
.text-surface-muted { color: var(--bg-table-header) !important; }
.bg-surface-muted { background: var(--bg-table-header) !important; }

/* Form hints, borders and surfaces also resolve outside Layout portals. */
:where(.user-layout, .admin-layout, .q-dialog) .q-field {
  color: var(--text-main);
}
:where(.user-layout, .admin-layout, .q-dialog)
  :is(.q-field__native, .q-field__input, .q-field__prefix, .q-field__suffix) {
  color: var(--text-main);
}
:where(.user-layout, .admin-layout, .q-dialog)
  :is(.q-field__label, .q-field__marginal, .q-field__bottom) {
  color: var(--workspace-text-muted);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-field--outlined .q-field__control::before {
  border-color: var(--workspace-border);
}
:where(.user-layout, .admin-layout, .q-dialog)
  .q-field--outlined:hover .q-field__control::before {
  border-color: var(--control-primary);
}
:where(.user-layout, .admin-layout, .q-dialog)
  .q-field--outlined.q-field--error .q-field__control::before {
  border-color: var(--status-error-text);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-field--outlined .q-field__control {
  background: var(--surface-field);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-field--focused .q-field__control::after {
  box-shadow: 0 0 0 2px var(--focus-ring);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-field--error
  :is(.q-field__bottom, .q-field__control, .q-field__marginal) {
  color: var(--status-error-text);
}
:where(.user-layout, .admin-layout, .q-dialog, .q-menu) .q-separator {
  background: var(--border-normal);
}
:where(.user-layout, .admin-layout, .q-dialog) :is(.q-table__container, .q-table) {
  color: var(--text-main);
  background: var(--bg-card);
  border-color: var(--border-normal);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-table :is(th, td) {
  border-color: var(--border-normal);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-table th {
  color: var(--workspace-text-muted);
  background: var(--bg-table-header);
}
:where(.user-layout, .admin-layout, .q-dialog) .q-inner-loading {
  background: var(--surface-loading);
}
.q-dialog__backdrop { background: var(--mask); }
.q-tooltip {
  color: var(--tooltip-text);
  background: var(--tooltip-bg);
  font-size: var(--spa-font-size-caption);
}
.q-notification {
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-body);
}
.q-menu :is(.q-item, .q-field),
.q-dialog-plugin {
  font-size: var(--spa-font-size-body);
}
.q-menu .q-item__label--caption {
  color: var(--text-secondary);
  font-size: var(--spa-font-size-caption);
}
.q-menu .q-item__section--side { color: var(--text-secondary); }

:where(.user-layout, .admin-layout) .q-message-name {
  font-size: var(--spa-font-size-caption);
  color: var(--workspace-text-muted);
}
:where(.user-layout, .admin-layout) .q-message-stamp {
  font-size: var(--spa-font-size-caption);
  opacity: 1;
}

:where(.spa-layout, .q-dialog) :where(.q-btn, .q-item, .q-tab, .q-banner, .q-card, .q-field, .q-table),
:is(.user-layout, .admin-layout, .q-dialog) :is(.q-btn, .q-item, .q-tab, .q-banner, .q-card, .q-field, .q-table) {
  font-family: var(--spa-font-family);
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-body);
}

:where(.spa-layout, .q-dialog) :where(.q-field__native, .q-field__input, .q-field__label, .q-field__messages),
:is(.user-layout, .admin-layout, .q-dialog) :is(.q-field__native, .q-field__input, .q-field__label, .q-field__messages) {
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-body);
}

:where(.spa-layout, .q-dialog) :where(.q-badge, .q-chip, .q-item__label--caption),
:is(.user-layout, .admin-layout, .q-dialog) :is(.q-badge, .q-chip, .q-item__label--caption) {
  font-size: var(--spa-font-size-caption);
  line-height: var(--spa-line-height-body);
}

:where(.spa-layout, .q-dialog) .q-table thead th {
  font-size: var(--spa-font-size-caption);
  line-height: var(--spa-line-height-body);
}

:where(.spa-layout, .q-dialog) .q-table tbody td {
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-body);
}

:where(.text-h5, .text-h6, .text-subtitle1, .text-subtitle2, .text-body2, .text-caption) {
  line-height: var(--spa-line-height-body);
}

.text-h5 {
  font-size: var(--spa-font-size-page-title);
}

.text-h6,
.text-subtitle1,
.text-subtitle2 {
  font-size: var(--spa-font-size-section-title);
}

.text-body2 {
  font-size: var(--spa-font-size-body);
}

.text-caption {
  font-size: var(--spa-font-size-caption);
}

@media (max-width: 768px) {
  .spa-toolbar {
    padding: 10px 12px;
  }

  .spa-page {
    padding: 20px 12px 32px;
  }

  .spa-hero {
    padding: 20px 22px;
  }
}
