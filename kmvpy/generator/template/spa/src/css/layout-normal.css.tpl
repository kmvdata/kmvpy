/* ==========================================================================
   KFW font-size layer: normal mode
   Structure, dimensions, spacing, typography, border width/style and stacking
   order live here. Do not add color, background, shadow or gradient.
   ========================================================================== */

:root {
  /* Spacing: 8px baseline */
  --kfw-space-xs: 4px;
  --kfw-space-sm: 8px;
  --kfw-space-md: 16px;
  --kfw-space-lg: 24px;
  --kfw-space-xl: 32px;
  --kfw-gutter: 16px;

  /* Radius scale */
  --kfw-radius-none: 0;
  --kfw-radius-sm: 4px;
  --kfw-radius-md: 8px;
  --kfw-radius-lg: 16px;
  --kfw-radius-pill: 999px;

  /* Border width and style only; theme files own colors */
  --kfw-border-width: 1px;
  --kfw-border-width-bold: 2px;
  --kfw-border-style: solid;
  --kfw-border-style-dashed: dashed;

  /* Z-index order: modal > drawer > header > content > footer */
  --kfw-z-footer: 10;
  --kfw-z-content: 100;
  --kfw-z-header: 300;
  --kfw-z-drawer: 600;
  --kfw-z-modal: 900;
  --kfw-z-toast: 1000;

  /* Typography */
  --kfw-font-family: "Microsoft YaHei", "Source Han Sans SC", Arial, sans-serif;
  --kfw-font-size-display: 32px;
  --kfw-font-size-h1: 24px;
  --kfw-font-size-h2: 20px;
  --kfw-font-size-h3: 18px;
  --kfw-font-size-h4: 16px;
  --kfw-font-size-body: 14px;
  --kfw-font-size-small: 12px;
  --kfw-font-size-caption: 12px;
  --kfw-font-size-meta: 13px;
  --kfw-font-size-overline: 10px;
  --kfw-font-size-page-title: 18px;
  --kfw-font-size-section-title: 16px;
  --kfw-font-size-card-title: 18px;
  --kfw-font-size-card-value: 20px;
  --kfw-line-height: 1.5;
  --kfw-line-height-tight: 1.3;
  --kfw-line-height-body: 1.6;
  --kfw-line-height-relaxed: 1.75;
  --kfw-font-weight-regular: 400;
  --kfw-font-weight-medium: 500;
  --kfw-font-weight-bold: 700;

  /* Component dimensions */
  --kfw-click-min: 32px;
  --kfw-btn-mini-height: 24px;
  --kfw-btn-small-height: 32px;
  --kfw-btn-medium-height: 40px;
  --kfw-btn-large-height: 48px;
  --kfw-btn-padding-x: 16px;
  --kfw-input-height: 40px;
  --kfw-input-width: 300px;
  --kfw-table-row-height: 40px;
  --kfw-table-head-height: 44px;
  --kfw-header-height: 60px;
  --kfw-footer-min-height: 80px;
  --kfw-card-padding: 16px;
  --kfw-sidebar-width: 240px;
  --kfw-sidebar-collapsed-width: 72px;
  --kfw-mobile-navbar-height: 48px;
  --kfw-mobile-tabbar-height: 56px;
  --account-menu-width: 288px;
  --account-submenu-width: 240px;
}

*,
*::before,
*::after {
  box-sizing: border-box;
}

html {
  font-size: var(--kfw-font-size-body);
  line-height: var(--kfw-line-height);
  -webkit-text-size-adjust: 100%;
}

body,
.kfw-app {
  min-width: 0;
  min-height: 100%;
  margin: 0;
  font-family: var(--kfw-font-family);
  font-size: var(--kfw-font-size-body);
  line-height: var(--kfw-line-height);
}

.kfw-h1,
.kfw-h2,
.kfw-h3,
.kfw-h4 {
  margin: 0 0 var(--kfw-space-md);
  line-height: var(--kfw-line-height);
  font-weight: var(--kfw-font-weight-bold);
}

.kfw-h1 { font-size: var(--kfw-font-size-h1); }
.kfw-h2 { font-size: var(--kfw-font-size-h2); }
.kfw-h3 { font-size: var(--kfw-font-size-h3); }
.kfw-h4 { font-size: var(--kfw-font-size-h4); }
.kfw-display { font-size: var(--kfw-font-size-display); line-height: var(--kfw-line-height-tight); }
.kfw-page-title { font-size: var(--kfw-font-size-page-title); line-height: var(--kfw-line-height-tight); font-weight: var(--kfw-font-weight-bold); }
.kfw-section-title { font-size: var(--kfw-font-size-section-title); line-height: var(--kfw-line-height-tight); font-weight: var(--kfw-font-weight-bold); }
.kfw-card-title { font-size: var(--kfw-font-size-card-title); line-height: var(--kfw-line-height-tight); font-weight: var(--kfw-font-weight-bold); }
.kfw-card-value { font-size: var(--kfw-font-size-card-value); line-height: var(--kfw-line-height-tight); font-weight: var(--kfw-font-weight-bold); }
.kfw-text { font-size: var(--kfw-font-size-body); line-height: var(--kfw-line-height-body); }
.kfw-text--small { font-size: var(--kfw-font-size-small); }
.kfw-text--caption { font-size: var(--kfw-font-size-caption); }
.kfw-text--meta { font-size: var(--kfw-font-size-meta); }
.kfw-text--overline { font-size: var(--kfw-font-size-overline); }
.kfw-text--medium { font-weight: var(--kfw-font-weight-medium); }
.kfw-text--bold { font-weight: var(--kfw-font-weight-bold); }

.kfw-layout {
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

.kfw-layout__header,
.kfw-header {
  position: sticky;
  top: 0;
  z-index: var(--kfw-z-header);
  min-height: var(--kfw-header-height);
  display: flex;
  align-items: center;
  padding: 0 var(--kfw-space-lg);
  border-bottom-width: var(--kfw-border-width);
  border-bottom-style: var(--kfw-border-style);
}

.kfw-header__brand {
  min-width: 0;
  display: flex;
  align-items: center;
  gap: var(--kfw-space-sm);
  font-size: var(--kfw-font-size-h4);
  font-weight: var(--kfw-font-weight-bold);
}

.kfw-header__menu {
  display: flex;
  align-items: center;
  gap: var(--kfw-space-sm);
  margin-left: var(--kfw-space-xl);
}

.kfw-header__actions {
  display: flex;
  align-items: center;
  gap: var(--kfw-space-sm);
  margin-left: auto;
}

.kfw-header__hamburger {
  display: none;
  width: var(--kfw-click-min);
  min-width: var(--kfw-click-min);
  height: var(--kfw-click-min);
  align-items: center;
  justify-content: center;
  padding: 0;
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-md);
}

.kfw-layout__body {
  flex: 1 1 auto;
  min-width: 0;
  display: flex;
}

.kfw-layout__sider {
  flex: 0 0 var(--kfw-sidebar-width);
  width: var(--kfw-sidebar-width);
  min-height: 0;
  padding: var(--kfw-space-md);
  border-right-width: var(--kfw-border-width);
  border-right-style: var(--kfw-border-style);
}

.kfw-layout__sider--collapsed {
  flex-basis: var(--kfw-sidebar-collapsed-width);
  width: var(--kfw-sidebar-collapsed-width);
}

.kfw-layout__main {
  position: relative;
  z-index: var(--kfw-z-content);
  flex: 1 1 auto;
  min-width: 0;
}

.kfw-layout__footer,
.kfw-footer {
  z-index: var(--kfw-z-footer);
  min-height: var(--kfw-footer-min-height);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--kfw-space-md);
  padding: var(--kfw-space-md) var(--kfw-space-lg);
  border-top-width: var(--kfw-border-width);
  border-top-style: var(--kfw-border-style);
}

.kfw-page {
  width: 100%;
  min-width: 0;
  padding: var(--kfw-space-lg);
}

.kfw-page__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: var(--kfw-space-md);
  margin-bottom: var(--kfw-space-lg);
}

.kfw-page__body {
  min-width: 0;
}

.kfw-container {
  width: 100%;
  max-width: 1200px;
  margin-right: auto;
  margin-left: auto;
}

.kfw-divider {
  display: block;
  width: 100%;
  height: 0;
  margin: var(--kfw-space-md) 0;
  border: 0;
  border-top-width: var(--kfw-border-width);
  border-top-style: var(--kfw-border-style);
}

.kfw-divider--vertical {
  width: 0;
  height: 1em;
  margin: 0 var(--kfw-space-sm);
  border-top: 0;
  border-left-width: var(--kfw-border-width);
  border-left-style: var(--kfw-border-style);
}

.kfw-space {
  display: inline-flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--kfw-space-md);
}

.kfw-space--vertical {
  display: flex;
  flex-direction: column;
  align-items: stretch;
}

.kfw-space--xs { gap: var(--kfw-space-xs); }
.kfw-space--sm { gap: var(--kfw-space-sm); }
.kfw-space--lg { gap: var(--kfw-space-lg); }
.kfw-space--xl { gap: var(--kfw-space-xl); }

.kfw-row {
  display: flex;
  flex-wrap: wrap;
  margin-right: calc(var(--kfw-gutter) / -2);
  margin-left: calc(var(--kfw-gutter) / -2);
}

.kfw-col,
[class*="kfw-col-"] {
  min-width: 0;
  padding-right: calc(var(--kfw-gutter) / 2);
  padding-left: calc(var(--kfw-gutter) / 2);
}

.kfw-col { flex: 1 0 0; }
.kfw-col-1 { flex: 0 0 8.333333%; max-width: 8.333333%; }
.kfw-col-2 { flex: 0 0 16.666667%; max-width: 16.666667%; }
.kfw-col-3 { flex: 0 0 25%; max-width: 25%; }
.kfw-col-4 { flex: 0 0 33.333333%; max-width: 33.333333%; }
.kfw-col-5 { flex: 0 0 41.666667%; max-width: 41.666667%; }
.kfw-col-6 { flex: 0 0 50%; max-width: 50%; }
.kfw-col-7 { flex: 0 0 58.333333%; max-width: 58.333333%; }
.kfw-col-8 { flex: 0 0 66.666667%; max-width: 66.666667%; }
.kfw-col-9 { flex: 0 0 75%; max-width: 75%; }
.kfw-col-10 { flex: 0 0 83.333333%; max-width: 83.333333%; }
.kfw-col-11 { flex: 0 0 91.666667%; max-width: 91.666667%; }
.kfw-col-12 { flex: 0 0 100%; max-width: 100%; }

.kfw-card {
  width: 100%;
  min-width: 0;
  padding: var(--kfw-card-padding);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-md);
}

.kfw-card__header,
.kfw-card__footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--kfw-space-md);
}

.kfw-card__body {
  min-width: 0;
  padding-top: var(--kfw-space-md);
}

.kfw-list {
  display: flex;
  flex-direction: column;
  margin: 0;
  padding: 0;
  list-style: none;
}

.kfw-list__item {
  min-height: var(--kfw-btn-medium-height);
  display: flex;
  align-items: center;
  gap: var(--kfw-space-md);
  padding: var(--kfw-space-sm) 0;
  border-bottom-width: var(--kfw-border-width);
  border-bottom-style: var(--kfw-border-style);
}

.kfw-avatar {
  width: 40px;
  height: 40px;
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  border-radius: var(--kfw-radius-pill);
  font-size: var(--kfw-font-size-body);
}

.kfw-avatar--sm { width: 32px; height: 32px; font-size: var(--kfw-font-size-small); }
.kfw-avatar--lg { width: 56px; height: 56px; font-size: var(--kfw-font-size-h3); }
.kfw-avatar__image { width: 100%; height: 100%; object-fit: cover; }

.kfw-tag,
.kfw-badge {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 24px;
  max-width: 100%;
  padding: 0 var(--kfw-space-sm);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-pill);
  font-size: var(--kfw-font-size-small);
  line-height: 1.2;
  vertical-align: middle;
}

.kfw-badge {
  min-width: 18px;
  height: 18px;
  padding: 0 6px;
}

.kfw-tooltip {
  position: absolute;
  z-index: var(--kfw-z-toast);
  max-width: 260px;
  padding: var(--kfw-space-sm) var(--kfw-space-md);
  border-radius: var(--kfw-radius-sm);
  font-size: var(--kfw-font-size-small);
  line-height: var(--kfw-line-height);
  pointer-events: none;
}

.kfw-collapse {
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-md);
}

.kfw-collapse__header {
  min-height: var(--kfw-btn-medium-height);
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--kfw-space-md);
  padding: 0 var(--kfw-space-md);
  cursor: pointer;
}

.kfw-collapse__body {
  padding: var(--kfw-space-md);
  border-top-width: var(--kfw-border-width);
  border-top-style: var(--kfw-border-style);
}

.kfw-button {
  min-width: var(--kfw-click-min);
  min-height: var(--kfw-click-min);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--kfw-space-sm);
  height: var(--kfw-btn-medium-height);
  padding: 0 var(--kfw-btn-padding-x);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-md);
  font: inherit;
  font-weight: var(--kfw-font-weight-medium);
  line-height: 1;
  text-decoration: none;
  white-space: nowrap;
  cursor: pointer;
}

.kfw-button--mini { height: var(--kfw-btn-mini-height); min-height: var(--kfw-btn-mini-height); padding: 0 var(--kfw-space-sm); font-size: var(--kfw-font-size-small); }
.kfw-button--small { height: var(--kfw-btn-small-height); }
.kfw-button--large { height: var(--kfw-btn-large-height); padding-right: var(--kfw-space-lg); padding-left: var(--kfw-space-lg); }
.kfw-button--block { width: 100%; }
.kfw-button--loading,
.kfw-button[disabled],
.kfw-is-disabled {
  cursor: not-allowed;
}

.kfw-input,
.kfw-select,
.kfw-date-picker {
  width: 100%;
  max-width: var(--kfw-input-width);
  min-width: 0;
  height: var(--kfw-input-height);
  padding: 0 var(--kfw-space-md);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-md);
  font: inherit;
  line-height: var(--kfw-input-height);
}

.kfw-textarea {
  width: 100%;
  min-height: 96px;
  padding: var(--kfw-space-sm) var(--kfw-space-md);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-md);
  font: inherit;
  line-height: var(--kfw-line-height);
  resize: vertical;
}

.kfw-form {
  display: flex;
  flex-direction: column;
  gap: var(--kfw-space-md);
}

.kfw-form__item {
  display: flex;
  align-items: flex-start;
  gap: var(--kfw-space-md);
}

.kfw-form__label {
  flex: 0 0 120px;
  min-height: var(--kfw-input-height);
  display: inline-flex;
  align-items: center;
  justify-content: flex-end;
  font-weight: var(--kfw-font-weight-medium);
}

.kfw-form__control {
  flex: 1 1 auto;
  min-width: 0;
}

.kfw-form__help {
  margin-top: var(--kfw-space-xs);
  font-size: var(--kfw-font-size-small);
}

.kfw-checkbox,
.kfw-radio,
.kfw-switch {
  min-height: var(--kfw-click-min);
  display: inline-flex;
  align-items: center;
  gap: var(--kfw-space-sm);
  cursor: pointer;
}

.kfw-checkbox__input,
.kfw-radio__input {
  width: 16px;
  height: 16px;
  flex: 0 0 auto;
  margin: 0;
}

.kfw-switch__track {
  position: relative;
  width: 44px;
  height: 24px;
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-pill);
}

.kfw-switch__thumb {
  position: absolute;
  top: 2px;
  left: 2px;
  width: 18px;
  height: 18px;
  border-radius: var(--kfw-radius-pill);
}

.kfw-switch--checked .kfw-switch__thumb {
  left: 22px;
}

.kfw-upload {
  min-height: 120px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--kfw-space-lg);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style-dashed);
  border-radius: var(--kfw-radius-md);
  text-align: center;
}

.kfw-table-wrap {
  width: 100%;
  min-width: 0;
  overflow-x: auto;
}

.kfw-table {
  width: 100%;
  min-width: 720px;
  border-collapse: collapse;
  table-layout: auto;
  font-size: var(--kfw-font-size-body);
}

.kfw-table th,
.kfw-table td {
  min-height: var(--kfw-table-row-height);
  padding: 0 var(--kfw-space-md);
  border-bottom-width: var(--kfw-border-width);
  border-bottom-style: var(--kfw-border-style);
  text-align: left;
  vertical-align: middle;
}

.kfw-table th {
  height: var(--kfw-table-head-height);
  font-weight: var(--kfw-font-weight-medium);
}

.kfw-table td {
  height: var(--kfw-table-row-height);
}

.kfw-table--sticky thead th {
  position: sticky;
  top: 0;
  z-index: 1;
}

.kfw-modal,
.kfw-drawer,
.kfw-action-sheet,
.kfw-picker {
  position: fixed;
}

.kfw-modal {
  inset: 0;
  z-index: var(--kfw-z-modal);
  display: none;
  align-items: center;
  justify-content: center;
  padding: var(--kfw-space-lg);
}

.kfw-modal--open { display: flex; }
.kfw-modal__mask,
.kfw-drawer__mask {
  position: absolute;
  inset: 0;
}

.kfw-modal__panel {
  position: relative;
  width: min(100%, 560px);
  max-height: calc(100vh - var(--kfw-space-xl) * 2);
  overflow: auto;
  border-radius: var(--kfw-radius-lg);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
}

.kfw-modal__header,
.kfw-modal__footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: var(--kfw-space-md);
  padding: var(--kfw-space-md) var(--kfw-space-lg);
}

.kfw-modal__body {
  padding: var(--kfw-space-lg);
}

.kfw-drawer {
  inset: 0;
  z-index: var(--kfw-z-drawer);
  display: none;
}

.kfw-drawer--open { display: block; }
.kfw-drawer__panel {
  position: absolute;
  top: 0;
  bottom: 0;
  width: min(420px, 90vw);
  overflow: auto;
  padding: var(--kfw-space-lg);
  border-width: 0;
  border-style: var(--kfw-border-style);
}

.kfw-drawer--right .kfw-drawer__panel { right: 0; border-left-width: var(--kfw-border-width); }
.kfw-drawer--left .kfw-drawer__panel { left: 0; border-right-width: var(--kfw-border-width); }

.kfw-toast,
.kfw-notify {
  position: fixed;
  z-index: var(--kfw-z-toast);
  max-width: min(420px, calc(100vw - var(--kfw-space-lg) * 2));
  padding: var(--kfw-space-md) var(--kfw-space-lg);
  border-radius: var(--kfw-radius-md);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
}

.kfw-toast { left: 50%; bottom: var(--kfw-space-xl); transform: translateX(-50%); }
.kfw-notify { top: var(--kfw-space-lg); right: var(--kfw-space-lg); }

.kfw-loading {
  display: inline-flex;
  align-items: center;
  gap: var(--kfw-space-sm);
}

.kfw-loading__spinner {
  width: 18px;
  height: 18px;
  border-width: var(--kfw-border-width-bold);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-pill);
}

.kfw-tabs {
  display: flex;
  align-items: center;
  gap: var(--kfw-space-sm);
  border-bottom-width: var(--kfw-border-width);
  border-bottom-style: var(--kfw-border-style);
  overflow-x: auto;
}

.kfw-tabs__item {
  min-height: var(--kfw-btn-medium-height);
  display: inline-flex;
  align-items: center;
  padding: 0 var(--kfw-space-md);
  border-bottom-width: var(--kfw-border-width-bold);
  border-bottom-style: var(--kfw-border-style);
  cursor: pointer;
  white-space: nowrap;
}

.kfw-breadcrumb {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: var(--kfw-space-sm);
  margin: 0;
  padding: 0;
  list-style: none;
  font-size: var(--kfw-font-size-small);
}

.kfw-pagination {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: flex-end;
  gap: var(--kfw-space-sm);
}

.kfw-pagination__item {
  min-width: var(--kfw-click-min);
  height: var(--kfw-click-min);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0 var(--kfw-space-sm);
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-sm);
  cursor: pointer;
}

.kfw-nav-menu {
  display: flex;
  flex-direction: column;
  gap: var(--kfw-space-xs);
  margin: 0;
  padding: 0;
  list-style: none;
}

.kfw-nav-menu--horizontal {
  flex-direction: row;
  align-items: center;
}

.kfw-nav-menu__item {
  min-height: var(--kfw-btn-medium-height);
  display: flex;
  align-items: center;
  gap: var(--kfw-space-sm);
  padding: 0 var(--kfw-space-md);
  border-radius: var(--kfw-radius-md);
  cursor: pointer;
}

.kfw-steps {
  display: flex;
  align-items: flex-start;
  gap: var(--kfw-space-md);
}

.kfw-steps__item {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  align-items: flex-start;
  gap: var(--kfw-space-sm);
}

.kfw-steps__index {
  width: var(--kfw-click-min);
  height: var(--kfw-click-min);
  display: inline-flex;
  flex: 0 0 auto;
  align-items: center;
  justify-content: center;
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-pill);
}

.kfw-back-top {
  position: fixed;
  right: var(--kfw-space-lg);
  bottom: var(--kfw-space-lg);
  z-index: var(--kfw-z-header);
  width: var(--kfw-btn-medium-height);
  height: var(--kfw-btn-medium-height);
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-width: var(--kfw-border-width);
  border-style: var(--kfw-border-style);
  border-radius: var(--kfw-radius-pill);
  cursor: pointer;
}

.kfw-navbar,
.kfw-tabbar {
  display: none;
}

.kfw-action-sheet,
.kfw-picker {
  left: 0;
  right: 0;
  bottom: 0;
  z-index: var(--kfw-z-modal);
  max-height: 80vh;
  overflow: auto;
  padding: var(--kfw-space-md);
  border-radius: var(--kfw-radius-lg) var(--kfw-radius-lg) 0 0;
}

.kfw-action-sheet__item,
.kfw-picker__item {
  min-height: var(--kfw-btn-large-height);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 var(--kfw-space-md);
}

.kfw-pull-refresh,
.kfw-infinite-scroll {
  min-height: var(--kfw-btn-large-height);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: var(--kfw-space-md);
}

@media (max-width: 1199px) {
  .kfw-layout__sider {
    flex-basis: var(--kfw-sidebar-collapsed-width);
    width: var(--kfw-sidebar-collapsed-width);
  }

  .kfw-header__menu {
    display: none;
  }

  .kfw-header__hamburger {
    display: inline-flex;
  }

  .kfw-col-md-6 { flex: 0 0 50%; max-width: 50%; }
  .kfw-col-md-12 { flex: 0 0 100%; max-width: 100%; }
}

@media (max-width: 767px) {
  .kfw-layout {
    padding-bottom: var(--kfw-mobile-tabbar-height);
  }

  .kfw-layout__header,
  .kfw-header {
    min-height: var(--kfw-mobile-navbar-height);
    padding: 0 var(--kfw-space-md);
  }

  .kfw-layout__sider {
    display: none;
  }

  .kfw-layout__body {
    display: block;
  }

  .kfw-layout__footer,
  .kfw-footer {
    flex-direction: column;
    align-items: flex-start;
    min-height: auto;
    padding: var(--kfw-space-md);
  }

  .kfw-page {
    padding: var(--kfw-space-md);
  }

  .kfw-page__header,
  .kfw-form__item,
  .kfw-steps {
    flex-direction: column;
  }

  .kfw-form__label {
    flex-basis: auto;
    min-height: 0;
    justify-content: flex-start;
  }

  .kfw-input,
  .kfw-select,
  .kfw-date-picker {
    max-width: none;
  }

  [class*="kfw-col-"],
  .kfw-col,
  .kfw-col-md-6,
  .kfw-col-md-12 {
    flex: 0 0 100%;
    max-width: 100%;
  }

  .kfw-navbar {
    position: sticky;
    top: 0;
    z-index: var(--kfw-z-header);
    height: var(--kfw-mobile-navbar-height);
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 var(--kfw-space-md);
    border-bottom-width: var(--kfw-border-width);
    border-bottom-style: var(--kfw-border-style);
  }

  .kfw-tabbar {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: var(--kfw-z-header);
    height: var(--kfw-mobile-tabbar-height);
    display: flex;
    align-items: stretch;
    border-top-width: var(--kfw-border-width);
    border-top-style: var(--kfw-border-style);
  }

  .kfw-tabbar__item {
    flex: 1 1 0;
    min-width: 0;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--kfw-space-xs);
    font-size: var(--kfw-font-size-small);
  }

  .kfw-modal {
    align-items: flex-end;
    padding: 0;
  }

  .kfw-modal__panel {
    width: 100%;
    max-height: 90vh;
    border-radius: var(--kfw-radius-lg) var(--kfw-radius-lg) 0 0;
  }

  .kfw-toast,
  .kfw-notify {
    left: var(--kfw-space-md);
    right: var(--kfw-space-md);
    max-width: none;
    transform: none;
  }

  .kfw-table {
    min-width: 640px;
  }

  .kfw-back-top {
    right: var(--kfw-space-md);
    bottom: calc(var(--kfw-mobile-tabbar-height) + var(--kfw-space-md));
  }
}
