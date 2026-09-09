import type { KmvApiErrorPayload } from './types';

const hasNonEmptyText = (value: string | null | undefined): value is string =>
  typeof value === 'string' && value.trim().length > 0;

export type KmvMessageTranslator = (key: string, ...values: unknown[]) => string;

export type KmvMessageKeyExists = (key: string) => boolean;

/**
 * 按当前 i18n locale 将 Kmv 业务错误转为用户可见说明。
 * - 主键为数字 `code`，与 `__PY_PROJECT_NAME__/.../common/exception/*_errors.py` 一致。
 */
export function resolveKmvApiUserMessage(
  t: KmvMessageTranslator,
  te: KmvMessageKeyExists,
  payload: KmvApiErrorPayload | null,
): string {
  const fallbackKey = 'api.kmv.fallback';

  if (!payload) {
    return t(fallbackKey);
  }

  const codeStr = String(payload.code);

  const simpleKey = `api.kmv.codes.${codeStr}`;
  if (te(simpleKey)) {
    return t(simpleKey);
  }

  return hasNonEmptyText(payload.msg) ? payload.msg : t(fallbackKey);
}
