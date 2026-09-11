import { strict as assert } from "node:assert";
import { promises as fs } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import { Client } from "@modelcontextprotocol/client";
import { StdioClientTransport } from "@modelcontextprotocol/client/stdio";

type ToolReply = {
  protocol?: string;
  sessionId?: string;
  requestId?: string;
  revision?: number;
  ok?: boolean;
  result?: Record<string, unknown> | null;
  error?: { code: string; message: string } | null;
};

type FixtureHandle = {
  fixtureId: string;
  fixtureRoot: string;
  configPath: string;
  descriptor: { sessionId: string; fixtureId?: string; capabilities: string[]; access: string };
};

const runRenderedE2E = process.env.REALMZ_TESTING_RENDERED_E2E === "1";
const packageRoot = path.resolve(process.cwd());
const repoRoot = path.resolve(packageRoot, "../..");
const packagePath = path.join(repoRoot, "tests", "fixtures", "packages", "realmz2-synthetic-fixture.realmz2");

function textResult(value: unknown): string {
  assert.ok(value && typeof value === "object", "MCP returned no result object");
  const content = (value as { content?: unknown }).content;
  assert.ok(Array.isArray(content), "MCP result has no content array");
  const text = content.find((entry) => entry && typeof entry === "object" && (entry as { type?: unknown }).type === "text") as { text?: unknown } | undefined;
  assert.equal(typeof text?.text, "string", "MCP result has no text content");
  return text!.text as string;
}

async function tool(client: Client, name: string, args: Record<string, unknown>): Promise<ToolReply | Record<string, unknown> | Array<unknown>> {
  const response = await client.callTool({ name, arguments: args });
  return JSON.parse(textResult(response)) as ToolReply | Record<string, unknown> | Array<unknown>;
}

function reply(value: ToolReply | Record<string, unknown> | Array<unknown>, label: string): ToolReply {
  assert.ok(value && !Array.isArray(value) && typeof value === "object", `${label} returned a non-object result`);
  assert.equal((value as ToolReply).protocol, "realmz-testing/1", `${label} returned the wrong protocol`);
  return value as ToolReply;
}

function successfulResult(value: ToolReply, label: string): Record<string, unknown> {
  assert.equal(value.ok, true, `${label} failed: ${value.error?.code ?? "unknown"}: ${value.error?.message ?? ""}`);
  assert.ok(value.result && typeof value.result === "object" && !Array.isArray(value.result), `${label} has no result object`);
  return value.result;
}

function sessionId(handle: FixtureHandle): string {
  assert.ok(handle.descriptor?.sessionId, "fixture descriptor has no session ID");
  return handle.descriptor.sessionId;
}

function currentRevision(value: ToolReply, label: string): number {
  assert.ok(Number.isSafeInteger(value.revision), `${label} has no safe revision`);
  return value.revision as number;
}

function pending(result: Record<string, unknown>): Record<string, unknown> | null {
  const value = result.pendingInteraction;
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function pendingRequest(value: Record<string, unknown>): { requestId: string; kind: string } {
  const data = value.data;
  assert.ok(data && typeof data === "object" && !Array.isArray(data), "pending interaction has no data object");
  const requestId = (data as Record<string, unknown>).requestId;
  const kind = value.kind;
  assert.equal(typeof requestId, "string", "pending interaction has no request ID");
  assert.equal(typeof kind, "string", "pending interaction has no kind");
  return { requestId: requestId as string, kind: kind as string };
}

function responseBody(kind: string, interaction: Record<string, unknown> = {}): Record<string, unknown> {
  switch (kind) {
    case "acknowledge": return {};
    case "encounter_choice": return { index: 0 };
    case "complex_encounter": {
      const data = interaction.data;
      const payload = data && typeof data === "object" && !Array.isArray(data)
        ? (data as Record<string, unknown>).payload
        : null;
      const selectionCount = payload && typeof payload === "object" && !Array.isArray(payload)
        ? Number((payload as Record<string, unknown>).actionSelectionCount ?? 0)
        : 0;
      const slots = Array.from({ length: Number.isSafeInteger(selectionCount) && selectionCount > 0 ? selectionCount : 0 }, (_, index) => index);
      return slots.length === 0 ? { action: "choice" } : { action: "choice", slots };
    }
    case "thief_encounter": return { action: "back" };
    case "pick_lock": return { frameIndex: 0 };
    default: throw new Error(`rendered fixture test does not know how to answer ${kind}`);
  }
}

async function observe(client: Client, id: string): Promise<ToolReply> {
  return reply(await tool(client, "realmz_observe", { sessionId: id, params: { diagnostics: "complete" } }), "observe");
}

async function invoke(client: Client, id: string, revision: number, target: Record<string, unknown>, requestId: string): Promise<ToolReply> {
  return reply(await tool(client, "realmz_invoke", { sessionId: id, params: { target }, expectedRevision: revision, requestId }), "invoke");
}

async function answerPending(client: Client, id: string, invocation: ToolReply, label: string): Promise<ToolReply> {
  let latest = invocation;
  for (let count = 0; count < 8; count += 1) {
    const result = successfulResult(latest, `${label} response`);
    const interaction = pending(result.observation as Record<string, unknown>);
    if (interaction === null) return latest;
    const identity = pendingRequest(interaction);
    const response = await tool(client, "realmz_respond", {
      sessionId: id,
      params: { response: { requestId: identity.requestId, kind: identity.kind, body: responseBody(identity.kind, interaction) } },
      expectedRevision: currentRevision(latest, `${label} pending`),
      requestId: `${label}-respond-${count}`
    });
    latest = reply(response, `${label} respond`);
    if (latest.ok !== true) return latest;
  }
  throw new Error(`${label} did not settle after eight typed responses`);
}

test("rendered MCP fixture lifecycle and typed continuations", { skip: !runRenderedE2E, timeout: 180_000 }, async () => {
  const godotPath = process.env.REALMZ_GODOT_PATH;
  const rebuiltRoot = process.env.REALMZ_REBUILT_ROOT;
  const testingHome = process.env.REALMZ_TESTING_HOME;
  assert.ok(godotPath && path.isAbsolute(godotPath), "REALMZ_GODOT_PATH must be an absolute native Godot executable path");
  assert.ok(rebuiltRoot && path.resolve(rebuiltRoot) === repoRoot, "REALMZ_REBUILT_ROOT must point at this checkout");
  assert.ok(testingHome && path.isAbsolute(testingHome), "REALMZ_TESTING_HOME must be an absolute designated testing home");
  await fs.access(godotPath);
  await fs.access(packagePath);
  await fs.access(path.join(repoRoot, "tools", "runtime_testing", "dist", "mcp.js"));

  const childEnv: Record<string, string> = {};
  for (const [key, value] of Object.entries(process.env)) if (value !== undefined) childEnv[key] = value;
  childEnv.REALMZ_GODOT_PATH = godotPath;
  childEnv.REALMZ_REBUILT_ROOT = path.resolve(rebuiltRoot);
  childEnv.REALMZ_TESTING_HOME = path.resolve(testingHome);
  const transport = new StdioClientTransport({ command: process.execPath, args: [path.join(packageRoot, "dist", "mcp.js")], cwd: packageRoot, env: childEnv });
  const client = new Client({ name: "realmz-rendered-fixture-e2e", version: "0.1.0" });
  const created: Array<{ id: string; revision: number }> = [];
  try {
    await client.connect(transport);
    const listed = await client.listTools();
    const names = new Set(listed.tools.map((entry) => entry.name));
    for (const name of ["realmz_fixture", "realmz_observe", "realmz_invoke", "realmz_respond", "realmz_capture"]) assert.ok(names.has(name), `tools/list omitted ${name}`);

    const createdRaw = await tool(client, "realmz_fixture", {
      operation: "create", engine: "rebuilt", packagePath,
      source: { kind: "classic-starters", seed: 37, location: { mapId: "land:0", x: 1, y: 1 } }
    });
    assert.ok(createdRaw && !Array.isArray(createdRaw) && typeof createdRaw === "object", "fixture create returned no handle");
    const fixture = createdRaw as unknown as FixtureHandle;
    const id = sessionId(fixture);
    created.push({ id, revision: 0 });
    assert.equal(fixture.descriptor.access, "fixture");
    assert.equal(fixture.descriptor.fixtureId, fixture.fixtureId);
    assert.deepEqual(fixture.descriptor.capabilities.sort(), ["act", "capture", "checkpoint", "close", "describe", "invoke", "observe", "respond", "restore", "ui"]);

    let observed = await observe(client, id);
    let revision = currentRevision(observed, "initial observation");
    const checkpointReply = reply(await tool(client, "realmz_fixture", { operation: "checkpoint", sessionId: id }), "checkpoint");
    const checkpointResult = successfulResult(checkpointReply, "checkpoint");
    const checkpoint = checkpointResult.checkpoint;
    assert.ok(checkpoint && typeof checkpoint === "object" && !Array.isArray(checkpoint));
    const checkpointPath = checkpointResult.checkpointPath;
    assert.equal(typeof checkpointPath, "string");
    await fs.access(checkpointPath as string);

    const xap = await invoke(client, id, revision, { kind: "extra-action-point-program", id: 0 }, "rendered-xap-0");
    const xapObservation = successfulResult(xap, "standalone XAP").observation as Record<string, unknown>;
    const xapPending = pending(xapObservation);
    assert.equal(xapPending?.kind, "acknowledge", "standalone XAP did not expose its acknowledgement continuation");
    const unavailable = reply(await tool(client, "realmz_fixture", { operation: "checkpoint", sessionId: id }), "pending checkpoint");
    assert.equal(unavailable.ok, false);
    assert.equal(unavailable.error?.code, "snapshot_unavailable");
    const settledXap = await answerPending(client, id, xap, "xap");
    assert.equal(settledXap.ok, true, "standalone XAP continuation failed");

    observed = await observe(client, id);
    revision = currentRevision(observed, "post-XAP observation");
    const stale = reply(await tool(client, "realmz_fixture", { operation: "restore", sessionId: id, checkpoint, expectedRevision: revision - 1, requestId: "rendered-stale-restore" }), "stale restore");
    assert.equal(stale.ok, false);
    assert.equal(stale.error?.code, "stale_revision");
    assert.equal(currentRevision(stale, "stale restore"), revision, "stale restore changed the monotonic revision");
    const restored = reply(await tool(client, "realmz_fixture", { operation: "restore", sessionId: id, checkpoint, expectedRevision: revision, requestId: "rendered-restore" }), "restore");
    assert.equal(restored.ok, true);
    revision = currentRevision(restored, "restore");

    const cloneRaw = await tool(client, "realmz_fixture", { operation: "clone", engine: "rebuilt", packagePath, checkpointPath });
    assert.ok(cloneRaw && !Array.isArray(cloneRaw) && typeof cloneRaw === "object", "fixture clone returned no handle");
    const clone = cloneRaw as unknown as FixtureHandle;
    const cloneId = sessionId(clone);
    created.push({ id: cloneId, revision: 0 });
    assert.notEqual(clone.fixtureId, fixture.fixtureId, "clone reused the source fixture identity");
    const cloneObservation = await observe(client, cloneId);
    const cloneRestore = reply(await tool(client, "realmz_fixture", { operation: "restore", sessionId: cloneId, checkpoint, expectedRevision: currentRevision(cloneObservation, "clone observation"), requestId: "clone-restore" }), "clone restore");
    assert.equal(cloneRestore.ok, true);
    created[1]!.revision = currentRevision(cloneRestore, "clone restore");

    const invalid = await invoke(client, id, revision, { kind: "not-a-supported-target", id: 0 }, "invalid-target");
    assert.equal(invalid.ok, false);
    assert.equal(invalid.error?.code, "unsupported_target");
    assert.equal(currentRevision(invalid, "invalid target"), revision);
    const ownerMismatch = await invoke(client, id, revision, { kind: "thief-encounter", id: 0, ownerId: 9999 }, "invalid-owner");
    assert.equal(ownerMismatch.ok, false);
    assert.equal(ownerMismatch.error?.code, "target_owner_mismatch");
    assert.equal(currentRevision(ownerMismatch, "owner mismatch"), revision);

    observed = await observe(client, id);
    revision = currentRevision(observed, "before simple encounter");
    const simple = await invoke(client, id, revision, { kind: "simple-encounter", id: 0 }, "simple-encounter");
    assert.equal(pending(successfulResult(simple, "simple encounter").observation as Record<string, unknown>)?.kind, "encounter_choice");
    const simpleDone = await answerPending(client, id, simple, "simple");
    assert.equal(simpleDone.ok, true, "simple encounter continuation failed");

    observed = await observe(client, id);
    revision = currentRevision(observed, "before complex encounter");
    const complex = await invoke(client, id, revision, { kind: "complex-encounter", id: 0 }, "complex-encounter");
    assert.equal(pending(successfulResult(complex, "complex encounter").observation as Record<string, unknown>)?.kind, "complex_encounter");
    const complexDone = await answerPending(client, id, complex, "complex");
    assert.equal(complexDone.ok, true, "complex encounter continuation failed");

    observed = await observe(client, id);
    revision = currentRevision(observed, "before owner-bound thief encounter");
    const thief = await invoke(client, id, revision, { kind: "thief-encounter", id: 0, ownerId: 0 }, "owner-bound-thief");
    assert.equal(pending(successfulResult(thief, "owner-bound thief encounter").observation as Record<string, unknown>)?.kind, "thief_encounter");
    const thiefDone = await answerPending(client, id, thief, "thief");
    assert.equal(thiefDone.ok, true, "owner-bound thief continuation failed");

    observed = await observe(client, id);
    const capture = reply(await tool(client, "realmz_capture", { sessionId: id, requestId: "rendered-capture" }), "capture");
    const captureResult = successfulResult(capture, "capture");
    assert.equal(captureResult.mode, "rendered-observation");
    assert.equal(captureResult.width, 1280);
    assert.equal(captureResult.height, 720);
    assert.ok(typeof captureResult.path === "string" && path.resolve(captureResult.path).startsWith(path.resolve(fixture.fixtureRoot) + path.sep));
    assert.ok(Number(captureResult.bytes) > 0);
    assert.equal((await fs.stat(captureResult.path as string)).isFile(), true);
    assert.equal(pending(successfulResult(observed, "final observation")), null, "fixture ended with an unexpected pending interaction");
  } finally {
    for (const entry of created.slice().reverse()) {
      try {
        const current = await observe(client, entry.id);
        if (current.ok === true) {
          const closed = reply(await tool(client, "realmz_fixture", { operation: "close", sessionId: entry.id, expectedRevision: currentRevision(current, "close observation"), requestId: `close-${entry.id}` }), "fixture close");
          assert.equal(closed.ok, true, `created fixture ${entry.id} did not close cleanly`);
        }
      } catch {
        // Preserve the original assertion or native startup error; scratch evidence remains for diagnosis.
      }
    }
    await client.close().catch(() => undefined);
  }
});
