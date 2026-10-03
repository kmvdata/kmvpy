import type { RouteLocationNormalizedLoaded, Router } from "vue-router";
export type AuthDomain = "user" | "admin";
export function routeAuthDomain(
  route: Pick<RouteLocationNormalizedLoaded, "matched">,
): AuthDomain | null {
  if (route.matched.some((r) => r.meta.requiresAdminAuth)) return "admin";
  return route.matched.some((r) => r.meta.requiresAuth) ? "user" : null;
}
class PageLifecycle {
  domain: AuthDomain | null = null;
  alive = true;
  version = 0;
  private stamp = "";
  private listeners = new Set<() => void>();
  eligible(domain: string) {
    return (
      this.alive &&
      this.domain === domain &&
      typeof document !== "undefined" &&
      document.visibilityState === "visible" &&
      navigator.onLine
    );
  }
  onChange(fn: () => void) {
    this.listeners.add(fn);
    return () => {
      this.listeners.delete(fn);
    };
  }
  changed() {
    const stamp = JSON.stringify([
      this.domain,
      this.alive,
      document.visibilityState,
      navigator.onLine,
    ]);
    if (stamp !== this.stamp) {
      this.stamp = stamp;
      this.version++;
    }
    this.listeners.forEach((fn) => fn());
  }
  install(router: Router) {
    const update = () => {
      this.domain = routeAuthDomain(router.currentRoute.value);
      this.changed();
    };
    router.afterEach((_to, _from, failure) => {
      if (!failure) update();
    });
    void router.isReady().then(update);
    window.addEventListener("online", () => this.changed());
    window.addEventListener("offline", () => this.changed());
    document.addEventListener("visibilitychange", () => this.changed());
    window.addEventListener("pagehide", () => {
      this.alive = false;
      this.changed();
    });
    window.addEventListener("pageshow", () => {
      this.alive = true;
      update();
    });
    document.addEventListener("freeze", () => {
      this.alive = false;
      this.changed();
    });
    document.addEventListener("resume", () => {
      this.alive = true;
      update();
    });
  }
}
export const pageLifecycle = new PageLifecycle();
