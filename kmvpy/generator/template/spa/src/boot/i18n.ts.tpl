import { defineBoot } from '#q-app/wrappers';
import { createI18n } from 'vue-i18n';

import messages from 'src/i18n';

export type MessageLanguages = keyof typeof messages;
// Type-define 'en-US' as the master schema for the resource
export type MessageSchema = (typeof messages)['en-US'];
export const LANGUAGE_STORAGE_KEY = 'kfw-locale';

export const isMessageLanguage = (value: unknown): value is MessageLanguages =>
  value === 'en-US' || value === 'zh-CN';

export const getStoredLocale = (fallback: MessageLanguages = 'en-US'): MessageLanguages => {
  if (typeof window === 'undefined') {
    return fallback;
  }

  try {
    const value = window.localStorage.getItem(LANGUAGE_STORAGE_KEY);
    return isMessageLanguage(value) ? value : fallback;
  } catch {
    return fallback;
  }
};

export const setStoredLocale = (value: MessageLanguages): void => {
  if (typeof window === 'undefined') {
    return;
  }

  try {
    window.localStorage.setItem(LANGUAGE_STORAGE_KEY, value);
  } catch {
    // Some embedded browsers or private sessions block localStorage.
  }
};

// See https://vue-i18n.intlify.dev/guide/advanced/typescript.html#global-resource-schema-type-definition
/* eslint-disable @typescript-eslint/no-empty-object-type */
declare module 'vue-i18n' {
  // define the locale messages schema
  export interface DefineLocaleMessage extends MessageSchema {}

  // define the datetime format schema
  export interface DefineDateTimeFormat {}

  // define the number format schema
  export interface DefineNumberFormat {}
}
/* eslint-enable @typescript-eslint/no-empty-object-type */

export const i18n = createI18n<{ message: MessageSchema }, MessageLanguages>({
  locale: getStoredLocale(),
  legacy: false,
  messages,
  // Locale files are authored in-repo (trusted). HTML fragments + v-html are intentional for marketing copy.
  warnHtmlMessage: false,
});

export default defineBoot(({ app }) => {
  // Set i18n instance on app
  app.use(i18n);
});
