import { browserStorage, type StorageOverlay } from "./session";
export interface Channel {
  postMessage(value: unknown): void;
  close(): void;
  onmessage: ((e: MessageEvent<unknown>) => void) | null;
}
export interface CoordinationRuntime {
  tabId: string;
  now(): number;
  random(): number;
  storage: StorageOverlay;
  channel(name: string): Channel | null;
  locks: Pick<LockManager, "request"> | null;
  listen(fn: (key: string, value: string | null) => void): () => void;
}
export const createTabId = () =>
  globalThis.crypto?.randomUUID?.() ??
  `tab-${Date.now()}-${Math.random().toString(16).slice(2)}`;
const browserLocks = () => {
  try {
    return typeof navigator === "undefined" ? null : (navigator.locks ?? null);
  } catch {
    return null;
  }
};
export const browserRuntime = (): CoordinationRuntime => ({
  tabId: createTabId(),
  now: Date.now,
  random: Math.random,
  storage: browserStorage,
  channel: (name) =>
    typeof BroadcastChannel === "undefined" ? null : new BroadcastChannel(name),
  locks: browserLocks(),
  listen: (fn) => {
    const handler = (e: StorageEvent) => {
      if (e.key) fn(e.key, e.newValue);
    };
    window.addEventListener("storage", handler);
    return () => window.removeEventListener("storage", handler);
  },
});
export const parseObject = (raw: string | null): unknown => {
  try {
    return raw ? (JSON.parse(raw) as unknown) : null;
  } catch {
    return null;
  }
};
export const object = (value: unknown): value is Record<string, unknown> =>
  value !== null && typeof value === "object" && !Array.isArray(value);
