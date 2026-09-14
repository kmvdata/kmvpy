import { defineBoot } from '#q-app/wrappers';
import axios, {
  AxiosHeaders,
  isAxiosError,
  type AxiosResponse,
  type AxiosInstance,
  type InternalAxiosRequestConfig,
} from 'axios';
import type { Router } from 'vue-router';

import packageJson from '../../package.json';
import {
  ApiResponseError,
  getApiResponseMessage,
  isApiResponse,
  unwrapApiResponse,
  type ApiResponse,
} from './api_response';

declare module 'vue' {
  interface ComponentCustomProperties {
    $axios: AxiosInstance;
    $api: AxiosInstance;
  }
}

// Be careful when using SSR for cross-request state pollution
// due to creating a Singleton instance here;
// If any client changes this (global) instance, it might be a
// good idea to move this instance creation inside of the
// "export default () => {}" function below (which runs individually
// for each client)
const getRequiredEnv = (key: 'VITE_API_BASE_URL' | 'VITE_AUTH_STORAGE_KEY') => {
  const value = import.meta.env[key]?.trim();
  if (!value) {
    throw new Error(`Missing required env: ${key}`);
  }

  return value;
};

export const API_BASE_URL = getRequiredEnv('VITE_API_BASE_URL');
const AUTH_STORAGE_KEY = getRequiredEnv('VITE_AUTH_STORAGE_KEY');
const AUTH_INVALID_HTTP_STATUS = 401;
const AUTH_RENEW_TOKEN_HEADER = 'x-auth-token';
const AUTH_RENEW_TOKEN_TYPE_HEADER = 'x-auth-token-type';
const AUTH_RENEW_EXPIRES_AT_HEADER = 'x-auth-expires-at';
const APP_VERSION =
  typeof packageJson.version === 'string' ? packageJson.version.trim() : '';

type LoginRouteName = 'login' | 'admin-login';

const api = axios.create({
  baseURL: API_BASE_URL,
  withCredentials: true,
});

const isFormData = (value: unknown): value is FormData =>
  typeof FormData !== 'undefined' && value instanceof FormData;

const normalizeAuthorization = (value: string | null | undefined) => {
  const token = value?.trim();
  if (!token) {
    return '';
  }

  return /^Bearer\s+/i.test(token) ? token : `Bearer ${token}`;
};

interface ClientHintBrandLike {
  brand?: string;
}

interface ClientHintDataLike {
  mobile?: boolean;
  platform?: string;
  brands?: ClientHintBrandLike[];
}

interface NetworkInformationLike {
  effectiveType?: string;
  type?: string;
}

type NavigatorLike = Navigator & {
  userAgentData?: ClientHintDataLike;
  connection?: NetworkInformationLike;
  mozConnection?: NetworkInformationLike;
  webkitConnection?: NetworkInformationLike;
};

const CLIENT_HEADER_NAMES = [
  'X-Device-Type',
  'X-Device-Model',
  'X-OS-Version',
  'X-App-Version',
  'X-Device-ID',
  'X-Network',
  'X-Brand',
] as const;

const getNavigatorLike = (): NavigatorLike | null => {
  if (typeof window === 'undefined') {
    return null;
  }

  return window.navigator;
};

const normalizeClientHeaderValue = (value: string | null | undefined) => value?.trim() || '';

const normalizeNetworkType = (value: string | undefined) => {
  const normalized = value?.trim().toLowerCase() || '';
  if (!normalized) {
    return '';
  }

  if (normalized === 'wifi') {
    return 'WiFi';
  }

  if (normalized === 'ethernet') {
    return 'Ethernet';
  }

  if (normalized === 'cellular') {
    return 'Cellular';
  }

  if (/^\d+g$/.test(normalized)) {
    return normalized.toUpperCase();
  }

  return normalized;
};

const parseDeviceType = (navigatorLike: NavigatorLike | null) => {
  if (!navigatorLike) {
    return '';
  }

  const platform = normalizeClientHeaderValue(navigatorLike.userAgentData?.platform);
  if (/android/i.test(platform)) {
    return 'Android';
  }
  if (/ios/i.test(platform)) {
    return 'iOS';
  }

  const userAgent = navigatorLike.userAgent || '';
  if (/(iPhone|iPad|iPod)/i.test(userAgent)) {
    return 'iOS';
  }
  if (/Android/i.test(userAgent)) {
    return 'Android';
  }

  return '';
};

const parseDeviceModel = (navigatorLike: NavigatorLike | null) => {
  if (!navigatorLike) {
    return '';
  }

  const userAgent = navigatorLike.userAgent || '';
  const iosMatch = userAgent.match(/\b(iPhone|iPad|iPod)\b/i);
  if (iosMatch?.[1]) {
    return iosMatch[1];
  }

  const androidMatch = userAgent.match(/Android\s[\d.]+;\s*([^;)]+?)(?:\s+Build|\))/i);
  if (androidMatch?.[1]) {
    return normalizeClientHeaderValue(androidMatch[1]);
  }

  return '';
};

const parseOsVersion = (navigatorLike: NavigatorLike | null) => {
  if (!navigatorLike) {
    return '';
  }

  const userAgent = navigatorLike.userAgent || '';
  const iosMatch = userAgent.match(/OS (\d+(?:[_]\d+)*) like Mac OS X/i);
  if (iosMatch?.[1]) {
    return iosMatch[1].replace(/_/g, '.');
  }

  const androidMatch = userAgent.match(/Android (\d+(?:\.\d+)*)/i);
  if (androidMatch?.[1]) {
    return androidMatch[1];
  }

  return '';
};

const parseBrand = (deviceType: string, deviceModel: string, navigatorLike: NavigatorLike | null) => {
  if (deviceType === 'iOS') {
    return 'Apple';
  }

  const deviceFingerprint = `${deviceModel} ${navigatorLike?.userAgent || ''}`;
  if (/Pixel/i.test(deviceFingerprint)) {
    return 'Google';
  }
  if (/(Xiaomi|Redmi|Mi\s|MIX|POCO)/i.test(deviceFingerprint)) {
    return 'Xiaomi';
  }
  if (/(HUAWEI|HONOR)/i.test(deviceFingerprint)) {
    return /HONOR/i.test(deviceFingerprint) ? 'HONOR' : 'Huawei';
  }
  if (/(SM-|Samsung)/i.test(deviceFingerprint)) {
    return 'Samsung';
  }
  if (/OnePlus/i.test(deviceFingerprint)) {
    return 'OnePlus';
  }
  if (/OPPO/i.test(deviceFingerprint)) {
    return 'OPPO';
  }
  if (/vivo/i.test(deviceFingerprint)) {
    return 'vivo';
  }

  const brands = navigatorLike?.userAgentData?.brands ?? [];
  const browserBrand = brands
    .map((item) => normalizeClientHeaderValue(item.brand))
    .find((brand) => brand && !/Not/i.test(brand));

  return browserBrand || '';
};

const getOrCreateDeviceId = () => {
  if (typeof window === 'undefined') {
    return '';
  }

  const storageKey = '__PROJECT_NAME___device_id';
  const storedDeviceId = normalizeClientHeaderValue(window.localStorage.getItem(storageKey));
  if (storedDeviceId) {
    return storedDeviceId;
  }

  const generatedDeviceId =
    typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `web-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  window.localStorage.setItem(storageKey, generatedDeviceId);
  return generatedDeviceId;
};

const getClientRequestHeaders = (): Record<(typeof CLIENT_HEADER_NAMES)[number], string> => {
  const navigatorLike = getNavigatorLike();
  const deviceType = parseDeviceType(navigatorLike);
  const deviceModel = parseDeviceModel(navigatorLike);
  const connection =
    navigatorLike?.connection ?? navigatorLike?.mozConnection ?? navigatorLike?.webkitConnection;

  return {
    'X-Device-Type': deviceType,
    'X-Device-Model': deviceModel,
    'X-OS-Version': parseOsVersion(navigatorLike),
    'X-App-Version': APP_VERSION,
    'X-Device-ID': getOrCreateDeviceId(),
    'X-Network': normalizeNetworkType(connection?.type || connection?.effectiveType),
    'X-Brand': parseBrand(deviceType, deviceModel, navigatorLike),
  };
};

const getHeader = (config: InternalAxiosRequestConfig, name: string) => {
  const headerValue =
    config.headers?.[name] ??
    config.headers?.[name.toLowerCase()] ??
    config.headers?.get?.(name);

  return typeof headerValue === 'string' ? headerValue : undefined;
};

const setHeader = (config: InternalAxiosRequestConfig, name: string, value: string) => {
  if (config.headers?.set) {
    config.headers.set(name, value);
    return;
  }

  const headers = AxiosHeaders.from(config.headers ?? {});
  headers.set(name, value);
  config.headers = headers;
};

const getStoredAuthorization = (storageKey = AUTH_STORAGE_KEY) => {
  if (typeof window === 'undefined') {
    return '';
  }

  return normalizeAuthorization(window.localStorage.getItem(storageKey));
};

const getAuthorizationExpiresAtStorageKey = (storageKey: string) => `${storageKey}:expires-at`;

const getStoredAuthorizationExpiresAt = (storageKey = AUTH_STORAGE_KEY) => {
  if (typeof window === 'undefined') {
    return '';
  }

  return window.localStorage.getItem(getAuthorizationExpiresAtStorageKey(storageKey))?.trim() || '';
};

const setStoredAuthorizationExpiresAt = (value: string, storageKey = AUTH_STORAGE_KEY) => {
  if (typeof window === 'undefined') {
    return;
  }

  const expiresAt = value.trim();
  const expiresAtStorageKey = getAuthorizationExpiresAtStorageKey(storageKey);
  if (!/^\d+$/.test(expiresAt)) {
    window.localStorage.removeItem(expiresAtStorageKey);
    return;
  }

  window.localStorage.setItem(expiresAtStorageKey, expiresAt);
};

const setStoredAuthorization = (value: string, storageKey = AUTH_STORAGE_KEY) => {
  if (typeof window === 'undefined') {
    return;
  }

  const authorization = normalizeAuthorization(value);
  window.localStorage.removeItem(getAuthorizationExpiresAtStorageKey(storageKey));
  if (!authorization) {
    window.localStorage.removeItem(storageKey);
    return;
  }

  window.localStorage.setItem(storageKey, authorization);
};

const clearStoredAuthorization = (storageKey = AUTH_STORAGE_KEY) => {
  if (typeof window === 'undefined') {
    return;
  }

  window.localStorage.removeItem(storageKey);
  window.localStorage.removeItem(getAuthorizationExpiresAtStorageKey(storageKey));
};

interface ValidationErrorDetailItemLike {
  msg?: string;
  loc?: unknown[];
  type?: string;
}

const formatValidationError = (detail: unknown, fallbackMessage: string) => {
  if (Array.isArray(detail)) {
    const messages = detail
      .map((item) => {
        if (!item || typeof item !== 'object') {
          return '';
        }

        const detailItem = item as ValidationErrorDetailItemLike;
        const location = Array.isArray(detailItem.loc) ? detailItem.loc.join('.') : '';
        const message = detailItem.msg || detailItem.type || '';
        return [location, message].filter(Boolean).join(': ');
      })
      .filter(Boolean);

    return messages.join(', ') || fallbackMessage;
  }

  if (typeof detail === 'string' && detail.trim()) {
    return detail;
  }

  return fallbackMessage;
};

export const extractRequestErrorMessage = (error: unknown, fallbackMessage: string) => {
  if (isAxiosError(error)) {
    const responseData = error.response?.data;

    if (isApiResponse(responseData)) {
      return getApiResponseMessage(responseData, fallbackMessage);
    }

    if (responseData && typeof responseData === 'object' && 'detail' in responseData) {
      return formatValidationError(responseData.detail, '请求参数验证失败');
    }

    return error.response?.statusText || fallbackMessage;
  }

  return error instanceof Error ? error.message : fallbackMessage;
};

export const postWithApiClient = async <TRequest, TResponse>(
  apiClient: AxiosInstance,
  url: string,
  requestData: TRequest,
  fallbackMessage: string,
): Promise<TResponse> => {
  try {
    const response: AxiosResponse<ApiResponse<TResponse>> = await apiClient.post(
      url,
      requestData,
    );
    return unwrapApiResponse(response.data, { fallbackMessage });
  } catch (error) {
    if (error instanceof ApiResponseError) {
      throw error;
    }
    throw new Error(extractRequestErrorMessage(error, fallbackMessage));
  }
};

export const postApi = async <TRequest, TResponse>(
  url: string,
  requestData: TRequest,
  fallbackMessage: string,
): Promise<TResponse> => postWithApiClient(api, url, requestData, fallbackMessage);

export const getWithApiClient = async <TResponse>(
  apiClient: AxiosInstance,
  url: string,
  fallbackMessage: string,
): Promise<TResponse> => {
  try {
    const response: AxiosResponse<ApiResponse<TResponse>> = await apiClient.get(
      url,
    );
    return unwrapApiResponse(response.data, { fallbackMessage });
  } catch (error) {
    if (error instanceof ApiResponseError) {
      throw error;
    }
    throw new Error(extractRequestErrorMessage(error, fallbackMessage));
  }
};

export const getApi = async <TResponse>(url: string, fallbackMessage: string): Promise<TResponse> =>
  getWithApiClient(api, url, fallbackMessage);

const installApiRequestInterceptor = (apiClient: AxiosInstance, authStorageKey = AUTH_STORAGE_KEY) => {
  apiClient.interceptors.request.use(
    (config) => {
      const method = config.method?.toLowerCase();
      const shouldSetJsonContentType = method === 'post' || method === 'put' || method === 'patch';

      if (shouldSetJsonContentType && !isFormData(config.data) && !getHeader(config, 'Content-Type')) {
        setHeader(config, 'Content-Type', 'application/json');
      }

      if (!getHeader(config, 'Authorization')) {
        const authorization = getStoredAuthorization(authStorageKey);
        if (authorization) {
          setHeader(config, 'Authorization', authorization);
        }
      }

      const clientHeaders = getClientRequestHeaders();
      for (const headerName of CLIENT_HEADER_NAMES) {
        if (getHeader(config, headerName) === undefined) {
          setHeader(config, headerName, clientHeaders[headerName]);
        }
      }

      return config;
    },
    (error: unknown) => Promise.reject(error instanceof Error ? error : new Error(String(error))),
  );
};

installApiRequestInterceptor(api);

interface ApiClientOptions {
  authStorageKey?: string;
}

export const createApiClient = (options: ApiClientOptions = {}) => {
  const apiClient = axios.create({ baseURL: API_BASE_URL, withCredentials: true });
  installApiRequestInterceptor(apiClient, options.authStorageKey);
  return apiClient;
};

const getResponseHeader = (response: AxiosResponse, name: string) => {
  const headers = response.headers;
  const value =
    headers?.[name] ??
    headers?.[name.toLowerCase()];
  if (typeof value === 'string') {
    return value.trim();
  }
  const headerGetter = (headers as { get?: unknown } | undefined)?.get;
  if (typeof headerGetter !== 'function') {
    return '';
  }
  const getterValue = headerGetter.call(headers, name);
  return typeof getterValue === 'string' ? getterValue.trim() : '';
};

interface AuthTokenResponseInterceptorOptions {
  authStorageKey?: string;
  onAuthorizationChanged?: (authorization: string, expiresAt: string) => void;
}

export const installAuthTokenResponseInterceptor = (
  apiClient: AxiosInstance,
  options: AuthTokenResponseInterceptorOptions = {},
) =>
  apiClient.interceptors.response.use((response) => {
    const token = getResponseHeader(response, AUTH_RENEW_TOKEN_HEADER);
    if (!token) {
      return response;
    }

    const tokenType =
      getResponseHeader(response, AUTH_RENEW_TOKEN_TYPE_HEADER) || 'Bearer';
    const expiresAt = getResponseHeader(response, AUTH_RENEW_EXPIRES_AT_HEADER);
    const authorization = normalizeAuthorization(`${tokenType} ${token}`);
    setStoredAuthorization(authorization, options.authStorageKey);
    setStoredAuthorizationExpiresAt(expiresAt, options.authStorageKey);
    options.onAuthorizationChanged?.(authorization, expiresAt);
    return response;
  });

interface AuthRedirectInterceptorOptions {
  authStorageKey?: string;
  invalidStatus?: number;
}

export const installAuthRedirectInterceptor = (
  apiClient: AxiosInstance,
  router: Router,
  loginRouteName: LoginRouteName,
  options: AuthRedirectInterceptorOptions = {},
) =>
  apiClient.interceptors.response.use(
    (response) => response,
    (error: unknown) => {
      const invalidStatus = options.invalidStatus ?? AUTH_INVALID_HTTP_STATUS;
      if (isAxiosError(error) && error.response?.status === invalidStatus) {
        clearStoredAuthorization(options.authStorageKey);
        const currentRoute = router.currentRoute.value;
        if (currentRoute.name !== loginRouteName) {
          const redirect = currentRoute.fullPath || undefined;
          const routeTarget = redirect
            ? { name: loginRouteName, query: { redirect } }
            : { name: loginRouteName };
          void router.replace(routeTarget).catch(() => undefined);
        }
      }

      return Promise.reject(error instanceof Error ? error : new Error(String(error)));
    },
  );

export default defineBoot(({ app }) => {
  // for use inside Vue files (Options API) through this.$axios and this.$api

  app.config.globalProperties.$axios = axios;
  // ^ ^ ^ this will allow you to use this.$axios (for Vue Options API form)
  //       so you won't necessarily have to import axios in each vue file

  app.config.globalProperties.$api = api;
  // ^ ^ ^ this will allow you to use this.$api (for Vue Options API form)
  //       so you can easily perform requests against your app's API
});

export {
  api,
  AUTH_STORAGE_KEY,
  clearStoredAuthorization,
  getStoredAuthorization,
  getStoredAuthorizationExpiresAt,
  setStoredAuthorization,
  setStoredAuthorizationExpiresAt,
};
