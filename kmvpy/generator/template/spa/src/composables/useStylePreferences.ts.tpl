import { computed, onMounted, onUnmounted, ref } from "vue";
import { useI18n } from "vue-i18n";

import { isMessageLanguage, setStoredLocale } from "src/boot/i18n";
import {
  frameworkStyleOptions,
  getFontSizeMode,
  getTheme,
  setFontSizeMode,
  setTheme,
} from "src/utils/frameworkStyle";

/** A reactive view of the existing DOM/storage preferences, not a second store. */
export function useStylePreferences() {
  const { t, locale } = useI18n({ useScope: "global" });
  const theme = ref(getTheme());
  const fontSize = ref(getFontSizeMode());
  let observer: MutationObserver | undefined;

  function syncStyle() {
    theme.value = getTheme();
    fontSize.value = getFontSizeMode();
  }

  onMounted(() => {
    syncStyle();
    observer = new MutationObserver(syncStyle);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-kfw-theme", "data-kfw-font-size"],
    });
  });
  onUnmounted(() => observer?.disconnect());

  const localeOptions = computed(() => [
    { value: "zh-CN", label: t("accountMenu.locales.zhCN") },
    { value: "en-US", label: t("accountMenu.locales.enUS") },
  ]);
  const fontSizeOptions = computed(() =>
    frameworkStyleOptions.fontSizes.map((value) => ({
      value,
      label: t(`accountMenu.fontSizes.${value}`),
    })),
  );
  const themeOptions = computed(() =>
    frameworkStyleOptions.themes.map((value) => ({
      value,
      label: t(`accountMenu.themes.${value}`),
    })),
  );

  function updateLocale(value: string) {
    if (isMessageLanguage(value)) {
      locale.value = value;
      setStoredLocale(value);
    }
  }
  function updateFontSize(value: string) {
    if (value === "normal" || value === "large") {
      setFontSizeMode(value);
      syncStyle();
    }
  }
  function updateTheme(value: string) {
    if (value === "light" || value === "dark" || value === "eye") {
      setTheme(value);
      syncStyle();
    }
  }

  return {
    locale,
    theme,
    fontSize,
    localeOptions,
    fontSizeOptions,
    themeOptions,
    updateLocale,
    updateFontSize,
    updateTheme,
  };
}
