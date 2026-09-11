import { strict as assert } from "node:assert";
import { promises as fs } from "node:fs";
import os from "node:os";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { afterEach, test } from "node:test";
import { startFakeTestingService, type FakeTestingService } from "./support/fake-engine.js";
import { writeDescriptor, type SessionDescriptor } from "../src/discovery.js";
import { runJourneyJob } from "../src/journeys.js";
import { compareJourneyRuns } from "../src/comparison.js";
import { JourneySpecSchema, JourneyStatusSchema, PROTOCOL } from "../src/schemas.js";

const services: FakeTestingService[] = [];
const homes: string[] = [];

afterEach(async () => {
  await Promise.all(services.splice(0).map((service) => service.close()));
  await Promise.all(homes.splice(0).map((home) => fs.rm(home, { recursive: true, force: true })));
});

function observation(options: { pending?: Record<string, unknown> | null; controls?: Array<Record<string, unknown>>; traceLimitReached?: boolean; drawIndex?: number; visualReady?: boolean; semanticReady?: boolean; ready?: boolean; failure?: Record<string, unknown> | null } = {}): Record<string, unknown> {
  return {
    campaignId: "fixture-campaign",
    packageHash: "package-hash",
    rulesVersion: "realmz-classic-1",
    sessionStarted: true,
    location: { mapId: "land:0", x: 1, y: 2 },
    clock: { day: 1, hour: 2, minute: 3 },
    fatigue: 0,
    pooledGold: 10,
    party: [],
    checkpointState: { rng: { generatorState: 1, drawCount: 0 }, gameState: { party: { characters: [] } } },
    pendingInteraction: options.pending ?? null,
    actions: [],
    controls: options.controls ?? [],
    readiness: { fixtureReady: options.ready ?? true, fixtureError: null, combatPlayback: false, hostInteraction: false, explorationInput: true, visualReady: options.visualReady ?? true, ...(options.semanticReady === undefined ? {} : { semanticReady: options.semanticReady }) },
    rngTrace: options.drawIndex === undefined ? [] : [{ drawIndex: options.drawIndex, tag: "test", range: 1, raw: 1, result: 1 }],
    scenarioTrace: [],
    traceLimitReached: options.traceLimitReached ?? false,
    ...(options.failure === undefined ? {} : { failure: options.failure })
  };
}

async function setupFakeSession(options: { pending?: Record<string, unknown> | null; controls?: Array<Record<string, unknown>>; traceLimitReached?: boolean; drawIndex?: number; captureBytes?: number; semanticReady?: boolean; semanticReadySequence?: boolean[]; failedCommand?: string; ready?: boolean; executionFailure?: Record<string, unknown> } = {}) {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "realmz-journey-test-"));
  homes.push(home);
  const sessionId = `journey-${randomBytes(4).toString("hex")}`;
  const descriptor: SessionDescriptor = { protocol: PROTOCOL, sessionId, engine: "rebuilt", build: "test-build", pid: process.pid, port: 9, token: "journey-token", fixtureId: randomBytes(16).toString("hex"), access: "fixture", capabilities: ["checkpoint", "observe", "act", "respond", "ui", "invoke", "capture"], startedAt: new Date().toISOString() };
  let actions = 0;
  let observations = 0;
  const service = await startFakeTestingService(descriptor, {
    describe: () => ({ ...descriptor }),
    handle: async (command) => {
      if (command === "checkpoint") return { revision: 0, result: { checkpoint: { format: "realmz2-save", formatVersion: 4, rng: { generatorState: 1, drawCount: 0 }, gameState: { party: { characters: [] } } }, sha256: "canonical-checkpoint", mode: "observation" } };
      if (command === "observe") {
        const semanticReady = options.semanticReadySequence?.[Math.min(observations++, options.semanticReadySequence.length - 1)] ?? options.semanticReady;
        const failure = actions > 0 ? options.executionFailure ?? undefined : undefined;
        return { revision: actions, result: observation({ ...options, failure, semanticReady, drawIndex: options.drawIndex === undefined ? undefined : options.drawIndex + actions }) };
      }
      if (command === "capture") return { revision: actions, result: { mode: "rendered-observation", path: "C:/private/capture.png", sha256: "capture-hash", bytes: options.captureBytes ?? 64, width: 1280, height: 720 } };
      if (command === options.failedCommand) throw new Error("mock command failure after request acceptance");
      actions += 1;
      return { revision: actions, result: { mode: command, state: "committed", events: [], observation: observation({ ...options, failure: options.executionFailure ?? undefined, drawIndex: options.drawIndex === undefined ? undefined : options.drawIndex + actions }) } };
    }
  }, 0);
  descriptor.port = service.port;
  services.push(service);
  await writeDescriptor(home, descriptor);
  return { home, descriptor };
}

async function makeJob(home: string, sessionId: string, specInput: unknown, cancelled = false): Promise<{ id: string; statusPath: string; evidencePath: string }> {
  const spec = JourneySpecSchema.parse(specInput);
  const id = randomBytes(16).toString("hex");
  const root = path.join(home, "jobs", id);
  await fs.mkdir(root, { recursive: true });
  const statusPath = path.join(root, "status.json");
  const evidencePath = path.join(root, "evidence.json");
  const status = JourneyStatusSchema.parse({ jobId: id, name: spec.name, sessionId, state: "queued", specPath: path.join(root, "spec.json"), statusPath, evidencePath, baselineCheckpointPath: null, startedAt: null, finishedAt: null, counts: { steps: 0, actions: 0, captures: 0, evidenceBytes: 0 }, failure: null });
  await fs.writeFile(path.join(root, "spec.json"), JSON.stringify(spec));
  await fs.writeFile(statusPath, JSON.stringify(status));
  if (cancelled) await fs.writeFile(path.join(root, "cancel"), "cancel\n");
  return { id, statusPath, evidencePath };
}

const actStep = { command: "act", params: { action: "search", arguments: {} }, expect: { interactionKind: null }, capture: false } as const;

test("journey records a successful action and deterministic comparison", async () => {
  const first = await setupFakeSession();
  const firstJob = await makeJob(first.home, first.descriptor.sessionId, { name: "deterministic", sessionId: first.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(firstJob.id, first.home);
  const firstStatus = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(firstJob.statusPath, "utf8")));
  assert.equal(firstStatus.state, "completed");
  assert.equal(firstStatus.counts.actions, 1);
  const second = await setupFakeSession();
  const secondJob = await makeJob(second.home, second.descriptor.sessionId, { name: "deterministic", sessionId: second.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(secondJob.id, second.home);
  const comparison = await compareJourneyRuns(firstJob.evidencePath, secondJob.evidencePath);
  assert.equal(comparison.initialEquivalenceVerified, true);
  assert.equal(comparison.equal, true);
});

test("journey waits for an asynchronously queued command to become semantically ready", async () => {
  const setup = await setupFakeSession({ semanticReadySequence: [true, false, true] });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "queued-ready", sessionId: setup.descriptor.sessionId, steps: [actStep], limits: { timeoutMs: 2_000, maxActions: 1 } });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "completed");
});

test("journey retains an accepted reply when post-command readiness times out", async () => {
  const setup = await setupFakeSession({ semanticReadySequence: [true, true, false] });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "queued-timeout", sessionId: setup.descriptor.sessionId, steps: [actStep], limits: { timeoutMs: 2_000, maxActions: 1 } });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.failure?.code, "timeout");
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { acceptedInputs: Array<{ accepted: boolean }>; steps: Array<{ reply: { ok: boolean }; after: unknown; afterUnavailableReason: string | null; capture: { unavailableReason?: string } }> };
  assert.equal(evidence.acceptedInputs[0]?.accepted, true);
  assert.equal(evidence.steps[0]?.reply.ok, true);
  assert.ok(evidence.steps[0]?.after);
  assert.match(evidence.steps[0]?.capture?.unavailableReason ?? "", /deadline|visual|cancellation|budget/i);
});

test("journey captures a screenshot when expectation verification fails", async () => {
  const setup = await setupFakeSession();
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "expectation-failure-capture", sessionId: setup.descriptor.sessionId, steps: [{ ...actStep, expect: { interactionKind: "shop_action" } }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.failure?.code, "unexpected_interaction");
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { steps: Array<{ capture: Record<string, unknown> }> };
  assert.equal(evidence.steps[0]?.capture?.bytes, 64);
});

test("journey permits UI control execution against an active modal", async () => {
  const setup = await setupFakeSession({ pending: { requestId: "shop-1", kind: "shop", shopId: 7 }, controls: [{ controlId: "enter-shop", label: "Enter", enabled: true }] });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "modal-ui", sessionId: setup.descriptor.sessionId, steps: [{ command: "ui", params: { controlId: "enter-shop" }, expect: { interactionKind: "shop", currentControlId: "enter-shop" } }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "completed");
});

test("journey resolves a UI label recipe to the one current enabled control", async () => {
  const setup = await setupFakeSession({ controls: [{ controlId: "shop-7", label: "Shop", enabled: true }] });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "label-ui", sessionId: setup.descriptor.sessionId, steps: [{ command: "ui", params: { action: "click", controlLabel: "Shop" }, expect: { interactionKind: null, currentControlId: "shop-7" } }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "completed");
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { acceptedInputs: Array<{ requestedParams: Record<string, unknown>; params: Record<string, unknown> }> };
  assert.deepEqual(evidence.acceptedInputs[0]?.requestedParams, { action: "click", controlLabel: "Shop" });
  assert.deepEqual(evidence.acceptedInputs[0]?.params, { action: "click", controlId: "shop-7" });
});

test("journey rejects an ambiguous enabled UI label", async () => {
  const setup = await setupFakeSession({ controls: [{ controlId: "shop-1", label: "Shop", enabled: true }, { controlId: "shop-2", label: "Shop", enabled: true }] });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "ambiguous-label-ui", sessionId: setup.descriptor.sessionId, steps: [{ command: "ui", params: { action: "click", controlLabel: "Shop" }, expect: { interactionKind: null } }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.failure?.code, "control_label_ambiguous");
});

test("journey retains failed command after diagnostics and a failure capture", async () => {
  const setup = await setupFakeSession({ failedCommand: "act", captureBytes: 128 });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "failure-evidence", sessionId: setup.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "failed");
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { steps: Array<{ after: Record<string, unknown> | null; capture: Record<string, unknown> | null }> };
  assert.ok(evidence.steps[0]?.after);
  assert.equal(evidence.steps[0]?.capture?.bytes, 128);
});

test("journey stops on an unexpected pending interaction", async () => {
  const setup = await setupFakeSession({ pending: { requestId: "pending-1", kind: "word-and-action", body: {} } });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "pending", sessionId: setup.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "failed");
  assert.equal(status.failure?.code, "unexpected_pending");
});

test("journey retains a failure observation and capture before submitting input", async () => {
  const setup = await setupFakeSession({ pending: { requestId: "pending-1", kind: "word-and-action", body: {} } });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "pending-evidence", sessionId: setup.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { acceptedInputs: unknown[]; steps: unknown[]; failureObservation: Record<string, unknown> | null; failureCapture: Record<string, unknown> | null };
  assert.equal(status.failure?.code, "unexpected_pending");
  assert.equal(evidence.acceptedInputs.length, 0);
  assert.equal(evidence.steps.length, 0);
  assert.deepEqual(evidence.failureObservation?.pendingInteraction, { requestId: "pending-1", kind: "word-and-action", body: {} });
  assert.equal(evidence.failureCapture?.bytes, 64);
});

test("journey retains a pre-submit UI recipe failure without claiming input", async () => {
  const setup = await setupFakeSession({ controls: [{ controlId: "shop-1", label: "Shop", enabled: true }, { controlId: "shop-2", label: "Shop", enabled: true }] });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "label-evidence", sessionId: setup.descriptor.sessionId, steps: [{ command: "ui", params: { action: "click", controlLabel: "Shop" }, expect: { interactionKind: null } }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { acceptedInputs: unknown[]; failureObservation: Record<string, unknown> | null; failureCapture: Record<string, unknown> | null };
  assert.equal(status.failure?.code, "control_label_ambiguous");
  assert.equal(evidence.acceptedInputs.length, 0);
  assert.ok(evidence.failureObservation);
  assert.equal(evidence.failureCapture?.bytes, 64);
});

test("journey preserves an exact Castle queued execution failure after acceptance", async () => {
  const setup = await setupFakeSession({ executionFailure: { code: "castle_action_failed", message: "Castle could not complete the queued action." } });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "queued-execution-failure", sessionId: setup.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { acceptedInputs: Array<{ accepted: boolean }>; steps: Array<{ error: Record<string, unknown> }> };
  assert.equal(status.failure?.code, "castle_action_failed");
  assert.equal(status.failure?.message, "Castle could not complete the queued action.");
  assert.equal(evidence.acceptedInputs[0]?.accepted, true);
  assert.deepEqual(evidence.steps[0]?.error, { code: "castle_action_failed", message: "Castle could not complete the queued action." });
});

test("journey resolves only the literal pending response request identity", async () => {
  const setup = await setupFakeSession({ pending: { kind: "shop_action", version: 1, data: { requestId: "pending-1", payload: {} } } });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "pending-response", sessionId: setup.descriptor.sessionId, steps: [{ command: "respond", params: { response: { requestId: "$pending", kind: "shop_action", body: {} } }, expect: { interactionKind: "shop_action" } }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "completed");
  const evidence = JSON.parse(await fs.readFile(job.evidencePath, "utf8")) as { acceptedInputs: Array<{ params: { response: { requestId: string } } }> };
  assert.equal(evidence.acceptedInputs[0]?.params.response.requestId, "pending-1");
});

test("journey stops before action when trace capacity is saturated", async () => {
  const setup = await setupFakeSession({ traceLimitReached: true });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "trace-cap", sessionId: setup.descriptor.sessionId, steps: [actStep] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.failure?.code, "trace_limit");
  assert.equal(status.counts.actions, 0);
});

test("journey retains cancellation and timeout failures", async () => {
  const cancelled = await setupFakeSession();
  const cancelledJob = await makeJob(cancelled.home, cancelled.descriptor.sessionId, { name: "cancel", sessionId: cancelled.descriptor.sessionId, steps: [actStep] }, true);
  await runJourneyJob(cancelledJob.id, cancelled.home);
  const cancelledStatus = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(cancelledJob.statusPath, "utf8")));
  assert.equal(cancelledStatus.state, "cancelled");
  assert.equal(cancelledStatus.failure?.code, "cancelled");

  const timeout = await setupFakeSession({ traceLimitReached: false, ready: false });
  const timeoutJob = await makeJob(timeout.home, timeout.descriptor.sessionId, { name: "timeout", sessionId: timeout.descriptor.sessionId, steps: [actStep], limits: { timeoutMs: 1, maxActions: 1 } });
  await runJourneyJob(timeoutJob.id, timeout.home);
  const timeoutStatus = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(timeoutJob.statusPath, "utf8")));
  assert.equal(timeoutStatus.state, "failed");
  assert.equal(timeoutStatus.failure?.code, "timeout");
});

test("journey stops explicitly before exceeding the evidence cap", async () => {
  const setup = await setupFakeSession({ captureBytes: 256 * 1024 * 1024 });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "evidence-cap", sessionId: setup.descriptor.sessionId, steps: [{ ...actStep, capture: true }] });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.state, "failed");
  assert.equal(status.failure?.code, "evidence_limit");
});

test("journey reserves evidence capacity before dispatching the next action", async () => {
  const setup = await setupFakeSession({ captureBytes: 220 * 1024 * 1024 });
  const job = await makeJob(setup.home, setup.descriptor.sessionId, { name: "evidence-reserve", sessionId: setup.descriptor.sessionId, steps: [{ ...actStep, capture: true }, actStep], limits: { timeoutMs: 5_000, maxActions: 2 } });
  await runJourneyJob(job.id, setup.home);
  const status = JourneyStatusSchema.parse(JSON.parse(await fs.readFile(job.statusPath, "utf8")));
  assert.equal(status.failure?.code, "evidence_limit");
  assert.equal(status.counts.actions, 1);
});

test("journey comparison rejects incomplete or empty evidence", async () => {
  const home = await fs.mkdtemp(path.join(os.tmpdir(), "realmz-journey-compare-"));
  homes.push(home);
  const left = path.join(home, "left.json");
  const right = path.join(home, "right.json");
  const incomplete = { format: "realmz-journey/1", completed: false, baseline: null, initialObservation: null, steps: [], failure: { code: "timeout" } };
  await fs.writeFile(left, JSON.stringify(incomplete));
  await fs.writeFile(right, JSON.stringify(incomplete));
  const comparison = await compareJourneyRuns(left, right);
  assert.equal(comparison.equal, false);
  assert.equal(comparison.initialEquivalenceVerified, false);
});
