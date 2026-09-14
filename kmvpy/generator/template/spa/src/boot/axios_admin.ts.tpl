import { defineBoot } from '#q-app/wrappers';
import { isAxiosError, type AxiosInstance } from 'axios';
import type { Router } from 'vue-router';

import {
  AUTH_STORAGE_KEY,
  createApiClient,
  clearStoredAuthorization,
  getStoredAuthorization,
  getStoredAuthorizationExpiresAt,
  getWithApiClient,
  installAuthTokenResponseInterceptor,
  postWithApiClient,
  setStoredAuthorization,
} from './axios';
import {
  AdminSocketActivePageBridge,
  AdminSocketClient,
  AdminSocketPageMessageStore,
} from 'src/network/admin_socket';
import type { AdminSocketApiNotice } from 'src/network/admin_socket';

declare module 'vue' {
  interface ComponentCustomProperties {
    $apiAdmin: AxiosInstance;
  }
}

export const ADMIN_AUTH_STORAGE_KEY = `${AUTH_STORAGE_KEY}:admin`;
const ADMIN_AUTH_INVALID_HTTP_STATUS = 401;
const ADMIN_LOGIN_ROUTE_NAME = 'admin-login';

const apiAdmin = createApiClient({ authStorageKey: ADMIN_AUTH_STORAGE_KEY });
let adminRouter: Router | null = null;
let pendingAdminLoginRedirect = false;
let authTokenResponseInterceptorId: number | null = null;
let socketApiNoticeOff: (() => void) | null = null;
let socketLogoutListenerBound = false;

const clearStoredAdminAuthorizationLocally = () => {
  clearStoredAuthorization(ADMIN_AUTH_STORAGE_KEY);
  AdminSocketPageMessageStore.clear();
};

export const getStoredAdminAuthorization = () => getStoredAuthorization(ADMIN_AUTH_STORAGE_KEY);
export const getStoredAdminAuthorizationExpiresAt = () =>
  getStoredAuthorizationExpiresAt(ADMIN_AUTH_STORAGE_KEY);
export const setStoredAdminAuthorization = (value: string) => {
  setStoredAuthorization(value, ADMIN_AUTH_STORAGE_KEY);
  AdminSocketClient.notifyAuthorizationChanged(value);
};
export const clearStoredAdminAuthorization = () => {
  clearStoredAdminAuthorizationLocally();
  AdminSocketClient.broadcastLogout('manual');
};

const redirectToAdminLogin = () => {
  if (!adminRouter) {
    pendingAdminLoginRedirect = true;
    return;
  }

  clearStoredAdminAuthorizationLocally();
  pendingAdminLoginRedirect = false;

  const currentRoute = adminRouter.currentRoute.value;
  if (currentRoute.name === ADMIN_LOGIN_ROUTE_NAME) {
    return;
  }

  const redirect = currentRoute.fullPath || undefined;
  const routeTarget = redirect
    ? { name: ADMIN_LOGIN_ROUTE_NAME, query: { redirect } }
    : { name: ADMIN_LOGIN_ROUTE_NAME };
  void adminRouter.replace(routeTarget).catch(() => undefined);
};

apiAdmin.interceptors.response.use(
  (response) => response,
  (error: unknown) => {
    if (isAxiosError(error) && error.response?.status === ADMIN_AUTH_INVALID_HTTP_STATUS) {
      AdminSocketClient.broadcastLogout('http-401');
      redirectToAdminLogin();
    }

    return Promise.reject(error instanceof Error ? error : new Error(String(error)));
  },
);

export const postAdminApi = async <TRequest, TResponse>(
  url: string,
  requestData: TRequest,
  fallbackMessage: string,
): Promise<TResponse> => postWithApiClient(apiAdmin, url, requestData, fallbackMessage);

export const getAdminApi = async <TResponse>(
  url: string,
  fallbackMessage: string,
): Promise<TResponse> => getWithApiClient(apiAdmin, url, fallbackMessage);

export default defineBoot(({ app, router }) => {
  adminRouter = router;
  if (pendingAdminLoginRedirect) {
    redirectToAdminLogin();
  }
  if (authTokenResponseInterceptorId !== null) {
    apiAdmin.interceptors.response.eject(authTokenResponseInterceptorId);
  }
  AdminSocketClient.configure({
    getAuthorization: getStoredAdminAuthorization,
    onLogout: () => {
      clearStoredAdminAuthorizationLocally();
      redirectToAdminLogin();
    },
  });
  AdminSocketClient.start();
  socketApiNoticeOff?.();
  socketApiNoticeOff = AdminSocketClient.onApiNotice((notice: AdminSocketApiNotice) => {
    const message = AdminSocketPageMessageStore.appendApiNotice(notice);
    AdminSocketActivePageBridge.notifyActivePage(message);
  });

  if (!socketLogoutListenerBound && typeof window !== 'undefined') {
    socketLogoutListenerBound = true;
    window.addEventListener('admin-socket-logout', () => {
      clearStoredAdminAuthorizationLocally();
      redirectToAdminLogin();
    });
  }

  authTokenResponseInterceptorId = installAuthTokenResponseInterceptor(apiAdmin, {
    authStorageKey: ADMIN_AUTH_STORAGE_KEY,
    onAuthorizationChanged: (authorization: string) => {
      AdminSocketClient.notifyAuthorizationChanged(authorization);
    },
  });

  app.config.globalProperties.$apiAdmin = apiAdmin;
});

export { apiAdmin };
