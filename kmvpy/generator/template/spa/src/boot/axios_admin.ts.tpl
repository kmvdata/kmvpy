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
  AdminSocketClient,
  AdminSocketPageMessageStore,
  AdminSocketActivePageBridge,
} from "src/network/admin_socket";
import { SessionValidationError } from "src/network/realtime/manager";
import { routeAuthDomain } from "src/network/realtime/lifecycle";

declare module "vue" {
  interface ComponentCustomProperties {
    $apiAdmin: AxiosInstance;
  }
}
export const ADMIN_AUTH_STORAGE_KEY = `${AUTH_STORAGE_KEY}:admin`;
const key = ADMIN_AUTH_STORAGE_KEY;
const apiAdmin = createApiClient({ authStorageKey: key });
let authRouter: Router | null = null;
export const getStoredAdminAuthorization = () => getStoredAuthorization(key);
export const getStoredAdminAuthorizationExpiresAt = () =>
  getStoredAuthorizationExpiresAt(key);
export const setStoredAdminAuthorization = (value: string) => {
  setStoredAuthorization(value, key);
  AdminSocketClient.notifyAuthorizationChanged();
};
export const clearStoredAdminAuthorization = () => {
  AdminSocketClient.broadcastLogout("manual");
};
const logout = () => {
  clearStoredAuthorization(key);
  AdminSocketPageMessageStore.clear();
  const route = authRouter?.currentRoute.value;
  if (route && routeAuthDomain(route) === "admin")
    void authRouter?.replace({
      name: "admin-login",
      query: { redirect: route.fullPath },
    });
};
apiAdmin.interceptors.response.use(
  (r) => r,
  (error: unknown) => {
    if (
      isAxiosError(error) &&
      error.response?.status === 401 &&
      error.response.headers["x-auth-error"] === "session_invalid" &&
      error.response.headers["x-auth-role"] === "admin" &&
      requestAuthorization(error.config) === getStoredAuthorization(key)
    ) {
      AdminSocketClient.broadcastLogout("http-401");
    }
    return Promise.reject(
      error instanceof Error ? error : new Error(String(error)),
    );
  },
);
installAuthTokenResponseInterceptor(apiAdmin, {
  authStorageKey: key,
  onAuthorizationChanged: () => AdminSocketClient.notifyAuthorizationChanged(),
});
export const postAdminApi = <Q, R>(
  url: string,
  data: Q,
  fallback: string,
  config?: AxiosRequestConfig,
): Promise<R> => postWithApiClient(apiAdmin, url, data, fallback, config);
export const getAdminApi = <R>(
  url: string,
  fallback: string,
  config?: AxiosRequestConfig,
): Promise<R> => getWithApiClient(apiAdmin, url, fallback, config);
export default defineBoot(({ app, router }) => {
  authRouter = router;
  AdminSocketClient.configure({
    getAuthorization: getStoredAdminAuthorization,
    onLogout: logout,
    onSessionChanged: () => AdminSocketPageMessageStore.clear(),
    validate: async (signal) => {
      try {
        const response = await apiAdmin.post<unknown>(
          "/api/admin/socket/session",
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
          error.response.headers["x-auth-role"] === "admin" &&
          requestAuthorization(error.config) === getStoredAuthorization(key)
        )
          throw new SessionValidationError("session_invalid");
        throw new SessionValidationError("temporary");
      }
    },
  });
  AdminSocketClient.start();
  AdminSocketClient.onApiNotice((notice) => {
    const message = AdminSocketPageMessageStore.appendApiNotice(notice);
    AdminSocketActivePageBridge.notifyActivePage(message);
  });
  app.config.globalProperties.$apiAdmin = apiAdmin;
});
export { apiAdmin };
