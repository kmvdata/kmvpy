declare namespace NodeJS {
  interface ProcessEnv {
    NODE_ENV: string;
    VUE_ROUTER_MODE: 'hash' | 'history' | 'abstract' | undefined;
    VUE_ROUTER_BASE: string | undefined;
  }
}

declare module '*.json' {
  const value: unknown;
  export default value;
}

// Augment vue-router RouteMeta; this file must be an ES module (`export {}`) so the block merges with vue-router instead of replacing it.
declare module 'vue-router' {
  interface RouteMeta {
    /** Human-readable page title shown in the toolbar */
    pageTitle?: string;
    /** When true the main navigation guard enforces authentication */
    requiresAuth?: boolean;
    /** When true the admin navigation guard enforces authentication */
    requiresAdminAuth?: boolean;
  }
}

export {};
