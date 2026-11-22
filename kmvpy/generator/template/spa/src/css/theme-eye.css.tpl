/* ==========================================================================
   KFW visual theme: eye-care
   Low brightness and low saturation for long reading sessions.
   Visual layer only. Imports the shared selector map, then swaps variables.
   ========================================================================== */

@import "./theme-light.css";

:root {
  /* Global visual variables */
  --bg-main: #f0f8f2;
  --bg-card: #f8fff9;
  --bg-header: #e6f5ea;
  --bg-footer: #e6f5ea;
  --bg-table-header: #e8f5eb;
  --bg-table-zebra: #f3fbf5;
  --text-main: #2a5c20;
  --text-secondary: #4a7c40;
  --text-light: #6f9a68;
  --text-link: #3a9d23;
  --text-link-hover: #2f831c;
  --text-link-active: #276d18;
  --text-link-disabled: #9bbd96;
  --text-on-primary: #ffffff;
  --primary: #3a9d23;
  --primary-hover: #2f831c;
  --primary-active: #276d18;
  --success: #3a9d23;
  --warning: #9a7a24;
  --error: #b0534d;
  --info: #3a8068;
  --border-normal: #d0e8d6;
  --border-light: #e4f2e7;
  --border-error: #e3b8b4;
  --shadow-light: none;
  --shadow-middle: 0 4px 12px rgba(42, 92, 32, 0.08);
  --shadow-dark: 0 10px 24px rgba(42, 92, 32, 0.12);
  --mask: rgba(42, 92, 32, 0.36);
  --focus-ring: rgba(58, 157, 35, 0.35);
  --control-primary: #287a20;
  --text-on-status: #ffffff;
  --surface-loading: rgba(240, 248, 242, 0.72);
  --tooltip-bg: #2a5c20;
  --tooltip-text: #f8fff9;
  --workspace-text-muted: #4a7c40;
  --workspace-border: #a3bdab;

  /* Signal Tracker aliases used by existing layouts and scoped pages. */
  --bg-primary: var(--bg-main);
  --bg-secondary: var(--bg-header);
  --text-primary: var(--text-main);
  --text-muted: var(--text-light);
  --border: var(--border-normal);
  --accent-1: var(--primary);
  --accent-2: #2f8f7f;
  --accent-3: #6d7f32;
  --accent-gradient: linear-gradient(135deg, var(--accent-1), var(--accent-2), var(--accent-3));
  --accent-gradient-h: linear-gradient(90deg, var(--accent-1), var(--accent-2), var(--accent-3));
  --glow-green: rgba(58, 157, 35, 0.12);
  --glow-blue: rgba(47, 143, 127, 0.10);
  --glow-purple: rgba(109, 127, 50, 0.10);
  --surface-glass: rgba(248, 255, 249, 0.88);
  --surface-glass-strong: rgba(248, 255, 249, 0.96);
  --surface-field: rgba(248, 255, 249, 0.94);
  --surface-hover: rgba(58, 157, 35, 0.10);
  --surface-grid-line: rgba(42, 92, 32, 0.05);
  --status-info-text: #2f6e5e;
  --status-info-bg: rgba(47, 143, 127, 0.10);
  --status-info-border: rgba(47, 143, 127, 0.22);
  --status-success-text: #276d18;
  --status-success-bg: rgba(58, 157, 35, 0.10);
  --status-success-border: rgba(58, 157, 35, 0.22);
  --status-error-text: #9e433d;
  --status-error-bg: rgba(176, 83, 77, 0.10);
  --status-error-border: rgba(176, 83, 77, 0.24);
  --status-warning-text: #80631d;
  --status-warning-bg: rgba(154, 122, 36, 0.12);
  --status-warning-border: rgba(154, 122, 36, 0.26);
  --admin-stat-accent: var(--accent-1);
  --admin-stat-positive: var(--success);
  --admin-stat-caution: var(--warning);
  --admin-stat-info: var(--accent-2);
  --admin-stat-violet: var(--accent-3);
  --admin-border-mint: rgba(58, 157, 35, 0.24);
  --admin-border-info: rgba(47, 143, 127, 0.24);
  --tier-basic: #3a9d23;
  --tier-pro: #9a7a24;
  --tier-vip: #b0534d;
}

.kfw-input:focus,
.kfw-select:focus,
.kfw-date-picker:focus,
.kfw-textarea:focus {
  outline-color: rgba(58, 157, 35, 0.18);
}

.kfw-tag,
.kfw-badge,
.kfw-tag--info,
.kfw-badge--info,
.kfw-status--info {
  background: rgba(58, 157, 35, 0.10);
  border-color: rgba(58, 157, 35, 0.24);
}

.kfw-tag--warning,
.kfw-badge--warning,
.kfw-status--warning {
  background: rgba(154, 122, 36, 0.12);
  border-color: rgba(154, 122, 36, 0.26);
}

.kfw-tag--error,
.kfw-badge--error,
.kfw-status--error {
  background: rgba(176, 83, 77, 0.10);
  border-color: rgba(176, 83, 77, 0.24);
}

.kfw-tooltip,
.kfw-toast,
.kfw-notify {
  color: #f8fff9;
  background: rgba(42, 92, 32, 0.92);
  border-color: rgba(42, 92, 32, 0.92);
}
