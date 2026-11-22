export interface UserSocketApiNotice {
  user_kid: string | number;
  api_uri: string;
  kid_for_api: string | number | null;
}

export type UserSocketStatus = 'idle' | 'connecting' | 'connected' | 'disconnected';

export interface UserSocketState {
  status: UserSocketStatus;
  lastAttemptAt: number;
  lastConnectedAt: number;
  lastDisconnectedAt: number;
  lastError: string;
}

export type UserSocketNoticeHandler = (notice: UserSocketApiNotice) => void;
