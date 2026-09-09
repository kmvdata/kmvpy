import { onActivated, onDeactivated, onMounted, onUnmounted } from 'vue';

import { AdminSocketActivePageBridge } from 'src/network/admin_socket';
import type { AdminSocketPageMessageHandler } from 'src/network/admin_socket';

export const onAdminSocketPageMessages = (handler: AdminSocketPageMessageHandler) => {
  let off: (() => void) | null = null;

  const activate = () => {
    if (off) {
      return;
    }
    off = AdminSocketActivePageBridge.register(handler);
    AdminSocketActivePageBridge.flushActivePage();
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
