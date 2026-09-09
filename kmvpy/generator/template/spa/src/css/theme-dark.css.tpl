/* ==========================================================================
   KFW visual theme: dark
   Visual layer only. Imports the shared selector map, then swaps variables.
   ========================================================================== */

@import "./theme-light.css";

:root {
  /* Global visual variables: extracted from home/admin/user dark shells. */
  --bg-main: #070e1c;
  --bg-card: #0c1a2e;
  --bg-header: #0a1628;
  --bg-footer: #0a1020;
  --bg-table-header: #0a1628;
  --bg-table-zebra: rgba(255, 255, 255, 0.02);
  --text-main: #f0f2f5;
  --text-secondary: #8b8fa3;
  --text-light: #555872;
  --text-link: #00d4aa;
  --text-link-hover: #74f3d9;
  --text-link-active: #00b894;
  --text-link-disabled: #555872;
  --text-on-primary: #070e1c;
  --primary: #00d4aa;
  --primary-hover: #74f3d9;
  --primary-active: #00b894;
  --success: #22c55e;
  --warning: #fbbf24;
  --error: #f87171;
  --info: #00b4ff;
  --border-normal: rgba(255, 255, 255, 0.08);
  --border-light: rgba(255, 255, 255, 0.04);
  --border-error: rgba(248, 113, 113, 0.35);
  --shadow-light: none;
  --shadow-middle: 0 24px 64px rgba(0, 0, 0, 0.35);
  --shadow-dark: 0 24px 80px rgba(0, 0, 0, 0.42);
  --mask: rgba(0, 0, 0, 0.62);
  --focus-ring: rgba(0, 212, 170, 0.35);
  --control-primary: #00d4aa;
  --text-on-status: #070e1c;
  --surface-loading: rgba(7, 14, 28, 0.72);
  --tooltip-bg: #202c40;
  --tooltip-text: #f0f2f5;
  --workspace-text-muted: #9ca3b8;
  --workspace-border: rgba(255, 255, 255, 0.24);

  /* Signal Tracker aliases used by existing layouts and scoped pages. */
  --bg-primary: var(--bg-main);
  --bg-secondary: var(--bg-header);
  --text-primary: var(--text-main);
  --text-muted: var(--text-light);
  --border: var(--border-normal);
  --accent-1: var(--primary);
  --accent-2: var(--info);
  --accent-3: #7c5cfc;
  --accent-gradient: linear-gradient(135deg, var(--accent-1), var(--accent-2), var(--accent-3));
  --accent-gradient-h: linear-gradient(90deg, var(--accent-1), var(--accent-2), var(--accent-3));
  --glow-green: rgba(0, 212, 170, 0.15);
  --glow-blue: rgba(0, 180, 255, 0.15);
  --glow-purple: rgba(124, 92, 252, 0.15);
  --surface-glass: rgba(12, 26, 46, 0.72);
  --surface-glass-strong: rgba(12, 26, 46, 0.88);
  --surface-field: rgba(10, 22, 40, 0.92);
  --surface-hover: rgba(0, 212, 170, 0.10);
  --surface-grid-line: rgba(255, 255, 255, 0.02);
  --status-info-text: #a9d8f7;
  --status-info-bg: rgba(74, 158, 255, 0.08);
  --status-info-border: rgba(74, 158, 255, 0.18);
  --status-success-text: #9ff3df;
  --status-success-bg: rgba(0, 212, 170, 0.08);
  --status-success-border: rgba(0, 212, 170, 0.18);
  --status-error-text: #ffb4b4;
  --status-error-bg: rgba(248, 113, 113, 0.08);
  --status-error-border: rgba(248, 113, 113, 0.18);
  --status-warning-text: var(--warning);
  --status-warning-bg: rgba(202, 138, 4, 0.12);
  --status-warning-border: rgba(251, 191, 36, 0.35);
  --admin-stat-accent: var(--accent-1);
  --admin-stat-positive: #22c55e;
  --admin-stat-caution: #fbbf24;
  --admin-stat-info: var(--accent-2);
  --admin-stat-violet: var(--accent-3);
  --admin-border-mint: rgba(0, 212, 170, 0.35);
  --admin-border-info: rgba(0, 180, 255, 0.32);
  --tier-basic: #22c55e;
  --tier-pro: #eab308;
  --tier-vip: #ef4444;
}

.q-field,
.q-field__native,
.q-field__input,
.q-field__prefix,
.q-field__suffix,
.q-field__label,
.q-field__marginal {
  color: var(--text-main);
}

.q-field__native::placeholder,
.q-field__input::placeholder,
.q-placeholder,
.q-field__label {
  color: var(--text-secondary);
  opacity: 1;
}

.q-field--outlined .q-field__control {
  color: var(--text-main);
  background: var(--bg-card);
}

.q-field--outlined .q-field__control::before {
  border-color: var(--border-normal);
}

.q-field--outlined:hover .q-field__control::before {
  border-color: var(--primary-hover);
}

.q-field--outlined.q-field--focused .q-field__control::after {
  border-color: var(--primary);
  box-shadow: 0 0 0 2px var(--focus-ring);
}

.q-field--disabled .q-field__control,
.q-field--readonly .q-field__control {
  background: var(--bg-table-header);
}

.q-field--disabled .q-field__native,
.q-field--disabled .q-field__input,
.q-field--disabled .q-field__label,
.q-field--disabled .q-field__marginal {
  color: var(--text-light);
  opacity: 0.78;
}

.q-menu,
.q-dialog-plugin,
.q-card {
  color: var(--text-main);
  background: var(--bg-card);
}

.q-item {
  color: var(--text-main);
}

.q-item__label--caption {
  color: var(--text-secondary);
}

.q-item.q-router-link--active,
.q-item--active {
  color: var(--primary-hover);
}

.kfw-input:focus,
.kfw-select:focus,
.kfw-date-picker:focus,
.kfw-textarea:focus {
  outline-color: rgba(0, 212, 170, 0.24);
}

.kfw-tag,
.kfw-badge,
.kfw-tag--info,
.kfw-badge--info,
.kfw-status--info {
  background: rgba(0, 180, 255, 0.12);
  border-color: rgba(0, 180, 255, 0.30);
}

.kfw-tag--success,
.kfw-badge--success,
.kfw-status--success {
  background: rgba(115, 209, 61, 0.14);
  border-color: rgba(115, 209, 61, 0.32);
}

.kfw-tag--warning,
.kfw-badge--warning,
.kfw-status--warning {
  background: rgba(255, 197, 61, 0.16);
  border-color: rgba(255, 197, 61, 0.34);
}

.kfw-tag--error,
.kfw-badge--error,
.kfw-status--error {
  background: rgba(255, 120, 117, 0.14);
  border-color: rgba(255, 120, 117, 0.34);
}

.kfw-tooltip,
.kfw-toast,
.kfw-notify {
  background: rgba(20, 20, 30, 0.98);
  border-color: rgba(80, 80, 110, 0.96);
}
