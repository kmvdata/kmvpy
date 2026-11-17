import type { Socket } from "socket.io-client";
import {
  readLoginSession,
  sameSession,
  sessionKey,
  type LoginSession,
} from "./session";
import {
  object,
  parseObject,
  type Channel,
  type CoordinationRuntime,
} from "./runtime";

export interface ConnectionState {
  status: "idle" | "connecting" | "connected" | "disconnected";
  lastAttemptAt: number;
  lastConnectedAt: number;
  lastDisconnectedAt: number;
  lastError: string;
}
export type LogoutReason =
  "manual" | "http-401" | "socket-auth-invalid" | "remote";
export class SessionValidationError extends Error {
  constructor(public kind: "session_invalid" | "token_expired" | "temporary") {
    super(kind);
  }
}
export interface SubscriptionIntent {
  resource: string;
  baseline: number | null;
}
interface Peer {
  at: number;
  eligible: boolean;
  owner: boolean;
  locked: boolean;
  intents: SubscriptionIntent[];
}
export interface ManagerConfig {
  getAuthorization: () => string;
  validate: (signal: AbortSignal) => Promise<void>;
  onSessionChanged?: (() => void) | undefined;
  onLogout?: ((reason: LogoutReason) => void) | undefined;
}
export interface ManagerOptions<N> {
  app: string;
  domain: string;
  runtime: CoordinationRuntime;
  eligible: () => boolean;
  connect: (
    session: LoginSession,
    observation: { recovery: boolean; tab: string },
  ) => Socket;
  notice: (value: unknown) => value is N;
  heartbeatMs?: number;
  leaseMs?: number;
  mergeMs?: number;
  validateMs?: number;
  handshakeMs?: number;
  renewLeadMs?: number;
}
interface Envelope {
  protocol: 1;
  id: string;
  source: string;
  key: string;
  domain: string;
  session: string;
  type: "presence" | "notice" | "logout" | "recovery" | "state" | "calibration";
  payload: unknown;
}
const initialState = (): ConnectionState => ({
  status: "idle",
  lastAttemptAt: 0,
  lastConnectedAt: 0,
  lastDisconnectedAt: 0,
  lastError: "",
});
const validIntents = (v: unknown): v is SubscriptionIntent[] =>
  Array.isArray(v) &&
  v.length <= 200 &&
  v.every(
    (i) =>
      object(i) &&
      typeof i.resource === "string" &&
      i.resource.length > 0 &&
      i.resource.length <= 255 &&
      (i.baseline === null ||
        (typeof i.baseline === "number" &&
          Number.isSafeInteger(i.baseline) &&
          i.baseline >= 0)),
  );

/** One instance per domain. Transport, election, renewal and subscriptions have one owner. */
export class RealtimeManager<N> {
  private config: ManagerConfig = {
    getAuthorization: () => "",
    validate: () => Promise.reject(new SessionValidationError("temporary")),
  };
  private session: LoginSession | null = null;
  private key = "";
  private channel: Channel | null = null;
  private storageAvailable = false;
  private offStorage: (() => void) | null = null;
  private timer: ReturnType<typeof setInterval> | null = null;
  private electionTimer: ReturnType<typeof setTimeout> | null = null;
  private socket: Socket | null = null;
  private handshakeTimer: ReturnType<typeof setTimeout> | null = null;
  private epoch = 0;
  private isOwner = false;
  private locked = false;
  private locksFailed = false;
  private lockAbort: AbortController | null = null;
  private releaseLock: (() => void) | null = null;
  private validation: {
    abort: AbortController;
    promise: Promise<void>;
  } | null = null;
  private connecting = false;
  private retryAt = 0;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private failures = 0;
  private renewAt = Infinity;
  private handshakeToken: LoginSession | null = null;
  private peers = new Map<string, Peer>();
  private seen = new Set<string>();
  private serial = 0;
  private lastEligible = false;
  private intents = new Map<string, SubscriptionIntent>();
  private acknowledged = new Map<string, number | null>();
  private subscriptionRunning = false;
  private subscriptionRetryAt = 0;
  private subscriptionAbort: AbortController | null = null;
  private handlers = new Set<(notice: N) => void>();
  private calibrations = new Set<(resource: string) => void>();
  private recoveries = new Set<() => void>();
  private changes = new Set<() => void>();
  private state = initialState();
  constructor(private options: ManagerOptions<N>) {}
  configure(config: ManagerConfig) {
    this.config = config;
  }
  getSession() {
    return readLoginSession(
      this.config.getAuthorization(),
      this.options.domain,
    );
  }
  eligible() {
    return this.options.eligible() && Boolean(this.getSession());
  }
  getState() {
    return { ...this.state };
  }
  isConnected() {
    return this.state.status === "connected";
  }
  onApiNotice(fn: (notice: N) => void) {
    this.handlers.add(fn);
    return () => {
      this.handlers.delete(fn);
    };
  }
  onCalibration(fn: (resource: string) => void) {
    this.calibrations.add(fn);
    return () => {
      this.calibrations.delete(fn);
    };
  }
  onRecovery(fn: () => void) {
    this.recoveries.add(fn);
    return () => {
      this.recoveries.delete(fn);
    };
  }
  onEligibilityChange(fn: () => void) {
    this.changes.add(fn);
    return () => {
      this.changes.delete(fn);
    };
  }
  start() {
    if (this.timer) return;
    this.offStorage = this.options.runtime.listen((key, raw) => {
      if (key === `${this.key}:message`) this.receive(parseObject(raw));
      else if (key === `${this.options.app}:${this.options.domain}`)
        this.notifyAuthorizationChanged();
    });
    this.timer = setInterval(
      () => this.tick(),
      this.options.heartbeatMs ?? 5000,
    );
    this.tick();
  }
  stop() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    this.disconnect();
    this.channel?.close();
    this.channel = null;
    this.offStorage?.();
    this.offStorage = null;
  }
  disconnect() {
    // Fence async work first, then transport, then ownership.
    this.epoch++;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = null;
    this.validation?.abort.abort();
    this.validation = null;
    this.subscriptionAbort?.abort();
    this.subscriptionAbort = null;
    this.lockAbort?.abort();
    this.lockAbort = null;
    if (this.electionTimer) clearTimeout(this.electionTimer);
    this.electionTimer = null;
    this.connecting = false;
    this.subscriptionRunning = false;
    this.closeSocket();
    this.isOwner = false;
    this.locked = false;
    this.publish("presence", this.presence());
    const lease = parseObject(
      this.options.runtime.storage.read(`${this.key}:lease`),
    );
    if (object(lease) && lease.source === this.options.runtime.tabId)
      this.options.runtime.storage.write(`${this.key}:lease`, null);
    this.releaseLock?.();
    this.releaseLock = null;
    this.state.status = "idle";
  }
  notifyAuthorizationChanged(authorization?: string) {
    void authorization;
    this.tick();
  }
  lifecycleChanged() {
    const eligible = this.eligible();
    if (!eligible) this.disconnect();
    else {
      if (!this.lastEligible) this.retryAt = 0;
      this.tick();
    }
    if (eligible !== this.lastEligible) {
      this.lastEligible = eligible;
      this.changes.forEach((fn) => fn());
      if (eligible) this.recoveries.forEach((fn) => fn());
    }
  }
  reconnectManually() {
    this.disconnect();
    this.retryAt = 0;
    this.tick();
  }
  broadcastLogout(reason: LogoutReason = "manual") {
    this.publish("logout", { reason });
    this.logout(reason);
  }
  private logout(reason: LogoutReason) {
    this.disconnect();
    this.config.onLogout?.(reason);
    this.changes.forEach((fn) => fn());
  }
  subscribe(id: string, intent: SubscriptionIntent) {
    if (!validIntents([intent])) throw new Error("invalid subscription");
    this.intents.set(id, intent);
    this.publish("presence", this.presence());
    void this.syncSubscriptions();
    return () => {
      this.intents.delete(id);
      this.publish("presence", this.presence());
      void this.syncSubscriptions();
    };
  }
  private presence(): Peer {
    return {
      at: this.options.runtime.now(),
      eligible: this.eligible(),
      owner: this.isOwner,
      locked: this.locked,
      intents: this.eligible() ? [...this.intents.values()] : [],
    };
  }
  private openCoordination(s: LoginSession) {
    this.channel?.close();
    this.channel = null;
    this.key = sessionKey(this.options.app, s);
    this.peers.clear();
    this.seen.clear();
    this.storageAvailable = this.options.runtime.storage.probe();
    try {
      this.channel = this.options.runtime.channel(this.key);
    } catch {
      this.channel = null;
    }
    if (this.channel) this.channel.onmessage = (e) => this.receive(e.data);
  }
  private publish(type: Envelope["type"], payload: unknown) {
    if (!this.session || !this.key) return;
    const value: Envelope = {
      protocol: 1,
      id: `${this.options.runtime.tabId}:${++this.serial}`,
      source: this.options.runtime.tabId,
      key: this.key,
      domain: this.options.domain,
      session: this.session.id,
      type,
      payload,
    };
    if (this.channel) {
      try {
        this.channel.postMessage(value);
      } catch {
        this.channel.close();
        this.channel = null;
      }
    }
    this.storageAvailable = this.options.runtime.storage.write(
      `${this.key}:message`,
      JSON.stringify(value),
    );
  }
  private receive(value: unknown) {
    if (
      !object(value) ||
      value.protocol !== 1 ||
      value.key !== this.key ||
      value.domain !== this.options.domain ||
      value.session !== this.session?.id ||
      !sameSession(this.session, this.getSession()) ||
      typeof value.id !== "string" ||
      typeof value.source !== "string" ||
      value.source === this.options.runtime.tabId ||
      this.seen.has(value.id)
    )
      return;
    this.seen.add(value.id);
    if (this.seen.size > 500)
      this.seen.delete(this.seen.values().next().value as string);
    const p = value.payload;
    if (
      value.type === "presence" &&
      object(p) &&
      typeof p.eligible === "boolean" &&
      typeof p.owner === "boolean" &&
      typeof p.locked === "boolean" &&
      validIntents(p.intents)
    ) {
      this.peers.set(value.source, {
        at: this.options.runtime.now(),
        eligible: p.eligible,
        owner: p.owner,
        locked: p.locked,
        intents: p.intents,
      });
      // A native lock cannot be revoked by an advertised lease or another tab's heartbeat.
      if (
        this.isOwner &&
        !this.locked &&
        p.owner &&
        (p.locked || value.source < this.options.runtime.tabId)
      )
        this.disconnect();
      void this.syncSubscriptions();
      if (!this.isOwner) this.elect();
    } else if (value.type === "notice" && this.options.notice(p)) {
      this.handlers.forEach((fn) => fn(p));
    } else if (
      value.type === "calibration" &&
      object(p) &&
      typeof p.resource === "string" &&
      p.resource.length <= 255
    ) {
      this.calibrations.forEach((fn) => fn(p.resource as string));
    } else if (value.type === "recovery") this.recoveries.forEach((fn) => fn());
    else if (
      value.type === "logout" &&
      object(p) &&
      ["manual", "http-401", "socket-auth-invalid", "remote"].includes(
        String(p.reason),
      )
    )
      this.logout("remote");
    else if (
      value.type === "state" &&
      object(p) &&
      !this.isOwner &&
      ["idle", "connecting", "connected", "disconnected"].includes(
        String(p.status),
      ) &&
      typeof p.lastAttemptAt === "number" &&
      typeof p.lastConnectedAt === "number" &&
      typeof p.lastDisconnectedAt === "number" &&
      typeof p.lastError === "string"
    )
      this.state = p as unknown as ConnectionState;
  }
  private valid(epoch: number, s: LoginSession | null) {
    return (
      epoch === this.epoch &&
      this.eligible() &&
      sameSession(s, this.getSession()) &&
      this.isOwner
    );
  }
  private tick() {
    const s = this.getSession();
    if (!sameSession(s, this.session)) {
      if (this.session) this.publish("logout", { reason: "remote" });
      this.disconnect();
      this.state = initialState();
      this.session = s;
      this.retryAt = 0;
      this.failures = 0;
      if (s) this.openCoordination(s);
      this.config.onSessionChanged?.();
      this.changes.forEach((fn) => fn());
    }
    if (!this.eligible() || !s) {
      if (this.isOwner || this.lockAbort || this.electionTimer)
        this.disconnect();
      return;
    }
    const now = this.options.runtime.now();
    const leaseMs = this.options.leaseMs ?? 15000;
    this.peers.forEach((p, id) => {
      if (now - p.at > leaseMs) this.peers.delete(id);
    });
    this.publish("presence", this.presence());
    if (!this.channel && !this.storageAvailable && this.locked)
      this.disconnect();
    if (!this.isOwner) {
      this.elect();
      return;
    }
    this.options.runtime.storage.write(
      `${this.key}:lease`,
      JSON.stringify({
        source: this.options.runtime.tabId,
        expires: now + leaseMs,
        locked: this.locked,
      }),
    );
    this.publish("state", this.getState());
    if (!this.socket && !this.connecting && now >= this.retryAt)
      void this.establish();
    else if (this.socket?.connected && now >= this.renewAt) void this.renew();
    void this.syncSubscriptions();
  }
  private elect() {
    if (this.lockAbort || this.electionTimer) return;
    // With no way to forward notifications, each eligible tab must have its own transport.
    if (!this.channel && !this.storageAvailable) {
      this.acquire(false);
      return;
    }
    const locks = this.options.runtime.locks;
    if (locks && !this.locksFailed) {
      const abort = new AbortController();
      this.lockAbort = abort;
      const epoch = this.epoch;
      const session = this.session;
      try {
        void locks
          .request(
            `realtime:${this.key}`,
            { mode: "exclusive", signal: abort.signal },
            async () => {
              if (
                abort.signal.aborted ||
                epoch !== this.epoch ||
                !this.eligible() ||
                !sameSession(session, this.getSession())
              )
                return;
              await new Promise<void>((resolve) => {
                this.releaseLock = resolve;
                this.acquire(true);
              });
            },
          )
          .catch(() => {
            if (!abort.signal.aborted) {
              this.locksFailed = true;
              this.lockAbort = null;
              this.elect();
            }
          })
          .finally(() => {
            if (this.lockAbort === abort) this.lockAbort = null;
          });
      } catch {
        this.locksFailed = true;
        this.lockAbort = null;
        this.elect();
      }
      return;
    }
    const epoch = this.epoch;
    this.electionTimer = setTimeout(() => {
      this.electionTimer = null;
      if (epoch !== this.epoch || !this.eligible()) return;
      const lease = parseObject(
        this.options.runtime.storage.read(`${this.key}:lease`),
      );
      if (
        object(lease) &&
        typeof lease.source === "string" &&
        lease.source !== this.options.runtime.tabId &&
        typeof lease.expires === "number" &&
        lease.expires > this.options.runtime.now()
      )
        return;
      const peers = [...this.peers.entries()].filter(([, p]) => p.eligible);
      if (peers.some(([, p]) => p.owner)) return;
      if (peers.some(([id]) => id < this.options.runtime.tabId)) return;
      this.acquire(false);
    }, this.options.mergeMs ?? 60);
  }
  private acquire(locked: boolean) {
    this.isOwner = true;
    this.locked = locked;
    this.tick();
  }
  private check(): Promise<void> {
    if (this.validation) return this.validation.promise;
    const abort = new AbortController();
    const timeout = setTimeout(
      () => abort.abort(),
      this.options.validateMs ?? 5000,
    );
    // Race the signal even if an adapter ignores cancellation; stale results remain fenced.
    const cancelled = new Promise<never>((_, reject) =>
      abort.signal.addEventListener(
        "abort",
        () => reject(new SessionValidationError("temporary")),
        { once: true },
      ),
    );
    const promise = Promise.race([
      this.config.validate(abort.signal),
      cancelled,
    ]).finally(() => {
      clearTimeout(timeout);
      if (this.validation?.abort === abort) this.validation = null;
    });
    this.validation = { abort, promise };
    return promise;
  }
  private async establish() {
    if (this.connecting || !this.isOwner) return;
    this.connecting = true;
    const epoch = this.epoch;
    const s = this.session;
    this.state.lastAttemptAt = this.options.runtime.now();
    this.state.status = "connecting";
    try {
      await this.check();
      if (!this.valid(epoch, s)) return;
      const latest = this.getSession();
      if (!latest || latest.expiresAt <= this.options.runtime.now())
        throw new SessionValidationError("token_expired");
      const socket = this.options.connect(latest, {
        recovery: this.state.lastConnectedAt > 0 || this.failures > 0,
        tab: this.options.runtime.tabId,
      });
      this.socket = socket;
      this.handshakeToken = latest;
      const current = () => this.valid(epoch, s) && this.socket === socket;
      socket.on("connect", () => {
        if (!current()) return;
        if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
        this.handshakeTimer = null;
        this.connecting = false;
        this.failures = 0;
        this.retryAt = 0;
        this.state.status = "connected";
        this.state.lastConnectedAt = this.options.runtime.now();
        this.state.lastError = "";
        this.renewAt = latest.expiresAt - (this.options.renewLeadMs ?? 60000);
        this.acknowledged.clear();
        this.publish("state", this.getState());
        this.publish("recovery", {});
        this.recoveries.forEach((fn) => fn());
        void this.syncSubscriptions();
      });
      const failed = (kind: string) => {
        if (!current()) return;
        this.connecting = false;
        this.closeSocket();
        this.backoff(kind);
      };
      socket.on("disconnect", () => failed("transport"));
      socket.on("connect_error", (error: Error & { data?: unknown }) => {
        if (!current()) return;
        if (object(error.data) && error.data.kind === "session_invalid")
          this.broadcastLogout("socket-auth-invalid");
        else
          failed(
            object(error.data) && error.data.kind === "token_expired"
              ? "token_expired"
              : "transport",
          );
      });
      socket.on("auth_status", (data: unknown) => {
        if (!current() || !object(data)) return;
        if (data.kind === "session_invalid")
          this.broadcastLogout("socket-auth-invalid");
        else if (data.kind === "token_expired") failed("token_expired");
      });
      socket.on("api_notice", (notice: unknown) => {
        if (!current() || !this.options.notice(notice)) return;
        this.publish("notice", notice);
        this.handlers.forEach((fn) => fn(notice));
      });
      this.handshakeTimer = setTimeout(
        () => failed("handshake_timeout"),
        this.options.handshakeMs ?? 8000,
      );
      socket.connect();
    } catch (error) {
      if (!this.valid(epoch, s)) return;
      this.connecting = false;
      if (
        error instanceof SessionValidationError &&
        error.kind === "session_invalid"
      )
        this.broadcastLogout("http-401");
      else this.backoff("validation");
    }
  }
  private async renew() {
    if (this.validation || !this.socket?.connected || !this.handshakeToken)
      return;
    const epoch = this.epoch;
    const socket = this.socket;
    const old = this.handshakeToken;
    // Keep the original deadline even when ordinary HTTP responses update stored tokens.
    this.renewAt = this.options.runtime.now() + 1000;
    try {
      await this.check();
      if (!this.valid(epoch, old) || this.socket !== socket) return;
      const latest = this.getSession();
      if (!latest || latest.expiresAt <= old.expiresAt) {
        this.renewAt = Math.max(
          this.options.runtime.now() + 1000,
          old.expiresAt,
        );
        if (old.expiresAt <= this.options.runtime.now()) {
          this.closeSocket();
          this.backoff("token_expired");
        }
        return;
      }
      const result: unknown = await socket
        .timeout(this.options.validateMs ?? 5000)
        .emitWithAck("auth_update", { authorization: latest.authorization });
      if (!this.valid(epoch, old) || this.socket !== socket) return;
      if (!object(result) || result.ok !== true) {
        if (object(result) && result.kind === "session_invalid")
          this.broadcastLogout("socket-auth-invalid");
        else throw new SessionValidationError("temporary");
        return;
      }
      this.handshakeToken = latest;
      this.renewAt = latest.expiresAt - (this.options.renewLeadMs ?? 60000);
    } catch (error) {
      if (!this.valid(epoch, old) || this.socket !== socket) return;
      if (
        error instanceof SessionValidationError &&
        error.kind === "session_invalid"
      )
        this.broadcastLogout("http-401");
      else {
        this.renewAt =
          this.options.runtime.now() +
          Math.min(30000, 500 * 2 ** Math.min(++this.failures, 6));
        if (old.expiresAt <= this.options.runtime.now()) {
          this.closeSocket();
          this.backoff("renewal");
        }
      }
    }
  }
  private closeSocket() {
    if (this.handshakeTimer) clearTimeout(this.handshakeTimer);
    this.handshakeTimer = null;
    this.subscriptionAbort?.abort();
    this.subscriptionAbort = null;
    this.subscriptionRunning = false;
    this.socket?.removeAllListeners();
    this.socket?.disconnect();
    this.socket = null;
    this.handshakeToken = null;
    this.renewAt = Infinity;
    this.acknowledged.clear();
  }
  private backoff(kind: string) {
    this.state.status = "disconnected";
    this.state.lastDisconnectedAt = this.options.runtime.now();
    this.state.lastError = kind;
    const delay = Math.min(
      30000,
      500 *
        2 ** Math.min(this.failures++, 6) *
        (0.8 + this.options.runtime.random() * 0.4),
    );
    this.retryAt = this.options.runtime.now() + delay;
    this.publish("state", this.getState());
    // A single scheduler controls retry; library reconnection is disabled.
    const epoch = this.epoch;
    if (this.retryTimer) clearTimeout(this.retryTimer);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      if (epoch === this.epoch) this.tick();
    }, delay);
  }
  private aggregate() {
    const all = [
      ...this.presence().intents,
      ...[...this.peers.values()]
        .filter((p) => p.eligible)
        .flatMap((p) => p.intents),
    ];
    const result = new Map<string, number | null>();
    all.forEach((i) => {
      const old = result.get(i.resource);
      result.set(
        i.resource,
        !result.has(i.resource)
          ? i.baseline
          : old === null || i.baseline === null
            ? null
            : Math.min(old as number, i.baseline),
      );
    });
    return result;
  }
  private async syncSubscriptions() {
    if (
      !this.isOwner ||
      !this.socket?.connected ||
      this.subscriptionRunning ||
      this.options.runtime.now() < this.subscriptionRetryAt
    )
      return;
    const socket = this.socket;
    const epoch = this.epoch;
    const session = this.session;
    const abort = new AbortController();
    this.subscriptionAbort = abort;
    this.subscriptionRunning = true;
    try {
      const desired = this.aggregate();
      const operations = [...desired.entries()]
        .filter(
          ([r, b]) =>
            !this.acknowledged.has(r) || this.acknowledged.get(r) !== b,
        )
        .map(([resource, baseline]) => ({
          action: "subscribe",
          resource,
          baseline,
        }));
      operations.push(
        ...[...this.acknowledged.keys()]
          .filter((r) => !desired.has(r))
          .map((resource) => ({
            action: "unsubscribe",
            resource,
            baseline: null,
          })),
      );
      for (const op of operations) {
        const result: unknown = await socket
          .timeout(this.options.validateMs ?? 5000)
          .emitWithAck("subscription", op);
        if (
          abort.signal.aborted ||
          !this.valid(epoch, session) ||
          this.socket !== socket
        )
          return;
        if (!object(result) || result.ok !== true)
          throw new Error("subscription rejected");
        if (op.action === "unsubscribe") this.acknowledged.delete(op.resource);
        else this.acknowledged.set(op.resource, op.baseline);
        if (op.action === "subscribe" && result.calibrate === true) {
          this.publish("calibration", { resource: op.resource });
          this.calibrations.forEach((fn) => fn(op.resource));
        }
      }
      // Changes during an ACK wait need a trailing reconciliation.
      const latest = this.aggregate();
      if (
        latest.size !== this.acknowledged.size ||
        [...latest].some(([r, b]) => this.acknowledged.get(r) !== b)
      ) {
        queueMicrotask(() => {
          void this.syncSubscriptions();
        });
      }
    } catch {
      if (
        !abort.signal.aborted &&
        this.valid(epoch, session) &&
        this.socket === socket
      )
        this.subscriptionRetryAt = this.options.runtime.now() + 1000;
    } finally {
      if (this.subscriptionAbort === abort) {
        this.subscriptionRunning = false;
        this.subscriptionAbort = null;
      }
    }
  }
}
