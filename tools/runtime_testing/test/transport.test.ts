import { strict as assert } from "node:assert";
import { promises as fs } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { test, afterEach } from "node:test";
import { randomUUID } from "node:crypto";
import { discoverSessions, discoverSession, writeDescriptor, type SessionDescriptor } from "../src/discovery.js";
import { sendRequest, ProtocolError } from "../src/transport.js";
import { PROTOCOL, type TestingRequest } from "../src/schemas.js";
import { startFakeTestingService, type FakeTestingService } from "./support/fake-engine.js";
import { requestSession } from "../src/client.js";

const services: FakeTestingService[] = [];
const homes: string[] = [];

afterEach(async () => {
  await Promise.all(services.splice(0).map((service) => service.close()));
  await Promise.all(homes.splice(0).map((home) => fs.rm(home, { recursive: true, force: true })));
});

async function freePort(): Promise<number> {
  const server = net.createServer();
  await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen({ host: "127.0.0.1", port: 0 }, () => resolve()); });
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const port = address.port;
  await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
  return port;
}

async function setup(access: "observe" | "fixture" = "fixture") {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "realmz-testing-"));
  homes.push(home);
  const sessionId = "test-session";
  const token = "private-test-token";
  const port = await freePort();
  let handled = 0;
  const descriptor: SessionDescriptor = { protocol: PROTOCOL, sessionId, engine: "rebuilt", build: "test-build", pid: process.pid, port, token, access, capabilities: ["observe", "checkpoint"], startedAt: new Date().toISOString() };
  const service = await startFakeTestingService(descriptor, {
    describe: () => ({ protocol: PROTOCOL, sessionId, engine: "rebuilt", build: "test-build", pid: descriptor.pid, port: descriptor.port, access, capabilities: ["observe", "checkpoint"], startedAt: descriptor.startedAt }),
    handle: async (command, params) => { handled += 1; return { revision: command === "checkpoint" ? 1 : 0, result: { command, params, handled, secret: { token: "not-public" } } }; }
  }, port);
  services.push(service);
  await writeDescriptor(home, descriptor);
  return { home, descriptor, getHandled: () => handled };
}

function request(descriptor: SessionDescriptor, command: string, requestId = randomUUID(), token = descriptor.token, expectedRevision: number | null = null): TestingRequest {
  return { protocol: PROTOCOL, sessionId: descriptor.sessionId, token, requestId, expectedRevision, command, params: {} };
}

test("discovers only live sessions and never exposes descriptor tokens", async () => {
  const { home, descriptor } = await setup();
  const stale: SessionDescriptor = { ...descriptor, sessionId: "stale", port: await freePort(), token: "stale-token" };
  await writeDescriptor(home, stale);
  const sessions = await discoverSessions(home);
  assert.equal(sessions.length, 1);
  assert.equal(sessions[0]?.sessionId, descriptor.sessionId);
  assert.equal("token" in (sessions[0] ?? {}), false);
  await assert.rejects(() => discoverSession("stale", home), /stale|missing/);
});

test("rejects authentication failures and cross-session requests", async () => {
  const { descriptor } = await setup();
  const bad = await sendRequest(descriptor.port, request(descriptor, "observe", "bad-token-id", "wrong"));
  assert.equal(bad.ok, false);
  assert.equal(bad.error?.code, "unauthorized");
  const cross = await sendRequest(descriptor.port, { ...request(descriptor, "observe", "cross-session"), sessionId: "other-session" });
  assert.equal(cross.ok, false);
  assert.equal(cross.error?.code, "unauthorized");
});

test("deduplicates an exact requestId but rejects reuse for another request", async () => {
  const { descriptor, getHandled } = await setup();
  const first = await sendRequest(descriptor.port, request(descriptor, "observe", "same-id"));
  assert.equal(JSON.stringify(first).includes("not-public"), false);
  const second = await sendRequest(descriptor.port, request(descriptor, "observe", "same-id"));
  assert.deepEqual(second, first);
  assert.equal(getHandled(), 1);
  const different = await sendRequest(descriptor.port, request(descriptor, "checkpoint", "same-id"));
  assert.equal(different.error?.code, "request_id_conflict");
});

test("rejects observe-service mutation and requires revision for fixture mutation", async () => {
  const observed = await setup("observe");
  await assert.rejects(() => requestSession(observed.descriptor.sessionId, "restore", {}, 0, "client-gate", observed.home), /observe sessions reject mutating commands/);
  const denied = await sendRequest(observed.descriptor.port, request(observed.descriptor, "restore", "restore-observe", observed.descriptor.token, 0));
  assert.equal(denied.error?.code, "access_denied");
  const fixture = await setup("fixture");
  const missing = await sendRequest(fixture.descriptor.port, request(fixture.descriptor, "restore", "restore-missing"));
  assert.equal(missing.error?.code, "expected_revision_required");
  const stale = await sendRequest(fixture.descriptor.port, request(fixture.descriptor, "restore", "restore-stale", fixture.descriptor.token, 3));
  assert.equal(stale.error?.code, "revision_conflict");
});

test("reports malformed replies and disconnected peers without retrying", async () => {
  const peerSockets: net.Socket[] = [];
  const malformed = net.createServer((socket) => { peerSockets.push(socket); socket.write("not-json\n"); socket.end(); });
  await new Promise<void>((resolve, reject) => { malformed.once("error", reject); malformed.listen({ host: "127.0.0.1", port: 0 }, () => resolve()); });
  const address = malformed.address();
  assert.ok(address && typeof address !== "string");
  const descriptor: SessionDescriptor = { protocol: PROTOCOL, sessionId: "peer", engine: "rebuilt", build: "test", pid: 1, port: address.port, token: "token", access: "fixture", capabilities: [], startedAt: new Date().toISOString() };
  await assert.rejects(() => sendRequest(descriptor.port, request(descriptor, "observe")), (error: unknown) => error instanceof ProtocolError && error.code === "malformed_reply");
  for (const socket of peerSockets) socket.destroy();
  await new Promise<void>((resolve, reject) => malformed.close((error) => error ? reject(error) : resolve()));
  await assert.rejects(() => sendRequest(descriptor.port, request(descriptor, "observe")), (error: unknown) => error instanceof ProtocolError && error.code === "disconnected");
});
