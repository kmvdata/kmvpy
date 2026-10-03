import { createDomainClient, validNotice } from "../realtime/client";
import { object } from "../realtime/runtime";
import type { UserSocketApiNotice } from "./types";
export const MIN_RECONNECT_INTERVAL_MS = 500;
export const UserSocketClient = createDomainClient<UserSocketApiNotice>(
  "user",
  "/ws",
  (v): v is UserSocketApiNotice =>
    validNotice(v) &&
    object(v) &&
    (typeof v.user_kid === "string" || typeof v.user_kid === "number"),
);
