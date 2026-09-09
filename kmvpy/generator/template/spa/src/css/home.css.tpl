/* ===== Home / Marketing：公开页与认证页通用视觉预设 ===== */

.home-layout--marketing {
  --home-bg-primary: var(--bg-primary);
  --home-bg-secondary: var(--bg-secondary);
  --home-bg-card: var(--bg-card);
  --home-accent-1: var(--accent-1);
  --home-accent-2: var(--accent-2);
  --home-accent-3: var(--accent-3);
  --home-accent-gradient: var(--accent-gradient);
  --home-accent-gradient-h: var(--accent-gradient-h);
  --home-text-primary: var(--text-primary);
  --home-text-secondary: var(--text-secondary);
  --home-text-muted: var(--text-muted);
  --home-border: var(--border);
  --home-glow-green: var(--glow-green);
  --home-glow-blue: var(--glow-blue);
  --home-glow-purple: var(--glow-purple);
  background: var(--home-bg-primary);
}

.home-layout--marketing.spa-layout {
  background: var(--home-bg-primary);
}

.home-layout--marketing .q-page-container {
  background: var(--home-bg-primary);
}

.home-layout__toolbar {
  gap: 12px;
}

/* ===== Home 通用排版与容器 ===== */
.signal-tracker-page section,
.home-layout--marketing section {
  padding: 4px 0px;
  position: relative;
}

.signal-tracker-page .container,
.home-layout--marketing .container {
  max-width: 1200px;
  margin: 0 auto;
}

.signal-tracker-page .section-label,
.home-layout--marketing .section-label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-family: var(--spa-mono-font-family);
  font-size: var(--spa-font-size-small);
  text-transform: uppercase;
  letter-spacing: 3px;
  color: var(--accent-1, var(--home-accent-1));
  margin-bottom: 16px;
}

.signal-tracker-page .section-label::before,
.signal-tracker-page .section-label::after,
.home-layout--marketing .section-label::before,
.home-layout--marketing .section-label::after {
  content: '';
  width: 24px;
  height: 1px;
  background: var(--accent-1, var(--home-accent-1));
}

.signal-tracker-page .section-title,
.home-layout--marketing .section-title {
  font-size: clamp(32px, 4vw, 52px);
  font-weight: 800;
  line-height: 1.15;
  letter-spacing: -1.5px;
  margin-bottom: 20px;
}

.signal-tracker-page .section-desc,
.home-layout--marketing .section-desc {
  font-size: var(--spa-font-size-body);
  color: var(--text-secondary);
  max-width: 600px;
  line-height: 1.8;
}

.signal-tracker-page .gradient-text,
.home-layout--marketing .gradient-text,
.auth-page .gradient-text {
  background: var(--accent-gradient, var(--home-accent-gradient));
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.signal-tracker-page .mono,
.home-layout--marketing .mono,
.auth-page .mono {
  font-family: var(--spa-mono-font-family);
}

/* ===== Home 顶部导航（HomeLayout q-header 内 #landing-top-nav） ===== */
.home-layout__landing-qheader.q-header {
  background: transparent;
  border-bottom: none;
}

#landing-top-nav {
  width: 100%;
  padding: 0 48px;
  height: 72px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: color-mix(in srgb, var(--bg-primary) 85%, transparent);
  backdrop-filter: blur(24px);
  border-bottom: 1px solid var(--border);
  transition: all 0.3s;
}

.nav-logo {
  display: flex;
  align-items: center;
  gap: 12px;
  text-decoration: none;
}

.nav-links {
  display: flex;
  gap: 36px;
  list-style: none;
}

.nav-links a {
  color: var(--text-secondary);
  text-decoration: none;
  font-size: 14px;
  font-weight: 500;
  transition: color 0.3s;
  position: relative;
}

.nav-links a:hover,
.nav-links a.nav-active {
  color: var(--text-primary) !important;
}

.nav-links a::after {
  content: '';
  position: absolute;
  bottom: -4px;
  left: 0;
  width: 0;
  height: 2px;
  background: var(--accent-gradient-h);
  transition: width 0.3s;
}

.nav-links a:hover::after,
.nav-links a.nav-active::after {
  width: 100%;
  transform: scaleX(1) !important;
}

.nav-cta {
  display: flex;
  gap: 12px;
  align-items: center;
  margin-left: auto;
}

/* ===== Home 通用按钮 ===== */
.signal-tracker-page .btn-ghost,
.signal-tracker-page .btn-primary,
.home-layout--marketing .btn-ghost,
.home-layout--marketing .btn-primary,
.auth-page .btn-ghost,
.auth-page .btn-primary {
  cursor: pointer;
  transition: all 0.3s;
  text-decoration: none;
  font-family: inherit;
}

.signal-tracker-page .btn-ghost,
.home-layout--marketing .btn-ghost {
  padding: 10px 20px;
  border: 1px solid var(--border, var(--home-border));
  border-radius: 8px;
  color: var(--text-secondary, var(--home-text-secondary));
  background: transparent;
  font-size: 14px;
  font-weight: 500;
}

.signal-tracker-page .btn-ghost:hover,
.home-layout--marketing .btn-ghost:hover {
  border-color: var(--accent-1, var(--home-accent-1));
  color: var(--accent-1, var(--home-accent-1));
}

.signal-tracker-page .btn-primary,
.home-layout--marketing .btn-primary {
  padding: 10px 24px;
  border: none;
  border-radius: 8px;
  background: var(--accent-gradient, var(--home-accent-gradient));
  color: var(--bg-primary, var(--home-bg-primary));
  font-size: 14px;
  font-weight: 600;
}

.signal-tracker-page .btn-primary:hover,
.home-layout--marketing .btn-primary:hover {
  transform: translateY(-2px);
  box-shadow: 0 8px 32px color-mix(in srgb, var(--accent-1) 30%, transparent);
}

.signal-tracker-page .btn-large,
.home-layout--marketing .btn-large {
  padding: 16px 36px;
  font-size: 16px;
  border-radius: 12px;
}

/* ===== Auth 页面预设 ===== */
.auth-page {
  position: relative;
  min-height: 100vh;
  overflow: hidden;
  background: var(--bg-primary);
  color: var(--text-primary);
  font-family: 'Plus Jakarta Sans', 'Noto Sans SC', sans-serif;
}

.auth-page::before {
  content: '';
  position: fixed;
  inset: 0;
  background: url("data:image/svg+xml,%3Csvg viewBox='0 0 256 256' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='4' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)' opacity='0.03'/%3E%3C/svg%3E");
  pointer-events: none;
}

.auth-page .auth-bg {
  position: absolute;
  inset: 0;
}

.auth-page .auth-orb {
  position: absolute;
  border-radius: 50%;
  filter: blur(120px);
}

.auth-page .auth-orb--one {
  top: -180px;
  left: -120px;
  width: 520px;
  height: 520px;
  background: var(--glow-green);
}

.auth-page .auth-orb--two {
  right: -120px;
  bottom: -120px;
  width: 460px;
  height: 460px;
  background: var(--glow-blue);
}

.auth-page .auth-grid {
  position: absolute;
  inset: 0;
  background-image:
    linear-gradient(var(--surface-grid-line) 1px, transparent 1px),
    linear-gradient(90deg, var(--surface-grid-line) 1px, transparent 1px);
  background-size: 60px 60px;
  mask-image: radial-gradient(ellipse at center, black 32%, transparent 72%);
}

.auth-page .auth-shell {
  position: relative;
  z-index: 1;
  min-height: 100vh;
  max-width: 1240px;
  margin: 0 auto;
  padding: 72px 24px;
  box-sizing: border-box;
  display: grid;
  grid-template-columns: 1.05fr 0.95fr;
  gap: 40px;
  align-items: start;
  align-content: start;
}

.auth-page .auth-copy {
  max-width: 620px;
}

.auth-page .brand {
  display: inline-flex;
  align-items: center;
  margin-bottom: 32px;
  text-decoration: none;
}

.auth-page .auth-copy h1 {
  font-size: clamp(40px, 5vw, 68px);
  line-height: 1.08;
  letter-spacing: -1.8px;
  margin: 0 0 24px;
}

.auth-page .auth-copy p {
  font-size: 17px;
  line-height: 1.8;
  color: var(--text-secondary);
  margin: 0 0 36px;
}

.auth-page .copy-points {
  display: grid;
  gap: 16px;
}

.auth-page .copy-point {
  display: flex;
  gap: 16px;
  padding: 18px 20px;
  border: 1px solid var(--border);
  border-radius: 18px;
  background: var(--surface-glass);
  backdrop-filter: blur(20px);
}

.auth-page .copy-point__icon {
  width: 44px;
  height: 44px;
  flex-shrink: 0;
  border-radius: 14px;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 700;
  font-family: var(--spa-mono-font-family);
  color: var(--accent-1);
  background: var(--status-success-bg);
  border: 1px solid var(--status-success-border);
}

.auth-page .copy-point strong {
  display: block;
  margin-bottom: 4px;
  font-size: 15px;
  color: var(--text-primary);
}

.auth-page .copy-point span {
  display: block;
  color: var(--text-secondary);
  font-size: 14px;
  line-height: 1.7;
}

.auth-page .auth-card {
  padding: 28px;
  border-radius: 28px;
  border: 1px solid var(--border);
  background: linear-gradient(180deg, var(--border-light) 0%, var(--surface-glass-strong) 100%);
  backdrop-filter: blur(28px);
  box-shadow: var(--shadow-middle);
}

.auth-page .auth-switcher {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px;
  padding: 6px;
  border-radius: 18px;
  background: var(--border-light);
  margin-bottom: 18px;
}

.auth-page .auth-switcher__item {
  border: none;
  border-radius: 14px;
  padding: 13px 16px;
  background: transparent;
  color: var(--text-secondary);
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.25s ease;
}

.auth-page .auth-switcher__item--active {
  color: var(--bg-primary);
  background: var(--accent-gradient);
}

.auth-page .status-banner {
  margin-bottom: 18px;
  padding: 12px 14px;
  border-radius: 14px;
  font-size: 13px;
  line-height: 1.6;
  border: 1px solid transparent;
}

.auth-page .status-banner--info {
  color: var(--status-info-text);
  background: var(--status-info-bg);
  border-color: var(--status-info-border);
}

.auth-page .status-banner--success {
  color: var(--status-success-text);
  background: var(--status-success-bg);
  border-color: var(--status-success-border);
}

.auth-page .status-banner--error {
  color: var(--status-error-text);
  background: var(--status-error-bg);
  border-color: var(--status-error-border);
}

.auth-page .auth-form {
  display: grid;
  gap: 18px;
}

.auth-page .auth-form__header h2 {
  font-size: 30px;
  line-height: 1.15;
  margin: 0 0 10px;
}

.auth-page .auth-form__header p {
  margin: 0;
  font-size: 14px;
  line-height: 1.7;
  color: var(--text-secondary);
}

.auth-page .section-label {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 16px;
  color: var(--accent-1);
  font-size: 12px;
  font-weight: 700;
  letter-spacing: 0.18em;
  text-transform: uppercase;
  font-family: var(--spa-mono-font-family);
}

.auth-page .section-label::before {
  content: '';
  width: 22px;
  height: 1px;
  background: var(--accent-1);
}

.auth-page .section-label::after {
  content: none;
}

.auth-page .field {
  display: grid;
  gap: 8px;
}

.auth-page .field-group {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  gap: 12px;
  align-items: end;
}

.auth-page .field--code {
  min-width: 0;
}

.auth-page .field__label {
  font-size: 12px;
  color: var(--text-muted);
  font-weight: 600;
  letter-spacing: 0.05em;
}

.auth-page .field__control {
  position: relative;
}

.auth-page .field__input {
  width: 100%;
  padding: 14px 16px;
  border: 1px solid var(--border);
  border-radius: 14px;
  background: var(--surface-field);
  color: var(--text-primary);
  font-size: 14px;
  outline: none;
  transition:
    border-color 0.25s ease,
    box-shadow 0.25s ease;
}

.auth-page .field__input::placeholder {
  color: var(--text-muted);
}

.auth-page .field__input:focus {
  border-color: var(--status-success-border);
  box-shadow: 0 0 0 3px var(--status-success-bg);
}

.auth-page .field__input--readonly {
  cursor: not-allowed;
  opacity: 0.78;
}

.auth-page .field__input--with-action {
  padding-right: 74px;
}

.auth-page .field__toggle {
  position: absolute;
  top: 50%;
  right: 12px;
  transform: translateY(-50%);
  border: none;
  padding: 4px 6px;
  background: transparent;
  color: var(--accent-1);
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
}

.auth-page .field__toggle:hover {
  color: var(--primary-hover);
}

.auth-page .btn-primary {
  border: none;
  border-radius: 14px;
  padding: 14px 24px;
  background: var(--accent-gradient);
  color: var(--bg-primary);
  font-size: 15px;
  font-weight: 700;
}

.auth-page .btn-primary:hover {
  transform: translateY(-1px);
  box-shadow: 0 12px 28px color-mix(in srgb, var(--accent-1) 22%, transparent);
}

.auth-page .btn-primary:disabled {
  cursor: not-allowed;
  opacity: 0.7;
  transform: none;
  box-shadow: none;
}

.auth-page .btn-primary--full {
  width: 100%;
}

.auth-page .btn-ghost {
  border: 1px solid var(--border);
  border-radius: 14px;
  padding: 14px 16px;
  background: transparent;
  color: var(--text-primary);
  font-size: 14px;
  font-weight: 600;
}

.auth-page .btn-ghost:hover:not(:disabled) {
  border-color: var(--status-success-border);
  color: var(--accent-1);
}

.auth-page .btn-ghost:disabled {
  cursor: not-allowed;
  color: var(--text-muted);
  opacity: 0.7;
}

.auth-page .btn-ghost--code {
  min-width: 128px;
}

.auth-page .hint-text {
  margin-top: -4px;
  font-size: 13px;
  line-height: 1.7;
  color: var(--text-secondary);
}

.auth-page .auth-footnote {
  text-align: center;
  font-size: 13px;
  color: var(--text-secondary);
}

.auth-page .inline-link {
  border: none;
  padding: 0;
  margin-left: 6px;
  background: transparent;
  color: var(--accent-1);
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
}

@media (max-width: 980px) {
  .auth-page .auth-shell {
    grid-template-columns: 1fr;
    padding-top: 48px;
  }

  .auth-page .auth-copy {
    max-width: none;
  }
}

@media (max-width: 640px) {
  .auth-page .auth-shell {
    padding: 32px 16px 48px;
    gap: 28px;
  }

  .auth-page .auth-card {
    padding: 20px;
    border-radius: 22px;
  }

  .auth-page .field-group {
    grid-template-columns: 1fr;
  }

  .auth-page .btn-ghost--code {
    width: 100%;
  }

  .auth-page .auth-copy h1 {
    font-size: 38px;
    letter-spacing: -1.2px;
  }
}
