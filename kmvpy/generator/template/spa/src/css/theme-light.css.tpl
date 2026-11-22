/* ==========================================================================
   KFW visual theme: light
   Visual layer only. Do not add layout dimensions, spacing or positioning here.
   ========================================================================== */

:root {
  /* Global visual variables */
  --bg-main: #ffffff;
  --bg-card: #ffffff;
  --bg-header: #f8f9fa;
  --bg-footer: #f8f9fa;
  --bg-table-header: #f8f9fa;
  --bg-table-zebra: #fafafa;
  --text-main: #333333;
  --text-secondary: #666666;
  --text-light: #999999;
  --text-link: #1677ff;
  --text-link-hover: #4096ff;
  --text-link-active: #0958d9;
  --text-link-disabled: #bfbfbf;
  --text-on-primary: #ffffff;
  --primary: #1677ff;
  --primary-hover: #4096ff;
  --primary-active: #0958d9;
  --success: #52c41a;
  --warning: #faad14;
  --error: #ff4d4f;
  --info: #1677ff;
  --border-normal: #eeeeee;
  --border-light: #f5f5f5;
  --border-error: #ffccc7;
  --shadow-light: 0 2px 8px rgba(0, 0, 0, 0.06);
  --shadow-middle: 0 6px 18px rgba(0, 0, 0, 0.10);
  --shadow-dark: 0 12px 32px rgba(0, 0, 0, 0.16);
  --mask: rgba(0, 0, 0, 0.45);
  --focus-ring: rgba(22, 119, 255, 0.35);
  --control-primary: #1264d0;
  --text-on-status: #ffffff;
  --surface-loading: rgba(255, 255, 255, 0.72);
  --tooltip-bg: #333333;
  --tooltip-text: #ffffff;
  --workspace-text-muted: #666666;
  --workspace-border: #c9cdd3;

  /* Signal Tracker visual aliases consumed by legacy layouts/pages. */
  --bg-primary: var(--bg-main);
  --bg-secondary: var(--bg-header);
  --text-primary: var(--text-main);
  --text-muted: var(--text-light);
  --border: var(--border-normal);
  --accent-1: var(--primary);
  --accent-2: #0891b2;
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
  --admin-stat-positive: var(--success);
  --admin-stat-caution: var(--warning);
  --admin-stat-info: var(--accent-2);
  --admin-stat-violet: var(--accent-3);
  --admin-border-mint: rgba(22, 119, 255, 0.24);
  --admin-border-info: rgba(8, 145, 178, 0.24);
  --tier-basic: #22c55e;
  --tier-pro: #eab308;
  --tier-vip: #ef4444;
}

body,
.kfw-app {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-main);
}

a,
.kfw-link {
  color: #1677ff;
  color: var(--text-link);
}

a:hover,
.kfw-link:hover {
  color: #4096ff;
  color: var(--text-link-hover);
}

a:active,
.kfw-link:active {
  color: #0958d9;
  color: var(--text-link-active);
}

a[aria-disabled="true"],
.kfw-link--disabled {
  color: #bfbfbf;
  color: var(--text-link-disabled);
  cursor: not-allowed;
}

.kfw-layout,
.kfw-page {
  background: #ffffff;
  background: var(--bg-main);
}

.kfw-layout__header,
.kfw-header,
.kfw-navbar {
  color: #333333;
  color: var(--text-main);
  background: #f8f9fa;
  background: var(--bg-header);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-layout__footer,
.kfw-footer,
.kfw-tabbar {
  color: #666666;
  color: var(--text-secondary);
  background: #f8f9fa;
  background: var(--bg-footer);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-layout__sider,
.kfw-divider,
.kfw-tabs,
.kfw-list__item,
.kfw-collapse,
.kfw-collapse__body {
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-card,
.kfw-modal__panel,
.kfw-drawer__panel,
.kfw-action-sheet,
.kfw-picker {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-card);
  border-color: #eeeeee;
  border-color: var(--border-normal);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  box-shadow: var(--shadow-light);
}

.kfw-card__footer,
.kfw-modal__footer,
.kfw-modal__header {
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-text--secondary,
.kfw-card__meta,
.kfw-list__meta,
.kfw-form__help,
.kfw-breadcrumb,
.kfw-placeholder {
  color: #666666;
  color: var(--text-secondary);
}

.kfw-text--light,
.kfw-empty {
  color: #999999;
  color: var(--text-light);
}

.kfw-button {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-card);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-button:hover,
.kfw-pagination__item:hover,
.kfw-nav-menu__item:hover,
.kfw-tabbar__item:hover {
  color: #1677ff;
  color: var(--primary);
  border-color: #1677ff;
  border-color: var(--primary);
}

.kfw-button:active,
.kfw-pagination__item:active {
  color: #0958d9;
  color: var(--primary-active);
  border-color: #0958d9;
  border-color: var(--primary-active);
}

.kfw-button--primary,
.kfw-button.kfw-is-active,
.kfw-pagination__item.kfw-is-active,
.kfw-nav-menu__item.kfw-is-active,
.kfw-steps__index.kfw-is-active {
  color: #ffffff;
  color: var(--text-on-primary);
  background: #1677ff;
  background: var(--primary);
  border-color: #1677ff;
  border-color: var(--primary);
}

.kfw-button--primary:hover {
  background: #4096ff;
  background: var(--primary-hover);
  border-color: #4096ff;
  border-color: var(--primary-hover);
}

.kfw-button--primary:active {
  background: #0958d9;
  background: var(--primary-active);
  border-color: #0958d9;
  border-color: var(--primary-active);
}

.kfw-button--text {
  color: #1677ff;
  color: var(--primary);
  background: transparent;
  border-color: transparent;
}

.kfw-button[disabled],
.kfw-is-disabled {
  color: #999999;
  color: var(--text-light);
  background: #f5f5f5;
  background: var(--border-light);
  border-color: #eeeeee;
  border-color: var(--border-normal);
  opacity: 0.7;
}

.kfw-input,
.kfw-select,
.kfw-date-picker,
.kfw-textarea {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-card);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-input:hover,
.kfw-select:hover,
.kfw-date-picker:hover,
.kfw-textarea:hover {
  border-color: #4096ff;
  border-color: var(--primary-hover);
}

.kfw-input:focus,
.kfw-select:focus,
.kfw-date-picker:focus,
.kfw-textarea:focus {
  border-color: #1677ff;
  border-color: var(--primary);
  outline: 2px solid rgba(22, 119, 255, 0.18);
}

.kfw-input[aria-invalid="true"],
.kfw-select[aria-invalid="true"],
.kfw-date-picker[aria-invalid="true"],
.kfw-textarea[aria-invalid="true"],
.kfw-form__item--error .kfw-input {
  border-color: #ffccc7;
  border-color: var(--border-error);
}

.kfw-checkbox__input,
.kfw-radio__input,
.kfw-switch__track {
  accent-color: #1677ff;
  accent-color: var(--primary);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-switch__track {
  background: #f5f5f5;
  background: var(--border-light);
}

.kfw-switch__thumb {
  background: #ffffff;
  background: var(--bg-card);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06);
  box-shadow: var(--shadow-light);
}

.kfw-switch--checked .kfw-switch__track {
  background: #1677ff;
  background: var(--primary);
  border-color: #1677ff;
  border-color: var(--primary);
}

.kfw-upload {
  color: #666666;
  color: var(--text-secondary);
  background: #ffffff;
  background: var(--bg-card);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-upload:hover {
  border-color: #1677ff;
  border-color: var(--primary);
}

.kfw-table {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-card);
}

.kfw-table th {
  color: #666666;
  color: var(--text-secondary);
  background: #f8f9fa;
  background: var(--bg-table-header);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-table td {
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-table tbody tr:nth-child(even) td {
  background: #fafafa;
  background: var(--bg-table-zebra);
}

.kfw-tag,
.kfw-badge {
  color: #1677ff;
  color: var(--primary);
  background: rgba(22, 119, 255, 0.08);
  border-color: rgba(22, 119, 255, 0.20);
}

.kfw-tag--success,
.kfw-badge--success,
.kfw-status--success {
  color: #52c41a;
  color: var(--success);
  background: rgba(82, 196, 26, 0.10);
  border-color: rgba(82, 196, 26, 0.30);
}

.kfw-tag--warning,
.kfw-badge--warning,
.kfw-status--warning {
  color: #faad14;
  color: var(--warning);
  background: rgba(250, 173, 20, 0.12);
  border-color: rgba(250, 173, 20, 0.30);
}

.kfw-tag--error,
.kfw-badge--error,
.kfw-status--error {
  color: #ff4d4f;
  color: var(--error);
  background: rgba(255, 77, 79, 0.10);
  border-color: rgba(255, 77, 79, 0.30);
}

.kfw-tag--info,
.kfw-badge--info,
.kfw-status--info {
  color: #1677ff;
  color: var(--info);
  background: rgba(22, 119, 255, 0.08);
  border-color: rgba(22, 119, 255, 0.20);
}

.kfw-tooltip,
.kfw-toast,
.kfw-notify {
  color: #ffffff;
  color: var(--text-on-primary);
  background: rgba(51, 51, 51, 0.96);
  border-color: rgba(51, 51, 51, 0.96);
  box-shadow: 0 6px 18px rgba(0, 0, 0, 0.10);
  box-shadow: var(--shadow-middle);
}

.kfw-notify--success,
.kfw-toast--success {
  background: #52c41a;
  background: var(--success);
  border-color: #52c41a;
  border-color: var(--success);
}

.kfw-notify--warning,
.kfw-toast--warning {
  background: #faad14;
  background: var(--warning);
  border-color: #faad14;
  border-color: var(--warning);
}

.kfw-notify--error,
.kfw-toast--error {
  background: #ff4d4f;
  background: var(--error);
  border-color: #ff4d4f;
  border-color: var(--error);
}

.kfw-modal__mask,
.kfw-drawer__mask {
  background: rgba(0, 0, 0, 0.45);
  background: var(--mask);
}

.kfw-tabs__item {
  color: #666666;
  color: var(--text-secondary);
  border-color: transparent;
}

.kfw-tabs__item:hover,
.kfw-tabs__item.kfw-is-active,
.kfw-tabbar__item.kfw-is-active,
.kfw-breadcrumb__item.kfw-is-active {
  color: #1677ff;
  color: var(--primary);
  border-color: #1677ff;
  border-color: var(--primary);
}

.kfw-pagination__item,
.kfw-steps__index,
.kfw-back-top,
.kfw-header__hamburger {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-card);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-back-top:hover {
  color: #ffffff;
  color: var(--text-on-primary);
  background: #1677ff;
  background: var(--primary);
  border-color: #1677ff;
  border-color: var(--primary);
}

.kfw-loading__spinner {
  border-color: #eeeeee;
  border-color: var(--border-normal);
  border-top-color: #1677ff;
  border-top-color: var(--primary);
}

.kfw-action-sheet__item,
.kfw-picker__item {
  color: #333333;
  color: var(--text-main);
  border-color: #eeeeee;
  border-color: var(--border-normal);
}

.kfw-action-sheet__item:hover,
.kfw-picker__item:hover {
  background: #f8f9fa;
  background: var(--bg-header);
}

/* Quasar bridge: keeps generated template pages aligned with the theme. */
.q-layout,
.q-page {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-main);
}

.q-header,
.q-footer,
.q-drawer {
  color: #333333;
  color: var(--text-main);
  background: #f8f9fa;
  background: var(--bg-header);
}

.q-card,
.q-menu,
.q-dialog__inner > div {
  color: #333333;
  color: var(--text-main);
  background: #ffffff;
  background: var(--bg-card);
}
