import { strict as assert } from "node:assert";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { randomUUID } from "node:crypto";
import { FixtureConfigSchema } from "../src/schemas.js";
import { FixtureError, FixtureManager, checkpointFixture, type FixtureEnvironment, type FixtureLaunchRequest } from "../src/fixtures.js";
import { PROTOCOL, type SessionDescriptor } from "../src/schemas.js";
import { writeDescriptor } from "../src/discovery.js";
import { startFakeTestingService, type FakeTestingService } from "./support/fake-engine.js";

const services: FakeTestingService[] = [];

async function fixtureSetup(): Promise<{ root: string; environment: FixtureEnvironment; packagePath: string; godotPath: string }> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "realmz-fixture-test-"));
  const packagePath = path.join(root, "test.realmz2");
  const godotPath = path.join(root, "godot.exe");
  await fs.writeFile(packagePath, "fixture-package");
  await fs.writeFile(godotPath, "fake-godot");
  return { root, packagePath, godotPath, environment: { testingHome: path.join(root, "home"), godotPath, rebuiltRoot: path.resolve(process.cwd(), "..", "..") } };
}

test("fixture config rejects malformed source and unsafe checkpoint paths", () => {
  const parsed = FixtureConfigSchema.safeParse({ protocol: "realmz-testing/1", kind: "fixture", fixtureId: "not-a-fixture", scratchRoot: "relative", discoveryRoot: "relative", build: "head", packagePath: "x.realmz2", packageSha256: "bad", source: { kind: "checkpoint", checkpointPath: "relative", checkpointSha256: "bad" } });
  assert.equal(parsed.success, false);
});

test("fixture launcher rejects relative and symlink package paths", async () => {
  const setup = await fixtureSetup();
  try {
    const manager = new FixtureManager(setup.environment, () => ({ pid: 1 }));
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: "relative.realmz2", source: { kind: "classic-starters", seed: 1, location: { mapId: "map", x: 1, y: 2 } } }), (error: unknown) => error instanceof FixtureError && error.code === "invalid_path");
    const link = path.join(setup.root, "link.realmz2");
    try { await fs.symlink(setup.packagePath, link, "file"); } catch { return; }
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: link, source: { kind: "classic-starters", seed: 1, location: { mapId: "map", x: 1, y: 2 } } }), (error: unknown) => error instanceof FixtureError && error.code === "invalid_path");
  } finally { await fs.rm(setup.root, { recursive: true, force: true }); }
});

test("fixture launch uses the canonical rendered native arguments and separate logs", async () => {
  const setup = await fixtureSetup();
  let launchRequest: FixtureLaunchRequest | undefined;
  try {
    const manager = new FixtureManager(setup.environment, (request) => { launchRequest = request; return { pid: 2 }; });
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: setup.packagePath, source: { kind: "classic-starters", seed: 1, location: { mapId: "map", x: 0, y: 32767 } } }, 10), (error: unknown) => error instanceof FixtureError && error.code === "fixture_timeout");
    assert.ok(launchRequest);
    assert.deepEqual(launchRequest.args, ["--path", setup.environment.rebuiltRoot, "--resolution", "1280x720", "--rendering-method", "mobile", "res://tools/runtime_testing_host.tscn", "--", launchRequest.configPath]);
    assert.equal(launchRequest.args.includes("--headless"), false);
    assert.notEqual(launchRequest.logPath, launchRequest.stdoutLogPath);
    assert.equal((await fs.stat(launchRequest.logPath)).isFile(), true);
    assert.equal((await fs.stat(launchRequest.stdoutLogPath)).isFile(), true);
  } finally { await fs.rm(setup.root, { recursive: true, force: true }); }
});

test("fixture source coordinates reject values outside the Classic map bound", async () => {
  const setup = await fixtureSetup();
  try {
    const manager = new FixtureManager(setup.environment, () => ({ pid: 3 }));
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: setup.packagePath, source: { kind: "classic-starters", seed: 1, location: { mapId: "map", x: -1, y: 0 } } }), (error: unknown) => error instanceof FixtureError && error.code === "invalid_source");
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: setup.packagePath, source: { kind: "classic-starters", seed: 1, location: { mapId: "map", x: 0, y: 32768 } } }), (error: unknown) => error instanceof FixtureError && error.code === "invalid_source");
  } finally { await fs.rm(setup.root, { recursive: true, force: true }); }
});

test("fixture readiness timeout retains private artifacts and does not kill the injected child", async () => {
  const setup = await fixtureSetup();
  let launched = false;
  try {
    const manager = new FixtureManager(setup.environment, (request) => { launched = request.args.includes("res://tools/runtime_testing_host.tscn") && request.args.includes("--"); return { pid: 4242 }; });
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: setup.packagePath, source: { kind: "classic-starters", seed: 7, location: { mapId: "map", x: 1, y: 2 } } }, 120), (error: unknown) => error instanceof FixtureError && error.code === "fixture_timeout" && error.fixtureRoot !== undefined);
    assert.equal(launched, true);
    const fixtureEntries = await fs.readdir(path.join(setup.environment.testingHome, "fixtures"));
    assert.equal(fixtureEntries.length, 1);
    const fixtureRoot = path.join(setup.environment.testingHome, "fixtures", fixtureEntries[0]!);
    assert.equal((await fs.stat(path.join(fixtureRoot, "fixture.json")).then(() => true).catch(() => false)), true);
    assert.equal((await fs.stat(path.join(fixtureRoot, "engine.log")).then(() => true).catch(() => false)), true);
  } finally { await fs.rm(setup.root, { recursive: true, force: true }); }
});

test("fixture cancellation retains artifacts without killing the injected child", async () => {
  const setup = await fixtureSetup();
  const controller = new AbortController();
  try {
    const manager = new FixtureManager(setup.environment, () => { controller.abort(); return { pid: 4343 }; });
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: setup.packagePath, source: { kind: "classic-starters", seed: 8, location: { mapId: "map", x: 1, y: 2 } } }, 1000, controller.signal), (error: unknown) => error instanceof FixtureError && error.code === "fixture_cancelled");
    const fixtureEntries = await fs.readdir(path.join(setup.environment.testingHome, "fixtures"));
    assert.equal(fixtureEntries.length, 1);
  } finally { await fs.rm(setup.root, { recursive: true, force: true }); }
});

test("fixture launch failures retain the scratch root and expose a bounded startup error", async () => {
  const setup = await fixtureSetup();
  try {
    const manager = new FixtureManager(setup.environment, () => { throw new Error("spawn denied"); });
    await assert.rejects(() => manager.create({ engine: "rebuilt", packagePath: setup.packagePath, source: { kind: "classic-starters", seed: 9, location: { mapId: "map", x: 1, y: 2 } } }), (error: unknown) => error instanceof FixtureError && error.code === "fixture_start_failed" && error.fixtureRoot !== undefined && error.message === "spawn denied");
    const fixtureEntries = await fs.readdir(path.join(setup.environment.testingHome, "fixtures"));
    assert.equal(fixtureEntries.length, 1);
  } finally { await fs.rm(setup.root, { recursive: true, force: true }); }
});

test("checkpoint exports use unique retained files and preserve the engine canonical hash", async () => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "realmz-checkpoint-test-"));
  const fixtureId = "0123456789abcdef0123456789abcdef";
  const fixtureRoot = path.join(home, "fixtures", fixtureId);
  await fs.mkdir(fixtureRoot, { recursive: true });
  const descriptor: SessionDescriptor = { protocol: PROTOCOL, sessionId: "checkpoint-fixture", engine: "rebuilt", build: "test-build", pid: process.pid, port: 9, token: "private-token", fixtureId, access: "fixture", capabilities: ["checkpoint"], startedAt: new Date().toISOString() };
  const service = await startFakeTestingService(descriptor, {
    describe: () => ({ ...descriptor }),
      handle: async (command) => command === "checkpoint" ? { revision: 1, result: { checkpoint: { revision: 1, state: "first" }, sha256: "canonical-engine-hash", checkpointSha256: "canonical-checkpoint-hash", mode: "observation" } } : { revision: 0, result: {} }
  }, 0);
  descriptor.port = service.port;
  services.push(service);
  try {
    await writeDescriptor(home, descriptor);
    const first = await checkpointFixture(descriptor.sessionId, home, randomUUID());
    const second = await checkpointFixture(descriptor.sessionId, home, randomUUID());
    assert.equal(first.ok, true);
    assert.equal(second.ok, true);
    assert.ok(first.result && second.result);
    assert.equal(first.result.sha256, "canonical-engine-hash");
    assert.equal(first.result.checkpointSha256, "canonical-checkpoint-hash");
    assert.notEqual(first.result.checkpointFileSha256, "canonical-checkpoint-hash");
    assert.notEqual(first.result.checkpointPath, second.result.checkpointPath);
    assert.match(String(first.result.checkpointPath), /[\\/]checkpoints[\\/][0-9a-f-]+\.r2save$/);
    assert.deepEqual(JSON.parse(await fs.readFile(String(first.result.checkpointPath), "utf8")), { revision: 1, state: "first" });
    delete descriptor.fixtureId;
    await writeDescriptor(home, descriptor);
    const live = await checkpointFixture(descriptor.sessionId, home, randomUUID());
    assert.equal(live.ok, true);
    const livePath = String(live.result?.checkpointPath);
    assert.equal(path.dirname(path.dirname(livePath)), path.join(home, "checkpoints"));
    assert.equal(path.basename(path.dirname(livePath)), descriptor.sessionId);
    assert.match(path.basename(livePath), /^[0-9a-f-]+\.r2save$/);
  } finally {
    await service.close();
    services.splice(services.indexOf(service), 1);
    await fs.rm(home, { recursive: true, force: true });
  }
});
