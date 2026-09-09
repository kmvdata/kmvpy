import { io, type Socket } from 'socket.io-client';

import { API_BASE_URL } from 'src/boot/axios';
import { isAuthorizationUsable, normalizeAuthorization } from './auth';
import {
  API_NOTICE_EVENT,
  MIN_RECONNECT_INTERVAL_MS,
  SOCKET_IO_PATH,
  SOCKET_NAMESPACE_PATH,
  USER_SOCKET_CHANNEL_NAME,
  USER_SOCKET_LEADER_STORAGE_KEY,
  USER_SOCKET_MESSAGE_STORAGE_KEY,
} from './constants';
import type {
  UserSocketApiNotice,
  UserSocketNoticeHandler,
  UserSocketState,
} from './types';

type UserSocketLogoutReason = 'manual' | 'http-401' | 'socket-auth-invalid' | 'remote';

interface UserSocketClientConfig {
  getAuthorization: () => string;
  onLogout?: ((reason: UserSocketLogoutReason) => void) | undefined;
}

interface EnsureConnectedOptions {
  authorization?: string;
  force?: boolean;
  start?: boolean;
}

interface UserSocketLeaderRecord {
  tabId: string;
  authorizationKey: string;
  expiresAt: number;
  updatedAt: number;
}

interface UserSocketBaseCrossTabMessage {
  id: string;
  sourceTabId: string;
  sentAt: number;
}

type UserSocketCrossTabMessage =
  | (UserSocketBaseCrossTabMessage & { type: 'hello' | 'election' })
  | (UserSocketBaseCrossTabMessage & {
      type: 'leader-heartbeat' | 'state';
      leaderTabId: string;
      state: UserSocketState;
    })
  | (UserSocketBaseCrossTabMessage & { type: 'api-notice'; notice: UserSocketApiNotice })
  | (UserSocketBaseCrossTabMessage & { type: 'logout'; reason: UserSocketLogoutReason });

type UserSocketPublishMessage =
  | { type: 'hello' | 'election' }
  | {
      type: 'leader-heartbeat' | 'state';
      leaderTabId: string;
      state: UserSocketState;
    }
  | { type: 'api-notice'; notice: UserSocketApiNotice }
  | { type: 'logout'; reason: UserSocketLogoutReason };

const LEADER_LEASE_MS = 15_000;
const LEADER_HEARTBEAT_MS = 5_000;
const MAX_SEEN_MESSAGE_IDS = 300;

const initialState = (): UserSocketState => ({
  status: 'idle',
  lastAttemptAt: 0,
  lastConnectedAt: 0,
  lastDisconnectedAt: 0,
  lastError: '',
});

const createTabId = () => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `tab-${Date.now()}-${Math.random().toString(16).slice(2)}`;
};

const createMessageId = (tabId: string) => `${tabId}:${Date.now()}:${Math.random().toString(16).slice(2)}`;

const authorizationKey = (authorization: string) => {
  let hash = 0;
  for (let index = 0; index < authorization.length; index += 1) {
    hash = Math.imul(31, hash) + authorization.charCodeAt(index);
    hash |= 0;
  }
  return String(hash >>> 0);
};

const safeParseJson = <T>(value: string | null): T | null => {
  if (!value) {
    return null;
  }
  try {
    return JSON.parse(value) as T;
  } catch {
    return null;
  }
};

const isObjectRecord = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === 'object';

const isUserSocketApiNotice = (value: unknown): value is UserSocketApiNotice => {
  if (!isObjectRecord(value)) {
    return false;
  }
  return (
    (typeof value.user_kid === 'string' || typeof value.user_kid === 'number') &&
    typeof value.api_uri === 'string' &&
    (typeof value.kid_for_api === 'string' ||
      typeof value.kid_for_api === 'number' ||
      value.kid_for_api === null)
  );
};

const isUserSocketState = (value: unknown): value is UserSocketState => {
  if (!isObjectRecord(value)) {
    return false;
  }
  return (
    (value.status === 'idle' ||
      value.status === 'connecting' ||
      value.status === 'connected' ||
      value.status === 'disconnected') &&
    typeof value.lastAttemptAt === 'number' &&
    typeof value.lastConnectedAt === 'number' &&
    typeof value.lastDisconnectedAt === 'number' &&
    typeof value.lastError === 'string'
  );
};

const isCrossTabMessage = (value: unknown): value is UserSocketCrossTabMessage => {
  if (!isObjectRecord(value) || typeof value.id !== 'string' || typeof value.sourceTabId !== 'string') {
    return false;
  }

  switch (value.type) {
    case 'hello':
    case 'election':
      return true;
    case 'leader-heartbeat':
    case 'state':
      return typeof value.leaderTabId === 'string' && isUserSocketState(value.state);
    case 'api-notice':
      return isUserSocketApiNotice(value.notice);
    case 'logout':
      return (
        value.reason === 'manual' ||
        value.reason === 'http-401' ||
        value.reason === 'socket-auth-invalid' ||
        value.reason === 'remote'
      );
    default:
      return false;
  }
};

class UserSocketClientManager {
  private socket: Socket | null = null;
  private broadcastChannel: BroadcastChannel | null = null;
  private maintenanceTimer: ReturnType<typeof setInterval> | null = null;
  private readonly tabId = createTabId();
  private getAuthorization: () => string = () => '';
  private onLogout: (reason: UserSocketLogoutReason) => void = () => undefined;
  private readonly handlers = new Set<UserSocketNoticeHandler>();
  private readonly state: UserSocketState = initialState();
  private readonly seenMessageIds: string[] = [];
  private readonly seenMessageIdSet = new Set<string>();
  private activeAuthorization = '';
  private currentLeaderId = '';
  private boundBrowserEvents = false;

  configure(config: UserSocketClientConfig) {
    this.getAuthorization = config.getAuthorization;
    this.onLogout = config.onLogout ?? (() => undefined);
  }

  start() {
    if (typeof window === 'undefined') {
      return;
    }

    this.bindBrowserEvents();
    this.ensureBroadcastChannel();
    this.ensureMaintenanceTimer();
    this.publishMessage({ type: 'hello' });
    this.ensureConnected({ start: true });
  }

  stop() {
    this.disconnect();
    this.releaseBroadcastChannel();
    this.clearMaintenanceTimer();
  }

  disconnect() {
    this.resignLeadership();
    this.disconnectSocket();
    Object.assign(this.state, {
      ...initialState(),
      lastDisconnectedAt: Date.now(),
    });
    this.broadcastState();
  }

  broadcastLogout(reason: UserSocketLogoutReason = 'manual') {
    this.publishMessage({ type: 'logout', reason }, { includeSelf: true });
  }

  notifyAuthorizationChanged(authorization?: string) {
    if (authorization === undefined) {
      this.ensureConnected({ force: true });
      return;
    }
    this.ensureConnected({ authorization, force: true });
  }

  reconnectManually() {
    return this.ensureConnected({ force: true });
  }

  onApiNotice(handler: UserSocketNoticeHandler) {
    this.handlers.add(handler);
    return () => {
      this.handlers.delete(handler);
    };
  }

  getState(): UserSocketState {
    return { ...this.state };
  }

  isConnected() {
    return this.state.status === 'connected';
  }

  private bindBrowserEvents() {
    if (this.boundBrowserEvents || typeof window === 'undefined') {
      return;
    }

    this.boundBrowserEvents = true;
    window.addEventListener('online', () => {
      this.ensureConnected();
    });
    window.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        this.ensureConnected();
      }
    });
    window.addEventListener('storage', (event) => {
      this.handleStorageEvent(event);
    });
    window.addEventListener('pagehide', () => {
      const wasLeader = this.isLeader();
      this.resignLeadership();
      if (wasLeader) {
        this.disconnectSocket();
      }
    });
    window.addEventListener('pageshow', () => {
      this.ensureBroadcastChannel();
      this.ensureConnected({ force: true, start: true });
    });
  }

  private ensureBroadcastChannel() {
    if (this.broadcastChannel || typeof BroadcastChannel === 'undefined') {
      return;
    }

    this.broadcastChannel = new BroadcastChannel(USER_SOCKET_CHANNEL_NAME);
    this.broadcastChannel.onmessage = (event: MessageEvent<unknown>) => {
      this.handleCrossTabMessage(event.data);
    };
  }

  private releaseBroadcastChannel() {
    this.broadcastChannel?.close();
    this.broadcastChannel = null;
  }

  private ensureMaintenanceTimer() {
    if (this.maintenanceTimer !== null) {
      return;
    }

    this.maintenanceTimer = setInterval(() => {
      this.maintainLeadership();
    }, LEADER_HEARTBEAT_MS);
  }

  private clearMaintenanceTimer() {
    if (this.maintenanceTimer === null) {
      return;
    }
    clearInterval(this.maintenanceTimer);
    this.maintenanceTimer = null;
  }

  private canAttemptReconnect(force = false) {
    if (force) {
      return true;
    }
    return Date.now() - this.state.lastAttemptAt >= MIN_RECONNECT_INTERVAL_MS;
  }

  private ensureConnected(options: EnsureConnectedOptions = {}) {
    if (typeof window === 'undefined') {
      return false;
    }

    const authorization = normalizeAuthorization(options.authorization || this.getAuthorization());
    if (!isAuthorizationUsable(authorization)) {
      this.disconnect();
      return false;
    }

    this.ensureBroadcastChannel();
    this.ensureMaintenanceTimer();

    if (!this.hasValidLeader(authorization)) {
      this.publishMessage({ type: 'election' });
      this.tryBecomeLeader(authorization);
    }

    if (!this.isLeader()) {
      return Boolean(this.currentLeaderId);
    }

    if (!this.canAttemptReconnect(options.force) && this.socket?.connected) {
      return true;
    }

    this.connect(authorization, options.force || options.start);
    return true;
  }

  private connect(authorization: string, force = false) {
    if (this.socket?.connected && this.activeAuthorization === authorization) {
      this.state.status = 'connected';
      this.broadcastState();
      return;
    }
    if (this.socket && this.activeAuthorization === authorization && !force) {
      return;
    }

    this.disconnectSocket();
    this.activeAuthorization = authorization;
    this.state.status = 'connecting';
    this.state.lastAttemptAt = Date.now();
    this.state.lastError = '';
    this.broadcastState();

    const socket = io(`${API_BASE_URL}${SOCKET_NAMESPACE_PATH}`, {
      path: SOCKET_IO_PATH,
      auth: { authorization },
      autoConnect: false,
      reconnection: false,
      transports: ['websocket', 'polling'],
    });

    socket.on('connect', () => {
      this.state.status = 'connected';
      this.state.lastConnectedAt = Date.now();
      this.state.lastError = '';
      this.refreshLeaderLease(authorization);
      this.broadcastState();
    });
    socket.on('disconnect', (reason) => {
      this.state.status = 'disconnected';
      this.state.lastDisconnectedAt = Date.now();
      this.state.lastError = reason;
      this.broadcastState();
    });
    socket.on('connect_error', (error) => {
      this.state.status = 'disconnected';
      this.state.lastDisconnectedAt = Date.now();
      this.state.lastError = error.message;
      this.broadcastState();
      socket.disconnect();
      if (/unauthorized|401|auth/i.test(error.message)) {
        this.broadcastLogout('socket-auth-invalid');
      }
    });
    socket.on(API_NOTICE_EVENT, (notice: UserSocketApiNotice) => {
      this.publishMessage({ type: 'api-notice', notice }, { includeSelf: true });
    });

    this.socket = socket;
    socket.connect();
  }

  private disconnectSocket() {
    this.socket?.removeAllListeners();
    this.socket?.disconnect();
    this.socket = null;
  }

  private maintainLeadership() {
    const authorization = normalizeAuthorization(this.getAuthorization());
    if (!isAuthorizationUsable(authorization)) {
      this.disconnect();
      return;
    }

    if (this.isLeader()) {
      const leaderRecord = this.readLeaderRecord();
      if (leaderRecord?.tabId && leaderRecord.tabId !== this.tabId) {
        this.disconnectSocket();
        this.currentLeaderId = leaderRecord.tabId;
        this.ensureConnected();
        return;
      }
      this.refreshLeaderLease(authorization);
      this.publishState('leader-heartbeat');
      this.ensureConnected();
      return;
    }

    if (!this.hasValidLeader(authorization)) {
      this.tryBecomeLeader(authorization);
    }
  }

  private tryBecomeLeader(authorization: string) {
    const normalizedAuthorization = normalizeAuthorization(authorization);
    if (!isAuthorizationUsable(normalizedAuthorization)) {
      return false;
    }

    const now = Date.now();
    const authKey = authorizationKey(normalizedAuthorization);
    const currentRecord = this.readLeaderRecord();
    if (
      currentRecord &&
      currentRecord.expiresAt > now &&
      currentRecord.tabId !== this.tabId &&
      currentRecord.authorizationKey === authKey
    ) {
      this.currentLeaderId = currentRecord.tabId;
      return false;
    }

    const nextRecord: UserSocketLeaderRecord = {
      tabId: this.tabId,
      authorizationKey: authKey,
      expiresAt: now + LEADER_LEASE_MS,
      updatedAt: now,
    };
    this.writeLeaderRecord(nextRecord);

    const confirmedRecord = this.readLeaderRecord();
    if (confirmedRecord?.tabId !== this.tabId) {
      this.currentLeaderId = confirmedRecord?.tabId || '';
      return false;
    }

    this.currentLeaderId = this.tabId;
    this.publishState('leader-heartbeat');
    this.connect(normalizedAuthorization, true);
    return true;
  }

  private refreshLeaderLease(authorization: string) {
    if (!this.isLeader()) {
      return;
    }
    const now = Date.now();
    this.writeLeaderRecord({
      tabId: this.tabId,
      authorizationKey: authorizationKey(authorization),
      expiresAt: now + LEADER_LEASE_MS,
      updatedAt: now,
    });
  }

  private resignLeadership() {
    if (!this.isLeader()) {
      return;
    }
    const leaderRecord = this.readLeaderRecord();
    if (leaderRecord?.tabId === this.tabId) {
      this.removeLeaderRecord();
    }
    this.currentLeaderId = '';
  }

  private isLeader() {
    return this.currentLeaderId === this.tabId;
  }

  private hasValidLeader(authorization: string) {
    const leaderRecord = this.readLeaderRecord();
    const now = Date.now();
    if (!leaderRecord || leaderRecord.expiresAt <= now) {
      this.currentLeaderId = '';
      return false;
    }
    if (leaderRecord.authorizationKey !== authorizationKey(authorization)) {
      this.currentLeaderId = '';
      return false;
    }
    this.currentLeaderId = leaderRecord.tabId;
    return true;
  }

  private readLeaderRecord() {
    if (typeof window === 'undefined') {
      return null;
    }
    try {
      return safeParseJson<UserSocketLeaderRecord>(
        window.localStorage.getItem(USER_SOCKET_LEADER_STORAGE_KEY),
      );
    } catch {
      return null;
    }
  }

  private writeLeaderRecord(record: UserSocketLeaderRecord) {
    if (typeof window === 'undefined') {
      return;
    }
    try {
      window.localStorage.setItem(USER_SOCKET_LEADER_STORAGE_KEY, JSON.stringify(record));
    } catch {
      this.currentLeaderId = this.tabId;
    }
  }

  private removeLeaderRecord() {
    if (typeof window === 'undefined') {
      return;
    }
    try {
      window.localStorage.removeItem(USER_SOCKET_LEADER_STORAGE_KEY);
    } catch {
      // localStorage 可能被禁用；此时当前 tab 只需放弃本地 leader 身份。
    }
  }

  private broadcastState() {
    if (!this.isLeader()) {
      return;
    }
    this.publishState('state');
  }

  private publishState(type: 'leader-heartbeat' | 'state') {
    this.publishMessage({
      type,
      leaderTabId: this.tabId,
      state: { ...this.state },
    });
  }

  private publishMessage(
    message: UserSocketPublishMessage,
    options: { includeSelf?: boolean } = {},
  ) {
    const fullMessage: UserSocketCrossTabMessage = {
      ...message,
      id: createMessageId(this.tabId),
      sourceTabId: this.tabId,
      sentAt: Date.now(),
    };

    if (options.includeSelf) {
      this.handleCrossTabMessage(fullMessage, { allowSelf: true });
    }

    if (this.broadcastChannel) {
      this.broadcastChannel.postMessage(fullMessage);
      return;
    }

    if (typeof window === 'undefined') {
      return;
    }
    try {
      window.localStorage.setItem(USER_SOCKET_MESSAGE_STORAGE_KEY, JSON.stringify(fullMessage));
    } catch {
      // 没有 BroadcastChannel 且 localStorage 不可写时，只能保留当前 tab 的本地行为。
    }
  }

  private handleStorageEvent(event: StorageEvent) {
    if (event.key === USER_SOCKET_MESSAGE_STORAGE_KEY) {
      const message = safeParseJson<unknown>(event.newValue);
      this.handleCrossTabMessage(message);
      return;
    }

    if (event.key === USER_SOCKET_LEADER_STORAGE_KEY) {
      const leaderRecord = safeParseJson<UserSocketLeaderRecord>(event.newValue);
      if (leaderRecord?.tabId && leaderRecord.tabId !== this.tabId) {
        if (this.isLeader()) {
          this.disconnectSocket();
        }
        this.currentLeaderId = leaderRecord.tabId;
      }
      this.ensureConnected({ force: true });
      return;
    }

    this.ensureConnected({ force: true });
  }

  private handleCrossTabMessage(value: unknown, options: { allowSelf?: boolean } = {}) {
    if (!isCrossTabMessage(value)) {
      return;
    }
    if (!options.allowSelf && value.sourceTabId === this.tabId) {
      return;
    }
    if (this.hasSeenMessage(value.id)) {
      return;
    }

    this.rememberMessage(value.id);
    switch (value.type) {
      case 'hello':
      case 'election':
        this.ensureConnected();
        break;
      case 'leader-heartbeat':
      case 'state':
        this.handleLeaderState(value.leaderTabId, value.state);
        break;
      case 'api-notice':
        if (isAuthorizationUsable(normalizeAuthorization(this.getAuthorization()))) {
          this.dispatchApiNotice(value.notice);
        }
        break;
      case 'logout':
        this.handleLogout(value.reason);
        break;
      default:
        break;
    }
  }

  private handleLeaderState(leaderTabId: string, state: UserSocketState) {
    if (leaderTabId === this.tabId) {
      return;
    }
    if (this.isLeader()) {
      this.disconnectSocket();
    }
    this.currentLeaderId = leaderTabId;
    Object.assign(this.state, state);
  }

  private handleLogout(reason: UserSocketLogoutReason) {
    this.resignLeadership();
    this.disconnectSocket();
    Object.assign(this.state, {
      ...initialState(),
      lastDisconnectedAt: Date.now(),
    });
    this.activeAuthorization = '';
    this.onLogout(reason);
    if (typeof window !== 'undefined') {
      window.dispatchEvent(new CustomEvent('user-socket-logout', { detail: { reason } }));
    }
  }

  private hasSeenMessage(id: string) {
    return this.seenMessageIdSet.has(id);
  }

  private rememberMessage(id: string) {
    this.seenMessageIds.push(id);
    this.seenMessageIdSet.add(id);
    while (this.seenMessageIds.length > MAX_SEEN_MESSAGE_IDS) {
      const droppedId = this.seenMessageIds.shift();
      if (droppedId) {
        this.seenMessageIdSet.delete(droppedId);
      }
    }
  }

  private dispatchApiNotice(notice: UserSocketApiNotice) {
    console.log('[UserSocket] 收到 api_notice', notice);
    this.handlers.forEach((handler) => handler(notice));
    window.dispatchEvent(new CustomEvent<UserSocketApiNotice>('user-socket-api-notice', { detail: notice }));
  }
}

export const UserSocketClient = new UserSocketClientManager();
export { MIN_RECONNECT_INTERVAL_MS };
