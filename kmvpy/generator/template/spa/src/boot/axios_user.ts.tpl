import { defineBoot } from '#q-app/wrappers';
import { isAxiosError, type AxiosInstance } from 'axios';

import {
  AUTH_STORAGE_KEY,
  createApiClient,
  clearStoredAuthorization,
  getStoredAuthorization,
  getStoredAuthorizationExpiresAt,
  getWithApiClient,
  installAuthTokenResponseInterceptor,
  installAuthRedirectInterceptor,
  postWithApiClient,
  setStoredAuthorization,
} from './axios';
import {
  UserSocketActivePageBridge,
  UserSocketClient,
  UserSocketPageMessageStore,
} from 'src/network/socket';
import type { UserSocketApiNotice } from 'src/network/socket';

declare module 'vue' {
  interface ComponentCustomProperties {
    $apiUser: AxiosInstance;
  }
}

export const USER_AUTH_STORAGE_KEY = `${AUTH_STORAGE_KEY}:user`;
const USER_AUTH_INVALID_HTTP_STATUS = 401;
const USER_LOGIN_ROUTE_NAME = 'login';

const apiUser = createApiClient({ authStorageKey: USER_AUTH_STORAGE_KEY });
let authResponseInterceptorId: number | null = null;
let authTokenResponseInterceptorId: number | null = null;
let socketAuthResponseInterceptorId: number | null = null;
let socketLogoutListenerBound = false;
let socketApiNoticeOff: (() => void) | null = null;

export const getStoredUserAuthorization = () => getStoredAuthorization(USER_AUTH_STORAGE_KEY);
export const getStoredUserAuthorizationExpiresAt = () =>
  getStoredAuthorizationExpiresAt(USER_AUTH_STORAGE_KEY);
export const setStoredUserAuthorization = (value: string) => {
  setStoredAuthorization(value, USER_AUTH_STORAGE_KEY);
  UserSocketClient.notifyAuthorizationChanged(value);
};
export const clearStoredUserAuthorization = () => {
  clearStoredAuthorization(USER_AUTH_STORAGE_KEY);
  UserSocketPageMessageStore.clear();
  UserSocketClient.broadcastLogout('manual');
};

export const postUserApi = async <TRequest, TResponse>(
  url: string,
  requestData: TRequest,
  fallbackMessage: string,
): Promise<TResponse> => postWithApiClient(apiUser, url, requestData, fallbackMessage);

export const getUserApi = async <TResponse>(
  url: string,
  fallbackMessage: string,
): Promise<TResponse> => getWithApiClient(apiUser, url, fallbackMessage);

export default defineBoot(({ app, router }) => {
  if (authResponseInterceptorId !== null) {
    apiUser.interceptors.response.eject(authResponseInterceptorId);
  }
  if (authTokenResponseInterceptorId !== null) {
    apiUser.interceptors.response.eject(authTokenResponseInterceptorId);
  }
  if (socketAuthResponseInterceptorId !== null) {
    apiUser.interceptors.response.eject(socketAuthResponseInterceptorId);
  }

  const redirectToLogin = () => {
    const currentRoute = router.currentRoute.value;
    if (currentRoute.name === USER_LOGIN_ROUTE_NAME) {
      return;
    }

    const redirect = currentRoute.fullPath || undefined;
    const routeTarget = redirect
      ? { name: USER_LOGIN_ROUTE_NAME, query: { redirect } }
      : { name: USER_LOGIN_ROUTE_NAME };
    void router.replace(routeTarget).catch(() => undefined);
  };

  UserSocketClient.configure({
    getAuthorization: getStoredUserAuthorization,
    onLogout: () => {
      clearStoredAuthorization(USER_AUTH_STORAGE_KEY);
      UserSocketPageMessageStore.clear();
      redirectToLogin();
    },
  });
  UserSocketClient.start();
  socketApiNoticeOff?.();
  socketApiNoticeOff = UserSocketClient.onApiNotice((notice: UserSocketApiNotice) => {
    const message = UserSocketPageMessageStore.appendApiNotice(notice);
    UserSocketActivePageBridge.notifyActivePage(message);
  });

  if (!socketLogoutListenerBound && typeof window !== 'undefined') {
    socketLogoutListenerBound = true;
    window.addEventListener('user-socket-logout', () => {
      clearStoredAuthorization(USER_AUTH_STORAGE_KEY);
      UserSocketPageMessageStore.clear();
      redirectToLogin();
    });
  }

  authTokenResponseInterceptorId = installAuthTokenResponseInterceptor(apiUser, {
    authStorageKey: USER_AUTH_STORAGE_KEY,
    onAuthorizationChanged: (authorization) => {
      UserSocketClient.notifyAuthorizationChanged(authorization);
    },
  });
  authResponseInterceptorId = installAuthRedirectInterceptor(apiUser, router, USER_LOGIN_ROUTE_NAME, {
    authStorageKey: USER_AUTH_STORAGE_KEY,
    invalidStatus: USER_AUTH_INVALID_HTTP_STATUS,
  });
  socketAuthResponseInterceptorId = apiUser.interceptors.response.use(
    (response) => response,
    (error: unknown) => {
      if (isAxiosError(error) && error.response?.status === USER_AUTH_INVALID_HTTP_STATUS) {
        UserSocketClient.broadcastLogout('http-401');
      }
      return Promise.reject(error instanceof Error ? error : new Error(String(error)));
    },
  );
  app.config.globalProperties.$apiUser = apiUser;
});

export { apiUser };
