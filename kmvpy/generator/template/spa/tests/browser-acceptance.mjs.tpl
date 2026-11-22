/** Run against tests/realtime_fixture.py and the SPA built with the documented loopback env. */
import { createRequire } from "node:module";
import assert from "node:assert/strict";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || "playwright");
const origin = "http://127.0.0.1:18761";
const browser = await chromium.launch({
  executablePath:
    process.env.CHROME_EXECUTABLE ||
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  headless: true,
});
let checks = 0;
const wait = async (fn, label) => {
  const until = Date.now() + 18000;
  while (Date.now() < until) {
    if (await fn()) {
      checks++;
      console.log("PASS " + label);
      return;
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw Error("timeout " + label);
};
try {
  const context = await browser.newContext();
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.goto(origin);
  const stats = async () =>
    (await context.request.get(origin + "/fixture/stats")).json();
  const active = async (domain) =>
    (await stats()).active.filter((c) => !domain || c.domain === domain);
  const credentials = {};
  for (const d of ["user", "admin"])
    credentials[d] = (
      await (await context.request.post(origin + "/fixture/login/" + d)).json()
    ).authorization;
  await page.evaluate((c) => {
    for (const d of ["user", "admin"])
      localStorage.setItem("__PROJECT_NAME__-realtime-test:" + d, c[d]);
  }, credentials);
  await new Promise((r) => setTimeout(r, 300));
  assert.equal((await active()).length, 0);
  checks++;
  console.log("PASS public page has no transport");
  await page.goto(origin + "/app/work-tickets/user-work-tickets");
  await wait(
    async () => (await active("user")).length === 1,
    "user protected page connects",
  );
  const userPeer = await context.newPage();
  await userPeer.goto(origin + "/app/work-tickets/user-work-tickets");
  const admin = await context.newPage();
  await admin.goto(origin + "/admin/work-tickets");
  const adminPeer = await context.newPage();
  await adminPeer.goto(origin + "/admin/work-tickets");
  await wait(
    async () =>
      (await active("user")).length === 1 &&
      (await active("admin")).length === 1,
    "four tabs share one connection per domain",
  );
  const connections = await active();
  assert.equal(new Set(connections.map((c) => c.engine)).size, 2);
  checks++;
  console.log("PASS namespaces use independent Engine.IO transports");
  await wait(
    async () => (await active()).every((c) => c.subscriptions >= 1),
    "real subscription ACKs register intents",
  );
  const before = (await stats()).reads.user;
  await context.request.post(origin + "/fixture/notice/user");
  await wait(
    async () => (await stats()).reads.user === before + 2,
    "one broadcast yields one authoritative read per user page",
  );
  // Headless Chrome does not expose native foreground/background tab visibility.
  // Exercise the pagehide/pageshow contract in real pages; transport remains real.
  await new Promise((r) => setTimeout(r, 250));
  await userPeer.evaluate(() =>
    window.dispatchEvent(
      new PageTransitionEvent("pagehide", { persisted: true }),
    ),
  );
  await new Promise((r) => setTimeout(r, 150));
  const beforeFreeze = (await stats()).reads.user;
  await context.request.post(origin + "/fixture/notice/user");
  await new Promise((r) => setTimeout(r, 350));
  assert.equal((await stats()).reads.user, beforeFreeze + 1);
  checks++;
  console.log("PASS pagehide lifecycle pauses notification HTTP reads");
  await userPeer.evaluate(() =>
    window.dispatchEvent(
      new PageTransitionEvent("pageshow", { persisted: true }),
    ),
  );
  await wait(
    async () => (await stats()).reads.user === beforeFreeze + 2,
    "resume compensates once",
  );
  await page.close();
  await wait(
    async () => (await active("user")).length === 1,
    "owner close hands transport to eligible peer",
  );
  await userPeer.goto(origin + "/");
  await wait(
    async () => (await active("user")).length === 0,
    "leaving final protected user page allows zero user connections",
  );
  assert.equal((await active("admin")).length, 1);
  checks++;
  console.log("PASS route-domain leave preserves admin connection");
  await userPeer.goto(origin + "/app/work-tickets/user-work-tickets");
  await wait(
    async () => (await active("user")).length === 1,
    "route return restores connection",
  );
  await context.setOffline(true);
  await new Promise((r) => setTimeout(r, 600));
  // The server sees socket closure after the network is brought back; browser client must stop ownership immediately.
  await context.setOffline(false);
  await wait(
    async () =>
      (await active("user")).length === 1 &&
      (await active("admin")).length === 1,
    "offline/online restore each domain",
  );
  await context.request.post(origin + "/fixture/revoke/user");
  await context.request.post(origin + "/fixture/disconnect/user");
  await wait(
    async () => (await active("user")).length === 0,
    "revoked user session is rejected",
  );
  await wait(
    async () =>
      (await userPeer.evaluate(() =>
        localStorage.getItem("__PROJECT_NAME__-realtime-test:user"),
      )) === null,
    "structured user failure clears only user credential",
  );
  assert.equal((await active("admin")).length, 1);
  assert.equal(errors.length, 0);
  checks++;
  console.log("PASS domain failure isolation and no browser page errors");
  await context.close();
  await new Promise((r) => setTimeout(r, 300));
  // Actual constructor/send exceptions, rather than merely hiding interfaces.
  for (const mode of [
    "lock-reject",
    "broadcast-create",
    "broadcast-send",
    "broadcast-memory",
    "isolated",
  ]) {
    const c = await browser.newContext();
    const login = await (
      await c.request.post(origin + "/fixture/login/user")
    ).json();
    await c.addInitScript(
      ({ mode, token }) => {
        if (mode === "lock-reject")
          Object.defineProperty(navigator, "locks", {
            value: {
              request: () => Promise.reject(Error("synthetic lock exception")),
            },
          });
        if (mode === "broadcast-create" || mode === "isolated")
          globalThis.BroadcastChannel = class {
            constructor() {
              throw Error("synthetic channel creation");
            }
          };
        if (mode === "broadcast-send") {
          const Original = BroadcastChannel;
          globalThis.BroadcastChannel = class extends Original {
            postMessage() {
              throw Error("synthetic channel send");
            }
          };
        }
        if (mode === "broadcast-memory" || mode === "isolated") {
          Storage.prototype.getItem = function (key) {
            if (key === "__PROJECT_NAME__-realtime-test:user") return token;
            throw Error("synthetic read");
          };
          Storage.prototype.setItem = function () {
            throw Error("synthetic write");
          };
          Storage.prototype.removeItem = function () {
            throw Error("synthetic remove");
          };
        }
      },
      { mode, token: login.authorization },
    );
    const p = await c.newPage();
    await p.goto(origin);
    if (mode !== "broadcast-memory" && mode !== "isolated")
      await p.evaluate(
        (token) => localStorage.setItem("__PROJECT_NAME__-realtime-test:user", token),
        login.authorization,
      );
    await p.goto(origin + "/app/work-tickets/user-work-tickets");
    const q = await c.newPage();
    await q.goto(origin + "/app/work-tickets/user-work-tickets");
    await wait(
      async () =>
        (
          await (await c.request.get(origin + "/fixture/stats")).json()
        ).active.filter((s) => s.domain === "user").length ===
        (mode === "isolated" ? 2 : 1),
      "browser exception fallback " + mode,
    );
    await c.close();
    await new Promise((r) => setTimeout(r, 350));
  }
  console.log(
    JSON.stringify({
      checks,
      result: "passed",
      kind: "synthetic localhost, real Chromium + Socket.IO + Redis",
    }),
  );
} finally {
  await browser.close();
}
