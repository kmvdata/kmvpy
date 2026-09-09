import type { RouteRecordRaw } from "vue-router";

const legacyUserPathToAppPath = (path: string): string => {
  const normalized =
    path.length > 1 && path.endsWith("/") ? path.slice(0, -1) : path;
  if (normalized === "/user") {
    return "/app";
  }

  const legacyPath = normalized.slice("/user/".length);
  if (legacyPath === "work-tickets" || legacyPath === "user-work-tickets") {
    return "/app/work-tickets/user-work-tickets";
  }
  if (legacyPath === "help" || legacyPath.startsWith("help-")) {
    return "/app/help/help";
  }

  return "/app/personal/profile";
};

const routes: RouteRecordRaw[] = [
  {
    path: "/",
    component: () => import("../layouts/HomeLayout.vue"),
    children: [
      {
        path: "",
        name: "home",
        component: () => import("../pages/home/IndexPage.vue"),
      },
      {
        path: "auth",
        name: "home-auth",
        component: () => import("../pages/home/AuthPage.vue"),
      },
      {
        path: "login",
        name: "login",
        component: () => import("../pages/home/AuthPage.vue"),
      },
    ],
  },
  {
    path: "/app",
    component: () => import("../layouts/UserLayout.vue"),
    meta: { requiresAuth: true },
    children: [
      { path: "", redirect: { name: "user-profile" } },
      {
        path: "personal/profile",
        name: "user-profile",
        component: () =>
          import("../pages/app/personal/PersonalProfilePage.vue"),
        meta: { titleKey: "layouts.userNav.profile" },
      },
      {
        path: "personal/users",
        redirect: { name: "user-profile" },
      },
      {
        path: "personal/:legacyPersonalPath(.*)*",
        redirect: { name: "user-profile" },
      },
      {
        path: "work-tickets",
        redirect: { name: "user-work-tickets" },
      },
      {
        path: "work-tickets/user-work-tickets",
        name: "user-work-tickets",
        component: () =>
          import("../pages/app/work-tickets/UserWorkTicketsPage.vue"),
        meta: { titleKey: "workTickets.title" },
      },
      {
        path: "help",
        redirect: { name: "user-help" },
      },
      {
        path: "help/help",
        name: "user-help",
        component: () => import("../pages/app/help/HelpPage.vue"),
        meta: { titleKey: "layouts.userNav.help" },
      },
      {
        path: "help/:legacyHelpPath(.*)*",
        redirect: { name: "user-help" },
      },
      {
        path: ":legacyAppPath(.*)*",
        redirect: { name: "user-profile" },
      },
    ],
  },
  {
    path: "/user",
    redirect: "/app",
  },
  {
    path: "/user/:legacyPathMatch(.*)*",
    redirect: (to) => ({
      path: legacyUserPathToAppPath(to.path),
      query: to.query,
      hash: to.hash,
    }),
  },
  {
    path: "/dashboard",
    redirect: "/app",
  },
  {
    path: "/dashboard/users",
    redirect: (to) => ({
      path: "/app/personal/profile",
      query: to.query,
      hash: to.hash,
    }),
  },
  {
    path: "/dashboard/work-tickets",
    redirect: (to) => ({
      path: "/app/work-tickets/user-work-tickets",
      query: to.query,
      hash: to.hash,
    }),
  },
  {
    path: "/dashboard/ai-models",
    redirect: (to) => ({
      path: "/app/personal/profile",
      query: to.query,
      hash: to.hash,
    }),
  },
  {
    path: "/admin/login",
    name: "admin-login",
    component: () => import("../pages/admin/AdminLoginPage.vue"),
  },
  {
    path: "/admin",
    component: () => import("../layouts/AdminLayout.vue"),
    meta: { requiresAdminAuth: true },
    children: [
      {
        path: "",
        redirect: { name: "admin-users" },
      },
      {
        path: "users",
        name: "admin-users",
        component: () =>
          import("../pages/admin/management/AdminUserListPage.vue"),
      },
      {
        path: "work-tickets",
        name: "admin-work-tickets",
        component: () =>
          import("../pages/admin/management/AdminWorkTicketsPage.vue"),
      },
      {
        path: "system-settings",
        name: "admin-system-settings",
        component: () =>
          import("../pages/admin/system/AdminSystemSettingsPage.vue"),
      },
      {
        path: "database-tables",
        name: "admin-database-tables",
        component: () =>
          import("../pages/admin/system/AdminDatabaseTablesPage.vue"),
      },
    ],
  },
  {
    path: "/:catchAll(.*)*",
    redirect: "/",
  },
];

export default routes;
