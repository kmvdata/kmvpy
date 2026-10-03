import { afterEach, expect, test } from "bun:test";
import { RealtimeManager } from "../src/network/realtime/manager";
import {
  StorageOverlay,
  isSessionValidationResult,
} from "../src/network/realtime/session";
import { RefreshCoordinator } from "../src/network/realtime/refresh";
const sleep = (n = 40) => new Promise((r) => setTimeout(r, n));
const jwt = (domain = "user", sid = "s1", exp = Date.now() + 3600000) =>
  "Bearer e30." +
  btoa(
    JSON.stringify({
      sub: "90071992547409931",
      role: domain,
      sid,
      exp: exp / 1000,
    }),
  ) +
  ".test";
class Network {
  disk = new Map();
  channels = new Map();
  listeners = new Set();
  locks = new Map();
  sockets = [];
  validates = 0;
  pump(name) {
    const q = this.locks.get(name);
    const e = q[0];
    if (!e || e.started) return;
    e.started = true;
    Promise.resolve(e.callback())
      .then(e.resolve, e.reject)
      .finally(() => {
        q.shift();
        this.pump(name);
      });
  }
  runtime(id, flags = {}) {
    const disk = {
      getItem: (k) => {
        if (flags.readFail) throw Error("read");
        return this.disk.get(k) ?? null;
      },
      setItem: (k, v) => {
        if (flags.writeFail) throw Error("write");
        this.disk.set(k, v);
        this.listeners.forEach((fn) => fn(k, v));
      },
      removeItem: (k) => {
        if (flags.writeFail) throw Error("write");
        this.disk.delete(k);
        this.listeners.forEach((fn) => fn(k, null));
      },
    };
    return {
      tabId: id,
      now: Date.now,
      random: () => 0.5,
      storage: new StorageOverlay(() => disk),
      locks: flags.lockFail
        ? { request: () => Promise.reject(Error("lock")) }
        : flags.noLocks
          ? null
          : {
              request: (name, o, callback) =>
                new Promise((resolve, reject) => {
                  const e = { callback, resolve, reject, started: false };
                  const q = this.locks.get(name) ?? [];
                  this.locks.set(name, q);
                  q.push(e);
                  o.signal.addEventListener("abort", () => {
                    if (!e.started) {
                      q.splice(q.indexOf(e), 1);
                      reject(Error("abort"));
                    }
                  });
                  this.pump(name);
                }),
            },
      channel: (name) => {
        if (flags.noBroadcast) return null;
        if (flags.createFail) throw Error("create");
        const set = this.channels.get(name) ?? new Set();
        this.channels.set(name, set);
        const ch = {
          onmessage: null,
          close: () => set.delete(ch),
          postMessage: (data) => {
            if (flags.sendFail) throw Error("send");
            set.forEach((p) => {
              if (p !== ch) queueMicrotask(() => p.onmessage?.({ data }));
            });
          },
        };
        set.add(ch);
        return ch;
      },
      listen: (fn) => {
        this.listeners.add(fn);
        return () => this.listeners.delete(fn);
      },
    };
  }
}
class FakeSocket {
  connected = false;
  handlers = new Map();
  ops = [];
  rejected = false;
  hold = false;
  on(e, fn) {
    this.handlers.set(e, fn);
    return this;
  }
  removeAllListeners() {
    this.handlers.clear();
  }
  disconnect() {
    this.connected = false;
  }
  connect() {
    if (!this.hold) setTimeout(() => this.finish(), 3);
  }
  finish() {
    this.connected = true;
    this.handlers.get("connect")?.();
  }
  timeout() {
    return this;
  }
  async emitWithAck(event, op) {
    this.ops.push({ event, ...op });
    return {
      ok: !this.rejected,
      calibrate: event === "subscription" && op.action === "subscribe",
    };
  }
  event(e, p) {
    this.handlers.get(e)?.(p);
  }
}
const managers = [];
const refreshes = [];
afterEach(() => {
  managers.splice(0).forEach((m) => m.stop());
  refreshes.splice(0).forEach((r) => r.dispose());
});
function tab(n, id, domain = "user", flags = {}, extra = {}) {
  const auth = { value: jwt(domain), eligible: true, validations: 0 };
  const m = new RealtimeManager({
    app: "test-app",
    domain,
    runtime: n.runtime(id, flags),
    eligible: () => auth.eligible,
    notice: (v) => v && typeof v.api_uri === "string",
    heartbeatMs: 12,
    leaseMs: 45,
    mergeMs: 8,
    renewLeadMs: 30,
    validateMs: 80,
    connect: () => {
      const s = new FakeSocket();
      s.hold = !!extra.hold;
      n.sockets.push(s);
      return s;
    },
  });
  m.configure({
    getAuthorization: () => auth.value,
    onLogout: () => {
      auth.value = "";
    },
    validate: async (signal) => {
      auth.validations++;
      n.validates++;
      if (extra.validate) await extra.validate(signal);
    },
  });
  managers.push(m);
  m.start();
  return { m, auth };
}
const connected = (n) => n.sockets.filter((s) => s.connected);
test("native locks share one connection per domain; logout isolates domains", async () => {
  const n = new Network();
  const a = tab(n, "a");
  const b = tab(n, "b");
  const c = tab(n, "c", "admin");
  const d = tab(n, "d", "admin");
  await sleep(70);
  expect(connected(n)).toHaveLength(2);
  expect(n.validates).toBe(2);
  let received = 0;
  b.m.onApiNotice(() => received++);
  n.sockets[0].event("api_notice", { api_uri: "/x" });
  await sleep();
  expect(received).toBe(1);
  a.m.broadcastLogout();
  await sleep();
  expect(b.auth.value).toBe("");
  expect(c.auth.value).not.toBe("");
  expect(d.auth.value).not.toBe("");
  expect(connected(n)).toHaveLength(1);
});
test("hidden/offline/route leave cancels waiting lock; handoff and return work", async () => {
  const n = new Network();
  const a = tab(n, "a");
  const b = tab(n, "b");
  const c = tab(n, "c");
  await sleep();
  b.auth.eligible = false;
  b.m.lifecycleChanged();
  a.auth.eligible = false;
  a.m.lifecycleChanged();
  await sleep();
  expect(connected(n)).toHaveLength(1);
  expect(b.auth.validations).toBe(0);
  expect(c.auth.validations).toBe(1);
  c.m.stop();
  await sleep();
  expect(connected(n)).toHaveLength(0);
  b.auth.eligible = true;
  b.m.lifecycleChanged();
  await sleep();
  expect(connected(n)).toHaveLength(1);
});
test.each([
  { noLocks: true },
  { lockFail: true },
  { noBroadcast: true },
  { createFail: true },
  { sendFail: true },
  { writeFail: true, readFail: true, noLocks: true },
])("exception fallback converges: %j", async (flags) => {
  const n = new Network();
  tab(n, "a", "user", flags);
  tab(n, "b", "user", flags);
  await sleep(140);
  expect(connected(n)).toHaveLength(1);
});
test("no forwarding enables independent connections", async () => {
  const n = new Network();
  const f = { noBroadcast: true, writeFail: true, readFail: true };
  tab(n, "a", "user", f);
  tab(n, "b", "user", f);
  await sleep(70);
  expect(connected(n)).toHaveLength(2);
});
test("native lock is not revoked by advertising lease", async () => {
  const n = new Network();
  tab(n, "a");
  const b = tab(n, "b");
  await sleep();
  for (const k of n.disk.keys())
    if (k.endsWith(":lease"))
      n.disk.set(
        k,
        JSON.stringify({ source: "b", expires: Date.now() + 100000 }),
      );
  b.m.notifyAuthorizationChanged();
  await sleep();
  expect(n.sockets).toHaveLength(1);
});
test("slow handshake survives token updates; old socket events cannot clear new login", async () => {
  const n = new Network();
  const a = tab(n, "a", "user", {}, { hold: true });
  await sleep();
  const old = n.sockets[0];
  for (let i = 0; i < 5; i++) {
    a.auth.value = jwt("user", "s1", Date.now() + 3700000 + i * 1000);
    a.m.notifyAuthorizationChanged();
  }
  await sleep();
  expect(n.sockets).toHaveLength(1);
  expect(n.validates).toBe(1);
  old.finish();
  const stale = old.handlers.get("connect_error");
  a.auth.value = jwt("user", "s2");
  a.m.notifyAuthorizationChanged();
  await sleep();
  stale({ data: { kind: "session_invalid" } });
  expect(a.auth.value).not.toBe("");
  expect(n.sockets).toHaveLength(2);
});
test("new stored token does not postpone original renewal; renewal keeps transport", async () => {
  const n = new Network();
  const a = tab(n, "a");
  a.m.stop();
  a.auth.value = jwt("user", "s1", Date.now() + 110);
  a.m.start();
  await sleep(30);
  const old = n.sockets.at(-1);
  a.auth.value = jwt("user", "s1", Date.now() + 3600000);
  a.m.notifyAuthorizationChanged();
  await sleep(95);
  expect(old.ops.some((o) => o.event === "auth_update")).toBe(true);
  expect(connected(n)).toHaveLength(1);
});
test("textual 401 and token updates cannot bypass transport backoff", async () => {
  const n = new Network();
  const a = tab(n, "a");
  await sleep();
  n.sockets[0].event("connect_error", Error("401 proxy failure"));
  for (let i = 0; i < 8; i++) a.m.notifyAuthorizationChanged();
  await sleep(80);
  expect(n.validates).toBe(1);
  expect(a.auth.value).not.toBe("");
});
test("late HTTP validation cannot connect after logout/new login", async () => {
  const n = new Network();
  let finish;
  const a = tab(
    n,
    "a",
    "user",
    {},
    { validate: () => new Promise((r) => (finish = r)) },
  );
  await sleep(10);
  const originalFinish = finish;
  a.m.broadcastLogout();
  a.auth.value = jwt("user", "new");
  a.m.notifyAuthorizationChanged();
  originalFinish();
  await sleep(100);
  expect(n.sockets).toHaveLength(0);
  expect(a.auth.value).not.toBe("");
});
test("subscriptions use slowest baseline, retain other consumers, retry rejected ACK", async () => {
  const n = new Network();
  const a = tab(n, "a");
  const b = tab(n, "b");
  await sleep();
  const off = a.m.subscribe("one", { resource: "r", baseline: 10 });
  b.m.subscribe("two", { resource: "r", baseline: 2 });
  await sleep();
  expect(n.sockets[0].ops.at(-1).baseline).toBe(2);
  off();
  await sleep();
  expect(n.sockets[0].ops.some((o) => o.action === "unsubscribe")).toBe(false);
  n.sockets[0].rejected = true;
  a.m.subscribe("three", { resource: "reject", baseline: null });
  await sleep();
  const before = n.sockets[0].ops.length;
  n.sockets[0].rejected = false;
  await sleep(1050);
  expect(n.sockets[0].ops.length).toBeGreaterThan(before);
});
test("readonly logout tombstone masks stale disk credential", () => {
  const s = new StorageOverlay(() => ({
    getItem: () => jwt(),
    setItem: () => {
      throw Error("write");
    },
    removeItem: () => {
      throw Error("write");
    },
  }));
  expect(s.read("auth")).toContain("Bearer");
  s.write("auth", null);
  expect(s.read("auth")).toBe(null);
});
function refresh(extra = {}) {
  const env = {
    active: true,
    resource: "r",
    session: "s",
    life: 0,
    reads: 0,
    applied: [],
  };
  const r = new RefreshCoordinator({
    identity: () => ({
      resource: env.resource,
      session: env.session,
      lifecycle: env.life,
    }),
    eligible: () => env.active,
    mergeMs: 8,
    read: async (c) => {
      env.reads++;
      return extra.read ? extra.read(c) : env.reads;
    },
    apply: (v) => env.applied.push(v),
  });
  refreshes.push(r);
  return { r, env };
}
test("hidden changes accumulate highest target and resume once without polling", async () => {
  let target;
  const { r, env } = refresh({
    read: (c) => {
      target = c.target;
      return 1;
    },
  });
  env.active = false;
  r.recover();
  r.request(2);
  r.request(8);
  await sleep();
  expect(env.reads).toBe(0);
  env.active = true;
  r.changed();
  r.recover();
  r.recover();
  await sleep();
  expect(env.reads).toBe(1);
  expect(target).toBe(8);
  await sleep();
  expect(env.reads).toBe(1);
});
test("recovery merges ongoing read; higher changes produce one trailing read", async () => {
  const resolve = [];
  const { r, env } = refresh({
    read: () => new Promise((r) => resolve.push(r)),
  });
  r.request();
  await sleep(15);
  r.recover();
  r.recover();
  r.request(3);
  r.request(5);
  expect(env.reads).toBe(1);
  resolve[0](1);
  await sleep(15);
  expect(env.reads).toBe(2);
  resolve[1](2);
  await sleep();
  expect(env.applied).toEqual([1, 2]);
});
test("late resource/session/lifecycle response cannot overwrite active page", async () => {
  const resolve = [];
  const { r, env } = refresh({
    read: () => new Promise((r) => resolve.push(r)),
  });
  r.request();
  await sleep(15);
  env.resource = "new";
  env.session = "new";
  env.life++;
  r.changed();
  r.request();
  await sleep(15);
  resolve[0]("stale");
  resolve[1]("current");
  await sleep();
  expect(env.applied).toEqual(["current"]);
});
test("same session/resource consumers share one in-flight read", async () => {
  let resolve;
  const a = refresh({ read: () => new Promise((r) => (resolve = r)) });
  const b = refresh();
  a.r.request();
  b.r.request();
  await sleep(15);
  expect(a.env.reads + b.env.reads).toBe(1);
  resolve("shared");
  await sleep();
  expect(a.env.applied).toEqual(["shared"]);
  expect(b.env.applied).toEqual(["shared"]);
});
test("version adapter calibrates untrusted/reset data and advances only after complete read", async () => {
  let resolve;
  let calls = 0;
  const applied = [];
  const r = new RefreshCoordinator({
    identity: () => ({ session: "version-test", resource: "r", lifecycle: 0 }),
    eligible: () => true,
    mergeMs: 8,
    read: async () => ({ version: 100, complete: false, reset: true }),
    versionOf: (v) => v.version,
    complete: (v) => v.complete,
    requiresCalibration: (v) => v.reset,
    calibrate: () => {
      calls++;
      return new Promise((r) => (resolve = r));
    },
    apply: (v) => applied.push(v),
  });
  refreshes.push(r);
  r.request(8);
  await sleep(15);
  expect(calls).toBe(1);
  expect(r.getLoadedVersion()).toBe(null);
  expect(applied).toHaveLength(0);
  resolve({ version: 8, complete: true, reset: false });
  await sleep();
  expect(r.getLoadedVersion()).toBe(8);
});
test("invalid, duplicate and old-session channel messages are ignored", async () => {
  const n = new Network();
  const a = tab(n, "a");
  await sleep();
  let received = 0;
  a.m.onApiNotice(() => received++);
  const ch = [...n.channels.values()][0].values().next().value;
  const key = [...n.channels.keys()][0];
  const msg = {
    protocol: 1,
    id: "remote:1",
    source: "remote",
    key,
    domain: "user",
    session: "s1",
    type: "notice",
    payload: { api_uri: "/r" },
  };
  ch.onmessage({ data: { ...msg, session: "old" } });
  ch.onmessage({ data: { ...msg, protocol: 0 } });
  ch.onmessage({ data: msg });
  ch.onmessage({ data: msg });
  expect(received).toBe(1);
});
test("mixed BroadcastChannel failures interoperate with healthy tabs through storage and dedupe", async () => {
  const n = new Network();
  tab(n, "a");
  const b = tab(n, "b", "user", { createFail: true });
  const c = tab(n, "c");
  await sleep(60);
  let bNotices = 0,
    cNotices = 0;
  b.m.onApiNotice(() => bNotices++);
  c.m.onApiNotice(() => cNotices++);
  n.sockets[0].event("api_notice", { api_uri: "/mixed" });
  await sleep();
  expect(connected(n)).toHaveLength(1);
  expect(bNotices).toBe(1);
  expect(cNotices).toBe(1);
});
test("subscription confirmation schedules resource calibration for every tab exactly once", async () => {
  const n = new Network();
  const a = tab(n, "a");
  const b = tab(n, "b");
  await sleep(60);
  const local = [],
    remote = [];
  a.m.onCalibration((r) => local.push(r));
  b.m.onCalibration((r) => remote.push(r));
  a.m.subscribe("join", { resource: "gap", baseline: null });
  await sleep();
  expect(local).toEqual(["gap"]);
  expect(remote).toEqual(["gap"]);
});
test("ownership handoff restores remaining subscriptions and compensation baseline", async () => {
  const n = new Network();
  const a = tab(n, "a");
  const b = tab(n, "b");
  await sleep(60);
  a.m.subscribe("fast", { resource: "handoff", baseline: 10 });
  b.m.subscribe("slow", { resource: "handoff", baseline: 2 });
  await sleep();
  a.auth.eligible = false;
  a.m.lifecycleChanged();
  await sleep(80);
  expect(connected(n)).toHaveLength(1);
  expect(
    n.sockets
      .at(-1)
      .ops.some(
        (o) =>
          o.action === "subscribe" &&
          o.resource === "handoff" &&
          o.baseline === 2,
      ),
  ).toBe(true);
});
test("session validation accepts only its structured success contract", () => {
  expect(isSessionValidationResult({ code: 0, data: { valid: true } })).toBe(
    true,
  );
  for (const body of [
    null,
    {},
    { code: 1, data: { valid: true } },
    { code: 0, data: { valid: false } },
    { code: 0, data: null },
    { detail: "401 temporary proxy failure" },
  ]) {
    expect(isSessionValidationResult(body)).toBe(false);
  }
});
