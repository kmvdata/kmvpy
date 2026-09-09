import fontSizeLargeHref from '../css/layout-large.css?url';
import layoutNormalHref from '../css/layout-normal.css?url';
import themeDarkHref from '../css/theme-dark.css?url';
import themeEyeHref from '../css/theme-eye.css?url';
import themeLightHref from '../css/theme-light.css?url';

export type FontSizeMode = 'normal' | 'large';
export type LayoutMode = FontSizeMode;
export type LegacyLayoutMode = 'normal' | 'elder';
export type ThemeName = 'light' | 'dark' | 'eye';

const FONT_SIZE_STORAGE_KEY = 'kfw-font-size-mode';
const LEGACY_LAYOUT_STORAGE_KEY = 'kfw-layout-mode';
const THEME_STORAGE_KEY = 'kfw-theme';
const FONT_SIZE_LINK_ID = 'kfw-font-size-link';
const LEGACY_LAYOUT_LINK_ID = 'kfw-layout-link';
const THEME_LINK_ID = 'kfw-theme-link';

const fontSizeFiles: Record<FontSizeMode, string> = {
  normal: layoutNormalHref,
  large: fontSizeLargeHref,
};

const themeFiles: Record<ThemeName, string> = {
  light: themeLightHref,
  dark: themeDarkHref,
  eye: themeEyeHref,
};

function getStoredValue<T extends string>(
  key: string,
  allowed: readonly T[],
  fallback: T,
): T {
  if (typeof window === 'undefined') {
    return fallback;
  }

  try {
    const value = window.localStorage.getItem(key);
    return allowed.includes(value as T) ? (value as T) : fallback;
  } catch {
    return fallback;
  }
}

function storeValue(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Private browsing or embedded webviews may block localStorage.
  }
}

function removeStoredValue(key: string): void {
  try {
    window.localStorage.removeItem(key);
  } catch {
    // Private browsing or embedded webviews may block localStorage.
  }
}

function normalizeFontSizeMode(value: string | null | undefined): FontSizeMode | undefined {
  if (value === 'normal') {
    return 'normal';
  }

  if (value === 'large' || value === 'elder') {
    return 'large';
  }

  return undefined;
}

function normalizeThemeName(value: string | null | undefined): ThemeName | undefined {
  if (value === 'light' || value === 'dark' || value === 'eye') {
    return value;
  }

  return undefined;
}

function upsertStylesheetLink(id: string, href: string): void {
  if (typeof document === 'undefined') {
    return;
  }

  let link = document.getElementById(id) as HTMLLinkElement | null;
  if (!link) {
    link = document.createElement('link');
    link.id = id;
    link.rel = 'stylesheet';
    document.head.appendChild(link);
  }

  if (link.getAttribute('href') !== href) {
    link.href = href;
  }
}

function removeStylesheetLink(id: string): void {
  if (typeof document === 'undefined') {
    return;
  }

  document.getElementById(id)?.remove();
}

function getStoredFontSizeMode(): FontSizeMode {
  if (typeof window === 'undefined') {
    return 'normal';
  }

  try {
    const value = normalizeFontSizeMode(window.localStorage.getItem(FONT_SIZE_STORAGE_KEY));
    if (value) {
      return value;
    }

    return normalizeFontSizeMode(window.localStorage.getItem(LEGACY_LAYOUT_STORAGE_KEY)) ?? 'normal';
  } catch {
    return 'normal';
  }
}

function getStoredThemeName(): ThemeName {
  return getStoredValue<ThemeName>(THEME_STORAGE_KEY, ['light', 'dark', 'eye'], 'dark');
}

export function setFontSizeMode(mode: FontSizeMode): void {
  if (typeof document === 'undefined' || typeof window === 'undefined') {
    return;
  }

  upsertStylesheetLink(FONT_SIZE_LINK_ID, fontSizeFiles[mode]);
  removeStylesheetLink(LEGACY_LAYOUT_LINK_ID);
  document.documentElement.setAttribute('data-kfw-font-size', mode);
  document.documentElement.removeAttribute('data-kfw-layout');
  storeValue(FONT_SIZE_STORAGE_KEY, mode);
  removeStoredValue(LEGACY_LAYOUT_STORAGE_KEY);
}

export function setLayoutMode(mode: FontSizeMode | LegacyLayoutMode): void {
  setFontSizeMode(normalizeFontSizeMode(mode) ?? 'normal');
}

export function setTheme(theme: ThemeName): void {
  if (typeof document === 'undefined' || typeof window === 'undefined') {
    return;
  }

  upsertStylesheetLink(THEME_LINK_ID, themeFiles[theme]);
  document.documentElement.setAttribute('data-kfw-theme', theme);
  storeValue(THEME_STORAGE_KEY, theme);
}

export function getFontSizeMode(): FontSizeMode {
  const attrValue =
    typeof document === 'undefined'
      ? undefined
      : document.documentElement.getAttribute('data-kfw-font-size');
  return normalizeFontSizeMode(attrValue) ?? getStoredFontSizeMode();
}

export function getLayoutMode(): LayoutMode {
  return getFontSizeMode();
}

export function getTheme(): ThemeName {
  const attrValue =
    typeof document === 'undefined'
      ? undefined
      : document.documentElement.getAttribute('data-kfw-theme');
  return normalizeThemeName(attrValue) ?? getStoredThemeName();
}

export function initFrameworkStyle(): void {
  const fontSize = getStoredFontSizeMode();
  const theme = getStoredThemeName();

  setFontSizeMode(fontSize);
  setTheme(theme);
}

export const frameworkStyleOptions = {
  fontSizes: Object.keys(fontSizeFiles) as FontSizeMode[],
  layouts: Object.keys(fontSizeFiles) as LayoutMode[],
  themes: Object.keys(themeFiles) as ThemeName[],
};
