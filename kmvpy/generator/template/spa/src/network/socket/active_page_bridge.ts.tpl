import { UserSocketPageMessageStore } from './page_message_store';
import type {
  UserSocketPageApiNoticeMessage,
  UserSocketPageMessage,
  UserSocketPageMessagePredicate,
} from './page_message_store';
import type { UserSocketApiNotice } from './types';

export interface UserSocketPageMessageContext {
  latest: UserSocketPageMessage | null;
  messages: UserSocketPageMessage[];
  getApiNotices: (
    predicate?: (notice: UserSocketApiNotice, message: UserSocketPageApiNoticeMessage) => boolean,
  ) => UserSocketPageApiNoticeMessage[];
  removeConsumed: (messagesOrIds: Array<UserSocketPageMessage | string>) => void;
  clearWhere: (predicate: UserSocketPageMessagePredicate) => void;
}

export type UserSocketPageMessageHandler = (
  context: UserSocketPageMessageContext,
) => void | Promise<void>;

interface ActivePageHandlerEntry {
  id: string;
  handler: UserSocketPageMessageHandler;
}

const createHandlerId = () =>
  `socket-page-handler:${Date.now()}:${Math.random().toString(16).slice(2)}`;

class UserSocketActivePageBridgeManager {
  private readonly handlers: ActivePageHandlerEntry[] = [];

  register(handler: UserSocketPageMessageHandler) {
    const entry: ActivePageHandlerEntry = {
      id: createHandlerId(),
      handler,
    };
    this.handlers.push(entry);

    return () => {
      const index = this.handlers.findIndex((item) => item.id === entry.id);
      if (index >= 0) {
        this.handlers.splice(index, 1);
      }
    };
  }

  notifyActivePage(latest: UserSocketPageMessage | null = null) {
    const entry = this.handlers[this.handlers.length - 1];
    if (!entry) {
      return;
    }

    const messages = UserSocketPageMessageStore.snapshot();
    if (messages.length === 0 && latest === null) {
      return;
    }

    this.dispatch(entry.handler, latest, messages);
  }

  flushActivePage() {
    this.notifyActivePage();
  }

  clear() {
    this.handlers.splice(0, this.handlers.length);
  }

  private dispatch(
    handler: UserSocketPageMessageHandler,
    latest: UserSocketPageMessage | null,
    messages: UserSocketPageMessage[],
  ) {
    const context: UserSocketPageMessageContext = {
      latest,
      messages,
      getApiNotices: (predicate) =>
        messages.filter((message): message is UserSocketPageApiNoticeMessage => {
          if (message.kind !== 'api_notice') {
            return false;
          }
          return predicate ? predicate(message.payload, message) : true;
        }),
      removeConsumed: (messagesOrIds) => {
        UserSocketPageMessageStore.removeConsumed(messagesOrIds);
      },
      clearWhere: (predicate) => {
        UserSocketPageMessageStore.removeWhere(predicate);
      },
    };

    try {
      const result = handler(context);
      if (result instanceof Promise) {
        result.catch((error: unknown) => {
          console.warn('[UserSocket] 激活页消息处理失败', error);
        });
      }
    } catch (error) {
      console.warn('[UserSocket] 激活页消息处理失败', error);
    }
  }
}

export const UserSocketActivePageBridge = new UserSocketActivePageBridgeManager();
