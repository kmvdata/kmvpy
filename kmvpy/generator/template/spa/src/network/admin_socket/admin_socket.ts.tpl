import { createDomainClient, validNotice } from "../realtime/client";
import type { AdminSocketApiNotice } from "./types";
export const MIN_RECONNECT_INTERVAL_MS = 500;
export const AdminSocketClient = createDomainClient<AdminSocketApiNotice>(
  "admin",
  "/admin_ws",
  (v): v is AdminSocketApiNotice => validNotice(v),
);
