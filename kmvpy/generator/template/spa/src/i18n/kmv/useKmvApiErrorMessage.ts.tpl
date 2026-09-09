import { useI18n } from 'vue-i18n';

import { extractKmvApiErrorPayload } from './extractKmvApiErrorPayload';
import type { KmvMessageKeyExists, KmvMessageTranslator } from './resolveKmvApiUserMessage';
import { resolveKmvApiUserMessage } from './resolveKmvApiUserMessage';
import type { KmvApiErrorPayload } from './types';

export function useKmvApiErrorMessage() {
  const i18n = useI18n();

  const translate: KmvMessageTranslator = (key, ...values) => {
    if (values.length > 0) {
      return String(i18n.t(key, values[0] as Record<string, unknown>));
    }
    return String(i18n.t(key));
  };

  const keyExists: KmvMessageKeyExists = (key) => i18n.te(key);

  return {
    resolveFromPayload: (payload: KmvApiErrorPayload | null) =>
      resolveKmvApiUserMessage(translate, keyExists, payload),
    resolveFromError: (error: unknown) =>
      resolveKmvApiUserMessage(translate, keyExists, extractKmvApiErrorPayload(error)),
  };
}
