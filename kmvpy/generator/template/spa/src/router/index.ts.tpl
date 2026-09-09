import { defineRouter } from '#q-app/wrappers';
import {
  createMemoryHistory,
  createRouter,
  createWebHashHistory,
  createWebHistory,
  type RouteLocationNormalized,
} from 'vue-router';

import { getStoredAdminAuthorization } from 'src/boot/axios_admin';
import { getStoredUserAuthorization } from 'src/boot/axios_user';

import routes from './routes';

const LEGACY_ADMIN_PAGE_HASH_PATTERN = /^#p\d+$/;

const getRequiredLoginRouteName = (to: RouteLocationNormalized) => {
  const requiresAdminAuth = to.matched.some((route) => route.meta.requiresAdminAuth);
  if (requiresAdminAuth) {
    return 'admin-login';
  }

  const requiresAuth = to.matched.some((route) => route.meta.requiresAuth);
  if (requiresAuth) {
    return 'login';
  }

  return '';
};

export default defineRouter(function () {
  const createHistory = process.env.SERVER
    ? createMemoryHistory
    : process.env.VUE_ROUTER_MODE === 'history'
      ? createWebHistory
      : createWebHashHistory;

  const router = createRouter({
    scrollBehavior: () => ({ left: 0, top: 0 }),
    routes,
    history: createHistory(process.env.VUE_ROUTER_BASE),
  });

  router.beforeEach((to) => {
    if (LEGACY_ADMIN_PAGE_HASH_PATTERN.test(to.hash)) {
      return {
        path: to.path,
        query: to.query,
        replace: true,
      };
    }

    const requiredLoginRouteName = getRequiredLoginRouteName(to);

    if (!requiredLoginRouteName) {
      return true;
    }

    const hasAuthorization =
      requiredLoginRouteName === 'admin-login'
        ? getStoredAdminAuthorization()
        : getStoredUserAuthorization();
    if (hasAuthorization) {
      return true;
    }

    return {
      name: requiredLoginRouteName,
      query: { redirect: to.fullPath },
    };
  });

  return router;
});
