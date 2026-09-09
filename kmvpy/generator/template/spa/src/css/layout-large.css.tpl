/* ==========================================================================
   KFW font-size layer: large mode
   Imports the normal structure and only enlarges readable typography tokens.
   This keeps the component tree and placement identical while improving text
   legibility and tap area.
   ========================================================================== */

@import "./layout-normal.css";

:root {
  --account-menu-width: 320px;
  --account-submenu-width: 280px;
  /* Spacing: +50% against normal font size */
  --kfw-space-xs: 6px;
  --kfw-space-sm: 12px;
  --kfw-space-md: 24px;
  --kfw-space-lg: 36px;
  --kfw-space-xl: 48px;
  --kfw-gutter: 24px;

  /* Radius remains proportional and recognizable */
  --kfw-radius-none: 0;
  --kfw-radius-sm: 6px;
  --kfw-radius-md: 12px;
  --kfw-radius-lg: 20px;
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

  /* Typography: visible enlargement against normal mode */
  --kfw-font-family: "Microsoft YaHei", "Source Han Sans SC", Arial, sans-serif;
  --kfw-font-size-display: 42px;
  --kfw-font-size-h1: 34px;
  --kfw-font-size-h2: 30px;
  --kfw-font-size-h3: 26px;
  --kfw-font-size-h4: 22px;
  --kfw-font-size-body: 18px;
  --kfw-font-size-small: 16px;
  --kfw-font-size-caption: 16px;
  --kfw-font-size-meta: 17px;
  --kfw-font-size-overline: 15px;
  --kfw-font-size-page-title: 24px;
  --kfw-font-size-section-title: 22px;
  --kfw-font-size-card-title: 22px;
  --kfw-font-size-card-value: 26px;
  --kfw-line-height: 1.8;
  --kfw-line-height-tight: 1.35;
  --kfw-line-height-body: 1.8;
  --kfw-line-height-relaxed: 1.9;
  --kfw-font-weight-regular: 400;
  --kfw-font-weight-medium: 500;
  --kfw-font-weight-bold: 700;

  /* Component dimensions: buttons +40%, fields/tables/header explicitly tuned */
  --kfw-click-min: 48px;
  --kfw-btn-mini-height: 34px;
  --kfw-btn-small-height: 45px;
  --kfw-btn-medium-height: 56px;
  --kfw-btn-large-height: 68px;
  --kfw-btn-padding-x: 24px;
  --kfw-input-height: 56px;
  --kfw-input-width: 360px;
  --kfw-table-row-height: 56px;
  --kfw-table-head-height: 60px;
  --kfw-header-height: 80px;
  --kfw-footer-min-height: 100px;
  --kfw-card-padding: 24px;
  --kfw-sidebar-width: 280px;
  --kfw-sidebar-collapsed-width: 88px;
  --kfw-mobile-navbar-height: 60px;
  --kfw-mobile-tabbar-height: 72px;
}

.kfw-avatar {
  width: 56px;
  height: 56px;
  font-size: var(--kfw-font-size-body);
}

.kfw-avatar--sm {
  width: 48px;
  height: 48px;
}

.kfw-avatar--lg {
  width: 72px;
  height: 72px;
}

.kfw-checkbox__input,
.kfw-radio__input {
  width: 22px;
  height: 22px;
}

.kfw-switch__track {
  width: 60px;
  height: 34px;
}

.kfw-switch__thumb {
  width: 28px;
  height: 28px;
}

.kfw-switch--checked .kfw-switch__thumb {
  left: 28px;
}

.kfw-loading__spinner {
  width: 24px;
  height: 24px;
}

@media (max-width: 767px) {
  .kfw-tabbar__item {
    font-size: var(--kfw-font-size-small);
    gap: var(--kfw-space-xs);
  }

  .kfw-action-sheet__item,
  .kfw-picker__item {
    min-height: 64px;
  }
}

:is(.user-layout, .admin-layout, .q-dialog) .q-btn:not(.q-btn--round) {
  min-height: var(--kfw-btn-medium-height);
}

:is(.user-layout, .admin-layout, .q-dialog) .q-field--dense .q-field__control,
:is(.user-layout, .admin-layout, .q-dialog) .q-field--dense .q-field__marginal {
  min-height: var(--kfw-input-height);
}
