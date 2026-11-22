import { createTabId } from "src/network/realtime/runtime";
import { onActivated, onDeactivated, onMounted, onUnmounted, watch } from "vue";
import { UserSocketClient } from "src/network/socket";
import { AdminSocketClient } from "src/network/admin_socket";
import { pageLifecycle, type AuthDomain } from "src/network/realtime/lifecycle";
import {
  RefreshCoordinator,
  type RefreshOptions,
} from "src/network/realtime/refresh";
export function usePageRefresh<T>(
  domain: AuthDomain,
  resource: () => string,
  options: Pick<RefreshOptions<T>, "read" | "apply" | "error">,
) {
  const client = domain === "user" ? UserSocketClient : AdminSocketClient;
  let active = false;
  let version = 0;
  const coordinator = new RefreshCoordinator<T>({
    ...options,
    identity: () => ({
      resource: resource(),
      session: client.getSession()
        ? JSON.stringify([
            domain,
            client.getSession()?.user,
            client.getSession()?.id,
          ])
        : "",
      lifecycle: version + pageLifecycle.version,
    }),
    eligible: () => active && client.eligible(),
  });
  const offCalibration = client.onCalibration((key) => {
    if (key === resource()) coordinator.request();
  });
  const offRecovery = client.onRecovery(() => coordinator.recover());
  let offSubscription: (() => void) | null = null;
  const subscriptionId = createTabId();
  const syncSubscription = () => {
    offSubscription?.();
    offSubscription = null;
    if (active && client.eligible() && resource())
      offSubscription = client.subscribe(subscriptionId, {
        resource: resource(),
        baseline: null,
      });
  };
  const offChange = client.onEligibilityChange(() => {
    coordinator.changed();
    syncSubscription();
  });
  const stopWatch = watch(resource, () => {
    version++;
    coordinator.changed();
    syncSubscription();
    coordinator.request();
  });
  const activate = () => {
    if (!active) {
      active = true;
      version++;
      coordinator.changed();
      syncSubscription();
      coordinator.recover();
    }
  };
  const deactivate = () => {
    active = false;
    version++;
    coordinator.changed();
    syncSubscription();
  };
  onMounted(activate);
  onActivated(activate);
  onDeactivated(deactivate);
  onUnmounted(() => {
    deactivate();
    coordinator.dispose();
    offCalibration();
    offRecovery();
    offChange();
    stopWatch();
  });
  return () => coordinator.request();
}
