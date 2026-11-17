/* ===== 用户区：个人信息、工单、帮助中心 ===== */

.user-layout {
  --text-muted: var(--workspace-text-muted);
  --spa-text-subtle: var(--workspace-text-muted);
}

:root:not([data-kfw-theme="dark"]) .user-layout .app-logo {
  --logo-wordmark-gradient: var(--accent-gradient);
}

.user-layout :is(.q-btn, .q-item, .nav-item, .q-tab):focus-visible {
  outline: 2px solid var(--control-primary);
  outline-offset: -2px;
}

.kmvpy-user-layout .admin-layout__toolbar-title {
  padding-left: 0;
  min-width: 0;
  white-space: normal;
}

.kmvpy-user-layout .admin-layout__toolbar-title .section-header-wrapper {
  margin-bottom: 0;
  min-width: 0;
}

.kmvpy-user-layout .admin-layout__toolbar-title .section-title {
  margin: 0 0 6px;
  font-size: var(--spa-font-size-page-title);
  font-weight: 700;
  line-height: var(--spa-line-height-tight);
}

.kmvpy-user-layout .admin-layout__toolbar-title .section-sub {
  margin: 0;
  font-size: var(--spa-font-size-small);
  color: var(--text-secondary);
  line-height: var(--spa-line-height-body);
}

.kmvpy-user-layout .gradient-text {
  background: var(--accent-gradient);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
}

.kmvpy-user-layout .q-header.spa-header {
  z-index: 2;
  background: color-mix(in srgb, var(--bg-primary) 85%, transparent);
  backdrop-filter: blur(24px);
  -webkit-backdrop-filter: blur(24px);
  border-bottom: 1px solid var(--border);
}

.kmvpy-user-layout .sidebar {
  display: flex;
  flex-direction: column;
  min-height: 100%;
  padding: 10px 0 12px;
}

.kmvpy-user-layout .sb-section {
  padding: 0 8px 8px;
}

.kmvpy-user-layout .nav-item {
  display: flex;
  align-items: center;
  gap: 8px;
  margin: 2px 0;
  padding: 10px 10px;
  border-radius: var(--spa-radius-xl);
  color: var(--text-secondary);
  cursor: pointer;
  user-select: none;
  transition:
    background 0.15s ease,
    color 0.15s ease;
}

.kmvpy-user-layout .nav-item:hover {
  color: var(--text-primary);
  background: var(--glow-green);
}

.kmvpy-user-layout .nav-item.active,
.kmvpy-user-layout .nav-item.is-active {
  color: var(--text-primary);
  font-weight: 600;
  background: var(--bg-card);
  box-shadow: inset 0 0 0 1px
    color-mix(in srgb, var(--accent-1) 28%, transparent);
}

.kmvpy-user-layout .admin-nav-section-label {
  color: var(--accent-1);
  font-weight: 700;
}

.kmvpy-user-layout .nav-icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  flex-shrink: 0;
  color: var(--accent-1);
}

.kmvpy-user-layout .nav-label {
  flex: 1;
  min-width: 0;
  font-size: var(--spa-font-size-body);
  line-height: var(--spa-line-height-tight);
}

.kmvpy-user-layout .nav-chevron {
  width: 18px;
  height: 18px;
  flex-shrink: 0;
  color: var(--text-secondary);
  transition: transform 0.18s ease;
}

.kmvpy-user-layout .nav-chevron.is-expanded,
.kmvpy-user-layout .nav-item.is-expanded .nav-chevron {
  transform: rotate(90deg);
}

.kmvpy-user-layout__nav-item {
  text-decoration: none;
}

.kmvpy-user-layout .sb-footer {
  margin-top: auto;
  padding: 16px 14px 18px;
  font-size: var(--spa-font-size-overline);
  line-height: var(--spa-line-height-body);
  color: var(--text-secondary);
  border-top: 1px solid var(--border);
}

.kmvpy-user-layout .sb-footer .status-dot {
  display: inline-block;
  width: 7px;
  height: 7px;
  border-radius: 999px;
  margin-right: 6px;
  background: var(--tier-basic);
  box-shadow: 0 0 0 3px color-mix(in srgb, var(--tier-basic) 18%, transparent);
  vertical-align: middle;
}

@media (max-width: 599px) {
  .user-layout .admin-layout__logo-link .app-logo__wordmark {
    display: none;
  }

  .user-layout .admin-layout__logo-link .app-logo {
    padding-inline: 0;
  }

  .kmvpy-user-layout .admin-layout__toolbar-title .section-sub {
    display: none;
  }

  .kmvpy-user-layout .admin-layout__toolbar-title .section-title {
    font-size: var(--spa-font-size-section-title);
  }

  .kmvpy-user-layout .admin-layout__toolbar-title .section-sub {
    font-size: var(--spa-font-size-overline);
  }
}
