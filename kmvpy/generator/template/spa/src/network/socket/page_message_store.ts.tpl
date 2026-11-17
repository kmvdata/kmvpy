import type { UserSocketApiNotice } from './types';

export type UserSocketPageMessageKind = 'api_notice';

export interface UserSocketPageApiNoticeMessage {
  id: string;
  kind: 'api_notice';
  payload: UserSocketApiNotice;
  receivedAt: number;
  dedupeKey: string;
}

export type UserSocketPageMessage = UserSocketPageApiNoticeMessage;
export type UserSocketPageMessagePredicate = (message: UserSocketPageMessage) => boolean;

const MAX_PAGE_MESSAGES = 200;

const createMessageId = () => {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `socket-page-message:${Date.now()}:${Math.random().toString(16).slice(2)}`;
};

const createApiNoticeDedupeKey = (notice: UserSocketApiNotice) =>
  `api_notice:${notice.api_uri}:${notice.kid_for_api ?? ''}`;

class UserSocketPageMessageStoreManager {
  private readonly messages: UserSocketPageMessage[] = [];

  appendApiNotice(notice: UserSocketApiNotice) {
    const message: UserSocketPageApiNoticeMessage = {
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
      // 页面未消费前，同一业务目标只保留最新通知，避免激活补偿时重复拉取同一资源。
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

  removeConsumed(messagesOrIds: Array<UserSocketPageMessage | string>) {
    const ids = new Set(
      messagesOrIds.map((item) => (typeof item === 'string' ? item : item.id)),
    );
    this.removeWhere((message) => ids.has(message.id));
  }

  removeWhere(predicate: UserSocketPageMessagePredicate) {
    for (let index = this.messages.length - 1; index >= 0; index -= 1) {
      if (predicate(this.messages[index] as UserSocketPageMessage)) {
        this.messages.splice(index, 1);
      }
    }
  }

  clear() {
    this.messages.splice(0, this.messages.length);
  }
}

export const UserSocketPageMessageStore = new UserSocketPageMessageStoreManager();
