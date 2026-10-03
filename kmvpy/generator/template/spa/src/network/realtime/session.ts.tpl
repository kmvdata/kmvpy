/** Decoding is a coordination hint only. The server independently verifies every credential. */
export interface LoginSession {
  id: string;
  user: string;
  domain: string;
  authorization: string;
  expiresAt: number;
}
export const normalizeToken = (value: string | null | undefined) => {
  const token = value?.trim() || "";
  return token && !/^Bearer\s/i.test(token) ? `Bearer ${token}` : token;
};
export function readLoginSession(
  authorization: string,
  domain: string,
): LoginSession | null {
  try {
    const part = normalizeToken(authorization)
      .replace(/^Bearer\s+/i, "")
      .split(".")[1];
    if (!part) return null;
    const payload: unknown = JSON.parse(
      atob(part.replace(/-/g, "+").replace(/_/g, "/")),
    );
    if (!payload || typeof payload !== "object") return null;
    const p = payload as Record<string, unknown>;
    if (
      typeof p.sid !== "string" ||
      !p.sid ||
      typeof p.sub !== "string" ||
      !p.sub ||
      p.role !== domain ||
      typeof p.exp !== "number" ||
      !Number.isFinite(p.exp)
    )
      return null;
    return {
      id: p.sid,
      user: p.sub,
      domain,
      authorization: normalizeToken(authorization),
      expiresAt: p.exp * 1000,
    };
  } catch {
    return null;
  }
}
export const sameSession = (a: LoginSession | null, b: LoginSession | null) =>
  Boolean(
    a && b && a.id === b.id && a.user === b.user && a.domain === b.domain,
  );
export const sessionKey = (app: string, s: LoginSession) =>
  JSON.stringify([app, s.domain, s.user, s.id]);

/** Failed writes mask stale disk values for this document, including logout tombstones. */
export class StorageOverlay {
  private overlay = new Map<string, string | null>();
  constructor(private storage: () => Storage | undefined) {}
  read(key: string): string | null {
    if (this.overlay.has(key)) return this.overlay.get(key) ?? null;
    try {
      return this.storage()?.getItem(key) ?? null;
    } catch {
      return null;
    }
  }
  write(key: string, value: string | null): boolean {
    this.overlay.set(key, value);
    try {
      const storage = this.storage();
      if (!storage) return false;
      if (value === null) storage.removeItem(key);
      else storage.setItem(key, value);
      this.overlay.delete(key);
      return true;
    } catch {
      return false;
    }
  }
  external(key: string, value: string | null) {
    if (this.overlay.has(key)) this.overlay.set(key, value);
  }
  probe(): boolean {
    const key = `realtime:probe:${Math.random()}`;
    try {
      const storage = this.storage();
      if (!storage) return false;
      storage.setItem(key, key);
      const ok = storage.getItem(key) === key;
      storage.removeItem(key);
      return ok;
    } catch {
      return false;
    }
  }
}
export const browserStorage = new StorageOverlay(() =>
  typeof window === "undefined" ? undefined : window.localStorage,
);
if (typeof window !== "undefined")
  window.addEventListener("storage", (e) => {
    if (e.key) browserStorage.external(e.key, e.newValue);
  });

/** A successful HTTP status alone does not prove the session endpoint contract succeeded. */
export function isSessionValidationResult(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const response = value as Record<string, unknown>;
  if (
    response.code !== 0 ||
    !response.data ||
    typeof response.data !== "object"
  )
    return false;
  return (response.data as Record<string, unknown>).valid === true;
}
