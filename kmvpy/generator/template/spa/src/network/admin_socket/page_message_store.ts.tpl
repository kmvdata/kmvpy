import type { AdminSocketApiNotice } from './types';

export type AdminSocketPageMessageKind = 'api_notice';

export interface AdminSocketPageApiNoticeMessage {
  id: string;
  kind: 'api_notice';
  payload: AdminSocketApiNotice;
  receivedAt: number;
  dedupeKey: string;
}

export type AdminSocketPageMessage = AdminSocketPageApiNoticeMessage;
export type AdminSocketPageMessagePredicate = (message: AdminSocketPageMessage) => boolean;

const MAX_PAGE_MESSAGES = 200;

const createMessageId = () => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `admin-socket-page-message:${Date.now()}:${Math.random().toString(16).slice(2)}`;
};

const createApiNoticeDedupeKey = (notice: AdminSocketApiNotice) =>
  `api_notice:${notice.api_uri}:${notice.kid_for_api ?? ''}`;

class AdminSocketPageMessageStoreManager {
  private readonly messages: AdminSocketPageMessage[] = [];

  appendApiNotice(notice: AdminSocketApiNotice) {
    const message: AdminSocketPageApiNoticeMessage = {
      id: createMessageId(),
      kind: 'api_notice',
      payload: notice,
      receivedAt: Date.now(),
      dedupeKey: createApiNoticeDedupeKey(notice),
    };

    const duplicateIndex = this.messages.findIndex(
      (item) => item.kind === message.kind && item.dedupeKey === message.dedupeKey,
    );
    if (duplicateIndex >= 0) {
      this.messages.splice(duplicateIndex, 1, message);
    } else {
      this.messages.push(message);
    }

    while (this.messages.length > MAX_PAGE_MESSAGES) {
      this.messages.shift();
    }

    return message;
  }

  snapshot() {
    return [...this.messages];
  }

  removeConsumed(messagesOrIds: Array<AdminSocketPageMessage | string>) {
    const ids = new Set(
      messagesOrIds.map((item) => (typeof item === 'string' ? item : item.id)),
    );
    this.removeWhere((message) => ids.has(message.id));
  }

  removeWhere(predicate: AdminSocketPageMessagePredicate) {
    for (let index = this.messages.length - 1; index >= 0; index -= 1) {
      if (predicate(this.messages[index] as AdminSocketPageMessage)) {
        this.messages.splice(index, 1);
      }
    }
  }

  clear() {
    this.messages.splice(0, this.messages.length);
  }
}

export const AdminSocketPageMessageStore = new AdminSocketPageMessageStoreManager();
