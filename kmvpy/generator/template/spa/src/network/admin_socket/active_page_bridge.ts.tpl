import { AdminSocketPageMessageStore } from './page_message_store';
import type {
  AdminSocketPageApiNoticeMessage,
  AdminSocketPageMessage,
  AdminSocketPageMessagePredicate,
} from './page_message_store';
import type { AdminSocketApiNotice } from './types';

export interface AdminSocketPageMessageContext {
  latest: AdminSocketPageMessage | null;
  messages: AdminSocketPageMessage[];
  getApiNotices: (
    predicate?: (notice: AdminSocketApiNotice, message: AdminSocketPageApiNoticeMessage) => boolean,
  ) => AdminSocketPageApiNoticeMessage[];
  removeConsumed: (messagesOrIds: Array<AdminSocketPageMessage | string>) => void;
  clearWhere: (predicate: AdminSocketPageMessagePredicate) => void;
}

export type AdminSocketPageMessageHandler = (
  context: AdminSocketPageMessageContext,
) => void | Promise<void>;

interface ActivePageHandlerEntry {
  id: string;
  handler: AdminSocketPageMessageHandler;
}

const createHandlerId = () =>
  `admin-socket-page-handler:${Date.now()}:${Math.random().toString(16).slice(2)}`;

class AdminSocketActivePageBridgeManager {
  private readonly handlers: ActivePageHandlerEntry[] = [];

  register(handler: AdminSocketPageMessageHandler) {
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

  notifyActivePage(latest: AdminSocketPageMessage | null = null) {
    const entry = this.handlers[this.handlers.length - 1];
    if (!entry) {
      return;
    }

    const messages = AdminSocketPageMessageStore.snapshot();
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
    handler: AdminSocketPageMessageHandler,
    latest: AdminSocketPageMessage | null,
    messages: AdminSocketPageMessage[],
  ) {
    const context: AdminSocketPageMessageContext = {
      latest,
      messages,
      getApiNotices: (predicate) =>
        messages.filter((message): message is AdminSocketPageApiNoticeMessage => {
          if (message.kind !== 'api_notice') {
            return false;
          }
          return predicate ? predicate(message.payload, message) : true;
        }),
      removeConsumed: (messagesOrIds) => {
        AdminSocketPageMessageStore.removeConsumed(messagesOrIds);
      },
      clearWhere: (predicate) => {
        AdminSocketPageMessageStore.removeWhere(predicate);
      },
    };

    try {
      const result = handler(context);
      if (result instanceof Promise) {
        result.catch((error: unknown) => {
          console.warn('[AdminSocket] 激活页消息处理失败', error);
        });
      }
    } catch (error) {
      console.warn('[AdminSocket] 激活页消息处理失败', error);
    }
  }
}

export const AdminSocketActivePageBridge = new AdminSocketActivePageBridgeManager();
