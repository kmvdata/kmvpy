import { isAxiosError } from 'axios';

import { ApiResponseError, isApiResponse, isApiSuccess } from 'src/boot/api_response';

import type { KmvApiErrorPayload } from './types';

const isObject = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === 'object';

const isLooseKmvErrorBody = (value: unknown): value is { code: number; msg: string | null; error?: string } => {
  if (!isObject(value)) {
    return false;
  }
  if (typeof value.code !== 'number') {
    return false;
  }
  if (!('msg' in value)) {
    return false;
  }
  const msg = value.msg;
  return msg === null || typeof msg === 'string';
};

const apiPayloadFromErrorResponse = (data: unknown): KmvApiErrorPayload | null => {
  if (isApiResponse(data) && !isApiSuccess(data)) {
    return { code: data.code, msg: data.msg };
  }
  if (isLooseKmvErrorBody(data)) {
    const base: KmvApiErrorPayload = { code: data.code, msg: data.msg };
    if (typeof data.error === 'string') {
      base.title = data.error;
    }
    return base;
  }
  return null;
};

/**
 * 从 ApiResponseError、Axios 错误或 HTTP 401 等携带的 body 中抽出 Kmv 业务码与兜底文案。
 * 不抛异常；无法识别时返回 null。
 */
export function extractKmvApiErrorPayload(error: unknown): KmvApiErrorPayload | null {
  if (error instanceof ApiResponseError) {
    return { code: error.code, msg: error.response.msg };
  }

  if (!isAxiosError(error)) {
    return null;
  }

  const data = error.response?.data;
  const direct = apiPayloadFromErrorResponse(data);
  if (direct) {
    return direct;
  }

  if (isObject(data) && 'detail' in data) {
    return apiPayloadFromErrorResponse(data.detail);
  }

  return null;
}
