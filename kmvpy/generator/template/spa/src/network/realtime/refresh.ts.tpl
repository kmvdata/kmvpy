/** Each session/resource has one reader; data remains page-local and is never shared between tabs. */
export interface RefreshContext {
  resource: string;
  session: string;
  signal: AbortSignal;
  target: number | null;
}
export interface RefreshOptions<T> {
  identity: () => { resource: string; session: string; lifecycle: number };
  eligible: () => boolean;
  read: (context: RefreshContext) => Promise<T>;
  apply: (value: T) => void;
  error?: (error: unknown) => void;
  mergeMs?: number;
  /** Optional future version adapter. read() must finish its own delta pagination. */
  versionOf?: (value: T) => number | null;
  complete?: (value: T) => boolean;
  requiresCalibration?: (value: T) => boolean;
  calibrate?: (context: RefreshContext) => Promise<T>;
}
interface SharedRead {
  abort: AbortController;
  promise: Promise<unknown>;
  consumers: number;
}
const reads = new Map<string, SharedRead>();
function sharedRead<T>(
  key: string,
  context: RefreshContext,
  read: RefreshOptions<T>["read"],
) {
  let entry = reads.get(key);
  if (!entry) {
    const abort = new AbortController();
    const next: SharedRead = {
      abort,
      consumers: 0,
      promise: Promise.resolve().then(() =>
        read({ ...context, signal: abort.signal }),
      ),
    };
    next.promise = next.promise.finally(() => {
      if (reads.get(key) === next) reads.delete(key);
    });
    entry = next;
    reads.set(key, next);
  }
  entry.consumers++;
  const current = entry;
  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    current.consumers--;
    if (!current.consumers) {
      current.abort.abort();
      if (reads.get(key) === current) reads.delete(key);
    }
  };
  context.signal.addEventListener("abort", release, { once: true });
  return current.promise
    .then((value) => value as T)
    .finally(() => {
      context.signal.removeEventListener("abort", release);
      release();
    });
}
export class RefreshCoordinator<T> {
  private dirty = false;
  private target: number | null = null;
  private generation = 0;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private running: AbortController | null = null;
  private runningIdentity = "";
  private retry = 0;
  private retryAt = 0;
  private disposed = false;
  private loadedVersion: number | null = null;
  private identityKey = "";
  getLoadedVersion() {
    return this.loadedVersion;
  }
  private syncIdentity() {
    const identity = this.options.identity();
    const key = JSON.stringify([identity.session, identity.resource]);
    if (this.identityKey && key !== this.identityKey) {
      this.loadedVersion = null;
      this.target = null;
    }
    this.identityKey = key;
  }
  constructor(private options: RefreshOptions<T>) {}
  request(target: number | null = null) {
    this.syncIdentity();
    this.dirty = true;
    if (target !== null) this.target = Math.max(this.target ?? 0, target);
    this.schedule();
  }
  recover() {
    // An ongoing authoritative read already calibrates this identity.
    if (
      this.running &&
      this.runningIdentity === JSON.stringify(this.options.identity())
    )
      return;
    this.request();
  }
  changed() {
    this.syncIdentity();
    this.generation++;
    if (this.running) {
      this.running.abort();
      this.running = null;
      this.dirty = true;
    }
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
    this.retryAt = 0;
    this.schedule();
  }
  dispose() {
    this.disposed = true;
    this.changed();
  }
  private schedule() {
    const identity = this.options.identity();
    if (
      this.disposed ||
      !this.dirty ||
      !this.options.eligible() ||
      !identity.session ||
      !identity.resource ||
      this.running ||
      this.timer
    )
      return;
    this.timer = setTimeout(
      () => {
        this.timer = null;
        void this.flush();
      },
      Math.max(this.options.mergeMs ?? 60, this.retryAt - Date.now()),
    );
  }
  private async flush() {
    const identity = this.options.identity();
    if (
      this.disposed ||
      !this.dirty ||
      !this.options.eligible() ||
      !identity.session ||
      !identity.resource ||
      this.running
    )
      return;
    const serialized = JSON.stringify(identity);
    const generation = this.generation;
    const abort = new AbortController();
    this.running = abort;
    this.runningIdentity = serialized;
    const target = this.target;
    this.dirty = false;
    try {
      let value = await sharedRead(
        JSON.stringify([identity.session, identity.resource]),
        { ...identity, signal: abort.signal, target },
        this.options.read,
      );
      if (
        abort.signal.aborted ||
        generation !== this.generation ||
        !this.options.eligible() ||
        serialized !== JSON.stringify(this.options.identity())
      )
        return;
      const trustworthy = (result: T) => {
        const version = this.options.versionOf?.(result);
        return (
          !this.options.versionOf ||
          (typeof version === "number" &&
            Number.isSafeInteger(version) &&
            version >= 0 &&
            (target === null || version >= target) &&
            (this.loadedVersion === null || version >= this.loadedVersion))
        );
      };
      if (
        this.options.requiresCalibration?.(value) ||
        this.options.complete?.(value) === false ||
        !trustworthy(value)
      ) {
        if (!this.options.calibrate)
          throw new Error("authoritative calibration required");
        value = await sharedRead(
          JSON.stringify([identity.session, identity.resource, "calibration"]),
          { ...identity, signal: abort.signal, target },
          this.options.calibrate,
        );
        if (
          abort.signal.aborted ||
          generation !== this.generation ||
          !this.options.eligible() ||
          serialized !== JSON.stringify(this.options.identity())
        )
          return;
        if (this.options.complete?.(value) === false || !trustworthy(value))
          throw new Error("incomplete calibration");
      }
      this.options.apply(value);
      this.retry = 0;
      this.retryAt = 0;
      if (this.options.versionOf)
        this.loadedVersion = this.options.versionOf(value);
      if (this.target === target) this.target = null;
    } catch (error) {
      if (abort.signal.aborted || generation !== this.generation) return;
      this.dirty = true;
      this.retryAt =
        Date.now() +
        Math.min(
          30000,
          500 * 2 ** Math.min(this.retry++, 6) * (0.8 + Math.random() * 0.4),
        );
      this.options.error?.(error);
    } finally {
      if (this.running === abort) this.running = null;
      this.schedule();
    }
  }
}
