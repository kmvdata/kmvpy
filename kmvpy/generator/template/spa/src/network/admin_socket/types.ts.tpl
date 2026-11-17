export interface AdminSocketApiNotice {
  api_uri: string;
  kid_for_api: string | number | null;
}

export type AdminSocketStatus = 'idle' | 'connecting' | 'connected' | 'disconnected';

export interface AdminSocketState {
  status: AdminSocketStatus;
  lastAttemptAt: number;
  lastConnectedAt: number;
  lastDisconnectedAt: number;
  lastError: string;
}

export type AdminSocketLogoutReason = 'manual' | 'http-401' | 'socket-auth-invalid' | 'remote';

export type AdminSocketNoticeHandler = (notice: AdminSocketApiNotice) => void;
