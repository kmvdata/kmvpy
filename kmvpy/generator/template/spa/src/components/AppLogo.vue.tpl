<template>
  <span
    class="app-logo"
    :class="[`app-logo--${size}`, { 'app-logo--full-width': fullWidth }]"
  >
    <span v-if="showMark" class="app-logo__mark" aria-hidden="true">
      <slot name="mark">
        <AppLogoMark />
      </slot>
    </span>

    <span class="app-logo__wordmark" :aria-label="logoText">
      <span class="app-logo__text app-logo__text--primary">
        {{ wordmarkSegments.primary }}
      </span>
      <span
        v-if="wordmarkSegments.secondary"
        class="app-logo__text app-logo__text--secondary"
        :class="{ 'app-logo__text--with-gap': wordmarkSegments.hasGap }"
      >
        {{ wordmarkSegments.secondary }}
      </span>
    </span>
  </span>
</template>

<script setup lang="ts">
import { computed } from "vue";

import { APP_LOGO_TEXT } from "src/components/appLogoConfig";
import AppLogoMark from "src/components/AppLogoMark.vue";

const props = withDefaults(
  defineProps<{
    size?: "sm" | "md" | "lg";
    fullWidth?: boolean;
    text?: string;
    showMark?: boolean;
  }>(),
  {
    size: "md",
    fullWidth: false,
    text: APP_LOGO_TEXT,
    showMark: true,
  },
);

const logoText = computed(() => props.text.trim() || APP_LOGO_TEXT);

const wordmarkSegments = computed(() => splitLogoText(logoText.value));

function splitLogoText(text: string) {
  const normalizedText = text.replace(/\s+/g, " ").trim();
  const firstSpaceIndex = normalizedText.indexOf(" ");

  if (firstSpaceIndex > 0 && firstSpaceIndex < normalizedText.length - 1) {
    return {
      primary: normalizedText.slice(0, firstSpaceIndex),
      secondary: normalizedText.slice(firstSpaceIndex + 1),
      hasGap: true,
    };
  }

  for (let index = 1; index < normalizedText.length; index += 1) {
    const previousChar = normalizedText[index - 1];
    const currentChar = normalizedText[index];

    if (
      previousChar &&
      currentChar &&
      isAsciiLowerOrDigit(previousChar) &&
      isAsciiUpper(currentChar)
    ) {
      return {
        primary: normalizedText.slice(0, index),
        secondary: normalizedText.slice(index),
        hasGap: false,
      };
    }
  }

  return {
    primary: normalizedText,
    secondary: "",
    hasGap: false,
  };
}

function isAsciiLowerOrDigit(char: string) {
  return /^[a-z0-9]$/.test(char);
}

function isAsciiUpper(char: string) {
  return /^[A-Z]$/.test(char);
}
</script>

<style scoped>
.app-logo {
  --logo-padding-y: 24px;
  --logo-padding-x: 32px;
  --logo-gap: 12px;
  --logo-radius: 14px;
  --logo-mark-size: 40px;
  --logo-font-size: 24px;
  --logo-wordmark-line-height: 1.28;
  --logo-wordmark-gradient: linear-gradient(
    90deg,
    #2dd4bf 0%,
    #a8d8ee 48%,
    #4a9eff 100%
  );
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--logo-gap);
  padding: var(--logo-padding-y) var(--logo-padding-x);
  border-radius: var(--logo-radius);
  background: transparent;
  line-height: normal;
  text-align: center;
  white-space: nowrap;
  overflow: visible;
}

.app-logo--sm {
  --logo-padding-y: 16px;
  --logo-padding-x: 20px;
  --logo-gap: 10px;
  --logo-mark-size: 32px;
  --logo-font-size: 24px;
}

.app-logo--lg {
  --logo-padding-y: 28px;
  --logo-padding-x: 36px;
  --logo-gap: 12px;
  --logo-radius: 14px;
  --logo-mark-size: 40px;
  --logo-font-size: 24px;
}

.app-logo--full-width {
  width: 100%;
}

.app-logo__mark {
  width: var(--logo-mark-size);
  height: var(--logo-mark-size);
  flex-shrink: 0;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.app-logo__mark :deep(svg),
.app-logo__mark :deep(img) {
  width: 100%;
  height: 100%;
  display: block;
  object-fit: contain;
}

.app-logo__wordmark {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-family: "Carlito", sans-serif;
  font-size: var(--logo-font-size);
  line-height: var(--logo-wordmark-line-height);
  overflow: visible;
}

.app-logo__text {
  display: inline-block;
  font-family: "Carlito", sans-serif;
  font-size: var(--logo-font-size);
  line-height: var(--logo-wordmark-line-height);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  -webkit-text-stroke: 0.02em transparent;
  background-clip: text;
  background-image: var(--logo-wordmark-gradient);
  filter: drop-shadow(0 0 0 transparent);
  overflow: visible;
}

.app-logo__text--primary {
  font-weight: 700;
  letter-spacing: 0;
}

.app-logo__text--secondary {
  font-weight: 400;
  letter-spacing: 0;
}

.app-logo__text--with-gap {
  margin-left: 0.16em;
}
</style>
