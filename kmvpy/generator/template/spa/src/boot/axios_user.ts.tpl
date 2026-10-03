import { isSessionValidationResult } from "src/network/realtime/session";
import { defineBoot } from "#q-app/wrappers";
import {
  isAxiosError,
  type AxiosInstance,
  type AxiosRequestConfig,
} from "axios";
import type { Router } from "vue-router";
import {
  AUTH_STORAGE_KEY,
  createApiClient,
  clearStoredAuthorization,
  getStoredAuthorization,
  getStoredAuthorizationExpiresAt,
  postWithApiClient,
  getWithApiClient,
  setStoredAuthorization,
  installAuthTokenResponseInterceptor,
  requestAuthorization,
} from "./axios";
import {
  UserSocketClient,
  UserSocketPageMessageStore,
  UserSocketActivePageBridge,
} from "src/network/socket";
import { SessionValidationError } from "src/network/realtime/manager";
import { routeAuthDomain } from "src/network/realtime/lifecycle";

declare module "vue" {
  interface ComponentCustomProperties {
    $apiUser: AxiosInstance;
  }
}
export const USER_AUTH_STORAGE_KEY = `${AUTH_STORAGE_KEY}:user`;
const key = USER_AUTH_STORAGE_KEY;
const apiUser = createApiClient({ authStorageKey: key });
let authRouter: Router | null = null;
export const getStoredUserAuthorization = () => getStoredAuthorization(key);
export const getStoredUserAuthorizationExpiresAt = () =>
  getStoredAuthorizationExpiresAt(key);
export const setStoredUserAuthorization = (value: string) => {
  setStoredAuthorization(value, key);
  UserSocketClient.notifyAuthorizationChanged();
};
export const clearStoredUserAuthorization = () => {
  UserSocketClient.broadcastLogout("manual");
};
const logout = () => {
  clearStoredAuthorization(key);
  UserSocketPageMessageStore.clear();
  const route = authRouter?.currentRoute.value;
  if (route && routeAuthDomain(route) === "user")
    void authRouter?.replace({
      name: "login",
      query: { redirect: route.fullPath },
    });
};
apiUser.interceptors.response.use(
  (r) => r,
  (error: unknown) => {
    if (
      isAxiosError(error) &&
      error.response?.status === 401 &&
      error.response.headers["x-auth-error"] === "session_invalid" &&
      error.response.headers["x-auth-role"] === "user" &&
      requestAuthorization(error.config) === getStoredAuthorization(key)
    ) {
      UserSocketClient.broadcastLogout("http-401");
    }
    return Promise.reject(
      error instanceof Error ? error : new Error(String(error)),
    );
  },
);
installAuthTokenResponseInterceptor(apiUser, {
  authStorageKey: key,
  onAuthorizationChanged: () => UserSocketClient.notifyAuthorizationChanged(),
});
export const postUserApi = <Q, R>(
  url: string,
  data: Q,
  fallback: string,
  config?: AxiosRequestConfig,
): Promise<R> => postWithApiClient(apiUser, url, data, fallback, config);
export const getUserApi = <R>(
  url: string,
  fallback: string,
  config?: AxiosRequestConfig,
): Promise<R> => getWithApiClient(apiUser, url, fallback, config);
export default defineBoot(({ app, router }) => {
  authRouter = router;
  UserSocketClient.configure({
    getAuthorization: getStoredUserAuthorization,
    onLogout: logout,
    onSessionChanged: () => UserSocketPageMessageStore.clear(),
    validate: async (signal) => {
      try {
        const response = await apiUser.post<unknown>(
          "/api/user/socket/session",
          {},
          { signal, timeout: 5000 },
        );
        if (!isSessionValidationResult(response.data))
          throw new SessionValidationError("temporary");
      } catch (error) {
        if (
          isAxiosError(error) &&
          error.response?.status === 401 &&
          error.response.headers["x-auth-error"] === "session_invalid" &&
          error.response.headers["x-auth-role"] === "user" &&
          requestAuthorization(error.config) === getStoredAuthorization(key)
        )
          throw new SessionValidationError("session_invalid");
        throw new SessionValidationError("temporary");
      }
    },
  });
  UserSocketClient.start();
  UserSocketClient.onApiNotice((notice) => {
    const message = UserSocketPageMessageStore.appendApiNotice(notice);
    UserSocketActivePageBridge.notifyActivePage(message);
  });
  app.config.globalProperties.$apiUser = apiUser;
});
export { apiUser };
