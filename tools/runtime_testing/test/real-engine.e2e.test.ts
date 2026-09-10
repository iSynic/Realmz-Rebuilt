import { strict as assert } from "node:assert";
import { once } from "node:events";
import { spawn, type ChildProcessWithoutNullStreams } from "node:child_process";
import { fileURLToPath } from "node:url";
import net from "node:net";
import { test } from "node:test";
import { discoverSession, testingHome } from "../src/discovery.js";
import { PROTOCOL, ReplySchema, type TestingRequest, type TestingReply } from "../src/schemas.js";
import { requestSession, sendRequest } from "../src/index.js";

const sessionId = process.env.REALMZ_TESTING_E2E_SESSION;
const skip = !sessionId;

async function rawExchange(port: number, payload: string): Promise<unknown> {
  const socket = new net.Socket();
  try {
    return await new Promise<unknown>((resolve, reject) => {
      let buffer = Buffer.alloc(0);
      let complete = false;
      const timer = setTimeout(() => { socket.destroy(); reject(new Error("raw engine exchange timed out")); }, 3000);
      const fail = (error: Error) => { if (!complete) { complete = true; clearTimeout(timer); reject(error); } };
      socket.once("connect", () => socket.write(`${payload}\n`));
      socket.on("data", (chunk: Buffer) => {
        if (complete) return;
        buffer = Buffer.concat([buffer, chunk]);
        const index = buffer.indexOf(0x0a);
        if (index < 0) return;
        if (buffer.byteLength !== index + 1) { fail(new Error("raw engine exchange returned trailing data")); return; }
        try { complete = true; clearTimeout(timer); resolve(JSON.parse(buffer.subarray(0, index).toString("utf8"))); }
        catch (error) { fail(error instanceof Error ? error : new Error("raw engine exchange returned malformed JSON")); }
      });
      socket.once("error", (error) => fail(error));
      socket.once("close", () => fail(new Error("raw engine disconnected before replying")));
      socket.connect({ host: "127.0.0.1", port });
    });
  } finally { socket.destroy(); }
}

class LineReader {
  private buffer = Buffer.alloc(0);
  private waiting: { resolve: (line: string) => void; reject: (error: Error) => void } | null = null;
  private failure: Error | null = null;
  constructor(private readonly stream: NodeJS.ReadableStream) {
    stream.on("data", (chunk: Buffer | string) => {
      this.buffer = Buffer.concat([this.buffer, Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)]);
      this.flush();
    });
    stream.on("error", (error: Error) => {
      this.failure = error;
      const waiting = this.waiting;
      this.waiting = null;
      waiting?.reject(error);
    });
  }
  private flush(): void {
    if (!this.waiting) return;
    const index = this.buffer.indexOf(0x0a);
    if (index < 0) return;
    const resolve = this.waiting.resolve;
    this.waiting = null;
    const line = this.buffer.subarray(0, index);
    this.buffer = this.buffer.subarray(index + 1);
    resolve(line.toString("utf8"));
  }
  async next(timeoutMs = 3000): Promise<string> {
    if (this.failure) throw this.failure;
    const index = this.buffer.indexOf(0x0a);
    if (index >= 0) {
      const line = this.buffer.subarray(0, index);
      this.buffer = this.buffer.subarray(index + 1);
      return line.toString("utf8");
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.waiting = null; reject(new Error("MCP stdio response timed out")); }, timeoutMs);
      this.waiting = { resolve: (line) => { clearTimeout(timer); resolve(line); }, reject: (error) => { clearTimeout(timer); reject(error); } };
    });
  }
}

async function mcpCall(child: ChildProcessWithoutNullStreams, reader: LineReader, id: number, method: string, params?: Record<string, unknown>): Promise<Record<string, unknown>> {
  child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", id, method, ...(params === undefined ? {} : { params }) })}\n`);
  return JSON.parse(await reader.next()) as Record<string, unknown>;
}

test("real engine transport proof (opt-in)", { skip }, async () => {
  const descriptor = await discoverSession(sessionId!, testingHome());
  const described = await requestSession(descriptor.sessionId, "describe", {}, null, "e2e-describe", testingHome());
  assert.equal(described.ok, true);
  assert.equal(described.result?.sessionId, descriptor.sessionId);
  assert.equal("token" in (described.result ?? {}), false);
  const observed = await requestSession(descriptor.sessionId, "observe", {}, null, "e2e-observe", testingHome());
  assert.equal(observed.ok, true);
  assert.equal("token" in (observed.result ?? {}), false);

  const base: TestingRequest = { protocol: PROTOCOL, sessionId: descriptor.sessionId, token: descriptor.token, requestId: "e2e-replay", expectedRevision: null, command: "observe", params: {} };
  const first = await sendRequest(descriptor.port, base);
  const second = await sendRequest(descriptor.port, base);
  assert.deepEqual(second, first);
  const staleRead = await sendRequest(descriptor.port, { ...base, requestId: "e2e-stale-read", expectedRevision: first.revision + 1 });
  assert.equal(staleRead.ok, false);
  assert.ok(["stale_revision", "revision_conflict", "expected_revision"].includes(staleRead.error?.code ?? ""));
  const conflict = await sendRequest(descriptor.port, { ...base, requestId: "e2e-replay", params: { changed: true } });
  assert.equal(conflict.error?.code, "request_id_conflict");
  const fractional = { ...base, requestId: "e2e-fractional-replay", params: { value: 1 / 3 } };
  const fractionalFirst = await sendRequest(descriptor.port, fractional);
  assert.deepEqual(await sendRequest(descriptor.port, fractional), fractionalFirst);
  const fractionalConflict = await sendRequest(descriptor.port, { ...fractional, params: { value: 0.333333333333333 } });
  assert.equal(fractionalConflict.error?.code, "request_id_conflict");
  const mutation = await sendRequest(descriptor.port, { ...base, requestId: "e2e-rejected-mutation", command: "restore", expectedRevision: first.revision });
  assert.equal(mutation.ok, false);
  assert.ok(["access_denied", "live_read_only"].includes(mutation.error?.code ?? ""));
  await assert.rejects(() => requestSession(descriptor.sessionId, "restore", {}, first.revision, "e2e-client-mutation", testingHome()), /observe sessions reject mutating commands/);

  const unauthorized = await sendRequest(descriptor.port, { ...base, requestId: "e2e-auth", token: "invalid" });
  assert.equal(unauthorized.error?.code, "unauthorized");
  const version = await rawExchange(descriptor.port, JSON.stringify({ ...base, requestId: "e2e-version", protocol: "realmz-testing/999" }));
  assert.ok(["invalid_request", "protocol_version"].includes((version as { error?: { code?: string } }).error?.code ?? ""));
  const malformed = await rawExchange(descriptor.port, "not-json");
  assert.ok(["malformed_request", "invalid_request"].includes((malformed as { error?: { code?: string } }).error?.code ?? ""));
  const cross = await rawExchange(descriptor.port, JSON.stringify({ ...base, requestId: "e2e-cross", sessionId: "other-session" }));
  assert.ok(["unauthorized", "cross_session", "session_mismatch"].includes((cross as { error?: { code?: string } }).error?.code ?? ""));
  await assert.rejects(() => requestSession("stale-session", "observe", {}, null, "e2e-stale", testingHome()), /missing|stale|authentication/);

  const child = spawn(process.execPath, ["dist/mcp.js"], { cwd: fileURLToPath(new URL("..", import.meta.url)), env: { ...process.env, REALMZ_TESTING_HOME: testingHome() }, stdio: "pipe" });
  let stderrBytes = 0;
  const stderrLimit = 64 * 1024;
  child.stderr.on("data", (chunk: Buffer | string) => { stderrBytes = Math.min(stderrLimit, stderrBytes + Buffer.byteLength(chunk)); });
  const reader = new LineReader(child.stdout);
  try {
    const initialized = await mcpCall(child, reader, 1, "initialize", { protocolVersion: "2025-11-25", capabilities: {}, clientInfo: { name: "realmz-runtime-testing-e2e", version: "0.1.0" } });
    assert.ok(initialized.result);
    child.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" })}\n`);
    const listed = await mcpCall(child, reader, 2, "tools/list");
    const tools = (listed.result as { tools?: Array<{ name?: string }> }).tools ?? [];
    assert.ok(tools.some((tool) => tool.name === "realmz_observe"));
    const called = await mcpCall(child, reader, 3, "tools/call", { name: "realmz_observe", arguments: { sessionId: descriptor.sessionId, params: {}, requestId: "e2e-mcp-observe" } });
    const content = (called.result as { content?: Array<{ text?: string }> }).content?.[0]?.text;
    assert.ok(content);
    const mcpReply = ReplySchema.parse(JSON.parse(content!));
    assert.equal(mcpReply.ok, true);
    assert.equal(JSON.stringify(called).includes(descriptor.token), false);
  } finally {
    if (child.exitCode === null && !child.killed) child.kill();
    if (child.exitCode === null) await Promise.race([once(child, "close"), new Promise((resolve) => setTimeout(resolve, 1000))]);
    assert.ok(stderrBytes <= stderrLimit);
  }
});
