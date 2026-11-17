import { io } from "socket.io-client";
import { API_BASE_URL, AUTH_STORAGE_KEY } from "src/boot/axios";
import { RealtimeManager } from "./manager";
import { browserRuntime, object } from "./runtime";
import { pageLifecycle } from "./lifecycle";
export function createDomainClient<N>(
  domain: "user" | "admin",
  namespace: string,
  notice: (v: unknown) => v is N,
) {
  const client = new RealtimeManager<N>({
    app: AUTH_STORAGE_KEY,
    domain,
    runtime: browserRuntime(),
    eligible: () => pageLifecycle.eligible(domain),
    notice,
    connect: (session, observation) =>
      io(`${API_BASE_URL}${namespace}`, {
        path: "/ws/socket.io",
        auth: {
          authorization: session.authorization,
          recovery: observation.recovery,
          tab_id: observation.tab,
        },
        forceNew: true,
        multiplex: false,
        autoConnect: false,
        reconnection: false,
        timeout: 8000,
        transports: ["polling", "websocket"],
        withCredentials: true,
      }),
  });
  pageLifecycle.onChange(() => client.lifecycleChanged());
  return client;
}
export const validNotice = (v: unknown) =>
  object(v) &&
  typeof v.api_uri === "string" &&
  (v.kid_for_api === null ||
    typeof v.kid_for_api === "string" ||
    typeof v.kid_for_api === "number");
