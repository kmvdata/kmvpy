import { onActivated, onDeactivated, onMounted, onUnmounted } from 'vue';

import { UserSocketActivePageBridge } from 'src/network/socket';
import type { UserSocketPageMessageHandler } from 'src/network/socket';

export const onSocketPageMessages = (handler: UserSocketPageMessageHandler) => {
  let off: (() => void) | null = null;

  const activate = () => {
    if (off) {
      return;
    }
    off = UserSocketActivePageBridge.register(handler);
    UserSocketActivePageBridge.flushActivePage();
  };

  const deactivate = () => {
    off?.();
    off = null;
  };

  onMounted(activate);
  onUnmounted(deactivate);
  onActivated(activate);
  onDeactivated(deactivate);
};
