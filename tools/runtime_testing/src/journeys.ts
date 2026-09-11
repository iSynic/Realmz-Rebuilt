import { randomBytes, randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { discoverSession } from "./discovery.js";
import { requestSession } from "./client.js";
import { checkpointFixture } from "./fixtures.js";
import { JourneySpecSchema, JourneyStatusSchema, type JourneySpec, type JourneyStatus, type JourneyStep, type TestingReply } from "./schemas.js";

const MAX_EVIDENCE_BYTES = 256 * 1024 * 1024;
const PER_STEP_EVIDENCE_RESERVE_BYTES = 64 * 1024 * 1024;
const MAX_CAPTURE_RESERVE_BYTES = 32 * 1024 * 1024;
const DEFAULT_POLL_MS = 100;
const JOB_ID = /^[a-f0-9]{32}$/;
const IGNORED_COMPARE_KEYS = new Set(["requestId", "revision", "gameRevision", "expectedRevision", "startedAt", "finishedAt", "pid", "port", "token", "build", "fixtureRoot", "configPath", "checkpointPath", "timingMs", "durationMs", "capture", "path", "sha256", "bytes", "width", "height"]);

export class JourneyError extends Error {
  constructor(readonly code: string, message: string, readonly mode = "journey", readonly stepIndex?: number) {
    super(message);
    this.name = "JourneyError";
  }
}

type Observation = { reply: TestingReply; result: Record<string, unknown> };

function homePath(home?: string): string {
  const value = home ?? process.env.REALMZ_TESTING_HOME;
  if (!value || !path.isAbsolute(value)) throw new JourneyError("invalid_home", "REALMZ_TESTING_HOME must be an absolute path");
  return path.resolve(value);
}

function jobRoot(home: string, jobId: string): string {
  if (!JOB_ID.test(jobId)) throw new JourneyError("invalid_job", "job ID is invalid");
  return path.join(home, "jobs", jobId);
}

function paths(home: string, jobId: string): { root: string; spec: string; status: string; evidence: string; cancel: string } {
  const root = jobRoot(home, jobId);
  return { root, spec: path.join(root, "spec.json"), status: path.join(root, "status.json"), evidence: path.join(root, "evidence.json"), cancel: path.join(root, "cancel") };
}

async function writeJson(file: string, value: unknown): Promise<void> {
  const temporary = `${file}.${randomUUID()}.tmp`;
  try {
    await fs.writeFile(temporary, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
    await fs.rename(temporary, file);
  } catch (error) {
    await fs.rm(temporary, { force: true }).catch(() => undefined);
    throw error;
  }
}

async function readJson<T>(file: string): Promise<T> {
  return JSON.parse(await fs.readFile(file, "utf8")) as T;
}

async function assertJobRoot(home: string, p: ReturnType<typeof paths>): Promise<void> {
  const jobs = path.dirname(p.root);
  await fs.mkdir(jobs, { recursive: true });
  const jobsStat = await fs.lstat(jobs).catch(() => null);
  if (jobsStat === null || !jobsStat.isDirectory() || jobsStat.isSymbolicLink()) throw new JourneyError("invalid_job_root", "the journey jobs root must be a regular directory");
  const rootStat = await fs.lstat(p.root).catch(() => null);
  if (rootStat?.isSymbolicLink()) throw new JourneyError("invalid_job_root", "the journey job root may not be a symbolic link");
  if (!path.resolve(p.root).startsWith(`${path.resolve(home)}${path.sep}`)) throw new JourneyError("invalid_job_root", "the journey job path escaped the testing home");
}

function now(): string { return new Date().toISOString(); }

function initialStatus(jobId: string, spec: JourneySpec, p: ReturnType<typeof paths>): JourneyStatus {
  return JourneyStatusSchema.parse({ jobId, name: spec.name, sessionId: spec.sessionId, state: "queued", specPath: p.spec, statusPath: p.status, evidencePath: p.evidence, baselineCheckpointPath: null, startedAt: null, finishedAt: null, counts: { steps: 0, actions: 0, captures: 0, evidenceBytes: 0 }, failure: null });
}

async function saveStatus(file: string, status: JourneyStatus): Promise<void> {
  await writeJson(file, JourneyStatusSchema.parse(status));
}

export function compactJourneyStatus(status: JourneyStatus): Record<string, unknown> {
  return { jobId: status.jobId, name: status.name, sessionId: status.sessionId, state: status.state, statusPath: status.statusPath, evidencePath: status.evidencePath, baselineCheckpointPath: status.baselineCheckpointPath, counts: status.counts, failure: status.failure };
}

export async function startJourney(input: unknown, home?: string): Promise<Record<string, unknown>> {
  const spec = JourneySpecSchema.parse(input);
  const rootHome = homePath(home);
  const jobId = randomBytes(16).toString("hex");
  const p = paths(rootHome, jobId);
  await assertJobRoot(rootHome, p);
  await fs.mkdir(p.root, { recursive: false });
  await writeJson(p.spec, spec);
  const status = initialStatus(jobId, spec, p);
  await saveStatus(p.status, status);
  const worker = await workerPath();
  let child;
  try {
    child = spawn(process.execPath, [...worker.loaderArgs, worker.path, jobId, rootHome], { cwd: rootHome, detached: true, windowsHide: true, shell: false, stdio: "ignore", env: { ...process.env, GODOT_MCP_HEADLESS_CHILD: "1" } });
    child.once("error", (error) => { void failSpawn(p.status, status, error); });
    child.unref();
  } catch (error) {
    await failSpawn(p.status, status, error);
  }
  return compactJourneyStatus(await readStatus(jobId, rootHome));
}

async function workerPath(): Promise<{ path: string; loaderArgs: string[] }> {
  const js = fileURLToPath(new URL("./journey-worker.js", import.meta.url));
  try { await fs.access(js); return { path: js, loaderArgs: [] }; }
  catch {
    const ts = fileURLToPath(new URL("./journey-worker.ts", import.meta.url));
    try { await fs.access(ts); }
    catch { throw new JourneyError("worker_unavailable", "the built journey worker is unavailable; run npm run build"); }
    const loaderArgs: string[] = [];
    for (let index = 0; index < process.execArgv.length; index += 1) {
      const arg = process.execArgv[index];
      if (arg === "--require" || arg === "--import") { loaderArgs.push(arg, process.execArgv[index + 1] ?? ""); index += 1; }
    }
    return { path: ts, loaderArgs };
  }
}

async function failSpawn(statusPath: string, queued: JourneyStatus, error: unknown): Promise<void> {
  await saveStatus(statusPath, { ...queued, state: "failed", finishedAt: now(), failure: { code: "worker_spawn_failed", message: error instanceof Error ? error.message : "journey worker failed to spawn", mode: "journey" } });
}

export async function readStatus(jobId: string, home?: string): Promise<JourneyStatus> {
  const rootHome = homePath(home);
  const p = paths(rootHome, jobId);
  await assertJobRoot(rootHome, p);
  const value = await readJson<unknown>(p.status);
  return JourneyStatusSchema.parse(value);
}

export async function cancelJourney(jobId: string, home?: string): Promise<Record<string, unknown>> {
  const rootHome = homePath(home);
  const status = await readStatus(jobId, rootHome);
  if (["completed", "failed", "cancelled"].includes(status.state)) return compactJourneyStatus(status);
  const p = paths(rootHome, jobId);
  await fs.writeFile(p.cancel, "cancel\n", { encoding: "utf8", mode: 0o600, flag: "wx" }).catch((error: unknown) => { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; });
  return compactJourneyStatus({ ...status, state: "running", failure: { code: "cancel_requested", message: "cancellation requested; worker will stop at the next boundary", mode: "journey" } });
}

async function cancelled(cancelPath: string): Promise<boolean> { return fs.access(cancelPath).then(() => true).catch(() => false); }

function failure(code: string, message: string, mode: string, stepIndex?: number): never { throw new JourneyError(code, message, mode, stepIndex); }

function recordOf(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function readinessFields(result: Record<string, unknown>, stepIndex: number): Record<string, unknown> {
  const value = recordOf(result.readiness);
  if (value === null && typeof result.semanticReady === "boolean") return { semanticReady: result.semanticReady };
  if (value === null) failure("readiness_unavailable", "the engine did not return semantic readiness", "readiness", stepIndex);
  return value;
}

function explicitSemanticReady(result: Record<string, unknown>, readiness: Record<string, unknown>): boolean | undefined {
  const value = readiness.semanticReady ?? result.semanticReady;
  return typeof value === "boolean" ? value : undefined;
}

function visualReady(result: Record<string, unknown>): boolean | undefined {
  const fields = recordOf(result.readiness);
  return fields && typeof fields.visualReady === "boolean" ? fields.visualReady : undefined;
}

function engineFailure(result: Record<string, unknown>): { error: Record<string, unknown>; code: string; message: string } | null {
  const value = recordOf(result.failure);
  if (value === null) return null;
  const code = typeof value.code === "string" && value.code.length > 0 ? value.code : "engine_failure";
  const message = typeof value.message === "string" && value.message.length > 0 ? value.message : JSON.stringify(value);
  return { error: value, code, message };
}

function throwEngineFailure(result: Record<string, unknown>, mode: string, stepIndex?: number): void {
  const value = engineFailure(result);
  if (value !== null) failure(value.code, value.message, mode, stepIndex);
}

function waitCadence(deadline: number): Promise<void> {
  const remaining = Math.max(1, deadline - Date.now());
  return new Promise((resolve) => setTimeout(resolve, Math.min(DEFAULT_POLL_MS, remaining)));
}

function checkDeadline(deadline: number, mode: string, stepIndex?: number): void {
  if (Date.now() > deadline) failure("timeout", "the journey deadline expired", mode, stepIndex);
}

async function observe(sessionId: string, home: string): Promise<Observation> {
  const reply = await requestSession(sessionId, "observe", { diagnostics: "complete" }, null, `journey-observe-${randomUUID()}`, home);
  if (!reply.ok || reply.result === null) failure(reply.error?.code ?? "observe_failed", reply.error?.message ?? "journey observation failed", "observe");
  return { reply, result: reply.result };
}

function readiness(result: Record<string, unknown>, command: JourneyStep["command"], params: Record<string, unknown>, stepIndex: number): void {
  const effectiveParams = command === "ui" ? resolveUiParams(params, result, stepIndex) : params;
  const r = readinessFields(result, stepIndex);
  if (r.fixtureReady !== undefined && r.fixtureReady !== true) failure("fixture_not_ready", "fixture is not ready", "readiness", stepIndex);
  if (r.fixtureError !== null && r.fixtureError !== undefined) failure("fixture_error", JSON.stringify(r.fixtureError), "readiness", stepIndex);
  if (r.combatPlayback === true || r.hostInteraction === true) failure("input_blocked", "presentation playback or a host interaction owns the boundary", command, stepIndex);
  if (explicitSemanticReady(result, r) === false) failure("input_blocked", "the engine has not reached its semantic input boundary", command, stepIndex);
  const pending = result.pendingInteraction;
  if ((command === "act" || command === "invoke") && pending !== null && pending !== undefined) failure("unexpected_pending", "a pending interaction must be answered before this command", command, stepIndex);
  if (command === "act" && explicitSemanticReady(result, r) !== true && r.explorationInput !== true) failure("input_blocked", "the fixture is not accepting exploration input", command, stepIndex);
  if (command === "respond" && (result.pendingInteraction === null || typeof result.pendingInteraction !== "object")) failure("unexpected_interaction", "respond requires an observed pending interaction", command, stepIndex);
  if (command === "ui") {
    const controlId = effectiveParams.controlId;
    if (typeof controlId !== "string") failure("invalid_params", "ui requires a supplied controlId", command, stepIndex);
    const controls = Array.isArray(result.controls) ? result.controls : [];
    const control = controls.find((entry) => entry !== null && typeof entry === "object" && (entry as Record<string, unknown>).controlId === controlId) as Record<string, unknown> | undefined;
    if (!control || control.enabled !== true) failure("control_unavailable", "the supplied current control is not visible and enabled", command, stepIndex);
  }
}

function postCommandReady(result: Record<string, unknown>, stepIndex: number): boolean {
  const r = readinessFields(result, stepIndex);
  if (r.fixtureReady !== undefined && r.fixtureReady !== true) return false;
  if (r.fixtureError !== null && r.fixtureError !== undefined) failure("fixture_error", JSON.stringify(r.fixtureError), "readiness", stepIndex);
  if (r.combatPlayback === true || r.hostInteraction === true) return false;
  const semantic = explicitSemanticReady(result, r);
  if (semantic !== undefined) return semantic;
  // Older Rebuilt observations have no semanticReady field. Their rendered
  // boundary is the strongest available signal, while pending interactions,
  // shops, and other non-exploration surfaces remain valid post-command state.
  return visualReady(result) !== false;
}

function resolvePending(params: Record<string, unknown>, result: Record<string, unknown>, stepIndex: number): Record<string, unknown> {
  const response = params.response;
  if (response === null || typeof response !== "object" || Array.isArray(response)) return params;
  const value = response as Record<string, unknown>;
  if (value.requestId !== "$pending") return params;
  const pending = result.pendingInteraction;
  const pendingRecord = recordOf(pending);
  const pendingData = pendingRecord === null ? null : recordOf(pendingRecord.data);
  const requestId = pendingRecord?.requestId ?? pendingData?.requestId;
  if (typeof requestId !== "string") failure("unexpected_interaction", "the pending response identity is unavailable", "respond", stepIndex);
  return { ...params, response: { ...value, requestId } };
}

function resolveUiParams(params: Record<string, unknown>, result: Record<string, unknown>, stepIndex: number): Record<string, unknown> {
  const action = params.action;
  const controlLabel = params.controlLabel;
  const controlId = params.controlId;
  if (controlLabel !== undefined) {
    if (action !== "click" || typeof controlLabel !== "string" || controlLabel.length === 0 || typeof controlId === "string") failure("invalid_params", "UI label recipes require action: click and one controlLabel", "ui", stepIndex);
    const controls = Array.isArray(result.controls) ? result.controls : [];
    const matches = controls.filter((entry) => {
      const value = recordOf(entry);
      return value?.label === controlLabel && value.enabled === true && typeof value.controlId === "string";
    }) as Array<Record<string, unknown>>;
    if (matches.length === 0) failure("control_label_unavailable", `no current enabled UI control has label '${controlLabel}'`, "ui", stepIndex);
    if (matches.length !== 1) failure("control_label_ambiguous", `more than one current enabled UI control has label '${controlLabel}'`, "ui", stepIndex);
    return { action: "click", controlId: matches[0]!.controlId };
  }
  if (action === "click" && typeof controlId === "string") return { action: "click", controlId };
  if (action === undefined && typeof controlId === "string") return { action: "click", controlId };
  return params;
}

function pendingKind(result: Record<string, unknown>): string | null {
  const pending = result.pendingInteraction;
  return pending !== null && typeof pending === "object" && typeof (pending as Record<string, unknown>).kind === "string" ? String((pending as Record<string, unknown>).kind) : null;
}

function verifyExpectation(result: Record<string, unknown>, step: JourneyStep, params: Record<string, unknown>, stepIndex: number): void {
  const expected = step.expect;
  const actual = pendingKind(result);
  if (actual !== expected.interactionKind) failure("unexpected_interaction", `expected interaction ${expected.interactionKind ?? "none"}, received ${actual ?? "none"}`, step.command, stepIndex);
  if (expected.location) {
    const location = result.location;
    if (diffValues(normalize(location), normalize(expected.location), "$.location") !== null) failure("unexpected_location", "the observed location differs from the journey expectation", step.command, stepIndex);
  }
  if (expected.currentControlId !== undefined && expected.currentControlId !== params.controlId) failure("control_mismatch", "expect.currentControlId must match the supplied UI controlId", step.command, stepIndex);
}

function traceDelta(previous: Record<string, unknown>, current: Record<string, unknown>, key: "rngTrace" | "scenarioTrace", stepIndex: number): unknown[] {
  const before = Array.isArray(previous[key]) ? previous[key] : [];
  const after = Array.isArray(current[key]) ? current[key] : [];
  if (after.length < before.length) failure("trace_gap", `${key} was shortened before the next journey step`, "trace", stepIndex);
  for (let i = 0; i < before.length; i += 1) if (JSON.stringify(before[i]) !== JSON.stringify(after[i])) failure("trace_gap", `${key} no longer has the prior prefix`, "trace", stepIndex);
  if (key === "rngTrace" && after.length > before.length) {
    const first = after[before.length];
    const previousLast = before.at(-1);
    if (previousLast && first && typeof previousLast === "object" && typeof first === "object" && typeof (previousLast as Record<string, unknown>).drawIndex === "number" && typeof (first as Record<string, unknown>).drawIndex === "number" && Number((first as Record<string, unknown>).drawIndex) !== Number((previousLast as Record<string, unknown>).drawIndex) + 1) failure("trace_gap", "RNG drawIndex skipped a trace entry", "trace", stepIndex);
  }
  return after.slice(before.length);
}

function normalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(normalize);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.entries(value as Record<string, unknown>).filter(([key]) => !IGNORED_COMPARE_KEYS.has(key)).sort(([a], [b]) => a.localeCompare(b)).map(([key, entry]) => [key, normalize(entry)]));
  return value;
}

function diffValues(left: unknown, right: unknown, at = "$"): { path: string; left: unknown; right: unknown } | null {
  if (JSON.stringify(left) === JSON.stringify(right)) return null;
  if (left === null || right === null || typeof left !== "object" || typeof right !== "object" || Array.isArray(left) !== Array.isArray(right)) return { path: at, left, right };
  const leftRecord = left as Record<string, unknown>;
  const rightRecord = right as Record<string, unknown>;
  const keys = [...new Set([...Object.keys(leftRecord), ...Object.keys(rightRecord)])].sort();
  for (const key of keys) { const difference = diffValues(leftRecord[key], rightRecord[key], `${at}.${key}`); if (difference) return difference; }
  return { path: at, left, right };
}

function normalizedObservation(value: unknown): unknown {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return value;
  const observation = value as Record<string, unknown>;
  if (observation.observation !== undefined) return normalize({ mode: observation.mode, state: observation.state, events: observation.events, observation: normalizedObservation(observation.observation) });
  return normalize({
    campaignId: observation.campaignId,
    packageHash: observation.packageHash,
    rulesVersion: observation.rulesVersion,
    sessionStarted: observation.sessionStarted,
    location: observation.location,
    clock: observation.clock,
    fatigue: observation.fatigue,
    pooledGold: observation.pooledGold,
    party: observation.party,
    pendingInteraction: observation.pendingInteraction,
    actions: observation.actions,
    rngTrace: observation.rngTrace,
    scenarioTrace: observation.scenarioTrace,
    traceLimitReached: observation.traceLimitReached
  });
}

async function waitSemantic(sessionId: string, home: string, step: JourneyStep, stepIndex: number, deadline: number, cancelPath: string, onObservation?: (observation: Observation) => void): Promise<Observation> {
  while (Date.now() <= deadline) {
    if (await cancelled(cancelPath)) failure("cancelled", "journey cancellation requested", "journey", stepIndex);
    checkDeadline(deadline, "readiness", stepIndex);
    const current = await observe(sessionId, home);
    onObservation?.(current);
    throwEngineFailure(current.result, "readiness", stepIndex);
    try { readiness(current.result, step.command, step.params, stepIndex); return current; }
    catch (error) { if (!(error instanceof JourneyError) || !["fixture_not_ready", "input_blocked", "control_unavailable"].includes(error.code)) throw error; }
    await waitCadence(deadline);
  }
  failure("timeout", "semantic readiness did not become actionable before the journey deadline", "readiness", stepIndex);
}

async function waitPostCommand(sessionId: string, home: string, deadline: number, cancelPath: string, stepIndex: number, onObservation?: (observation: Observation) => void): Promise<Observation> {
  while (Date.now() <= deadline) {
    if (await cancelled(cancelPath)) failure("cancelled", "journey cancellation requested", "journey", stepIndex);
    checkDeadline(deadline, "observe", stepIndex);
    const current = await observe(sessionId, home);
    onObservation?.(current);
    throwEngineFailure(current.result, "observe", stepIndex);
    if (postCommandReady(current.result, stepIndex)) return current;
    await waitCadence(deadline);
  }
  failure("timeout", "the post-command semantic boundary did not settle before the journey deadline", "observe", stepIndex);
}

async function tryObserve(sessionId: string, home: string): Promise<{ observation: Observation | null; reason: string | null }> {
  try { return { observation: await observe(sessionId, home), reason: null }; }
  catch (error) { return { observation: null, reason: error instanceof Error ? error.message : "complete diagnostics were unavailable" }; }
}

async function failureCapture(sessionId: string, home: string, after: Observation | null, deadline: number, cancelPath: string, stepIndex: number): Promise<Record<string, unknown>> {
  let visual = after;
  while (Date.now() <= deadline) {
    if (await cancelled(cancelPath)) return { unavailableReason: "cancellation_requested_before_failure_capture" };
    if (visual !== null && visualReady(visual.result) === true) {
      try {
        const capture = await requestSession(sessionId, "capture", {}, null, `journey-failure-capture-${randomUUID()}`, home);
        if (capture.ok && capture.result !== null) return capture.result;
        return { unavailableReason: `${capture.error?.code ?? "capture_failed"}: ${capture.error?.message ?? "failure capture was unavailable"}` };
      } catch (error) {
        return { unavailableReason: error instanceof Error ? error.message : "failure capture was unavailable" };
      }
    }
    const next = await tryObserve(sessionId, home);
    if (next.observation !== null) visual = next.observation;
    else if (visual === null) return { unavailableReason: next.reason ?? "complete diagnostics were unavailable" };
    await waitCadence(deadline);
  }
  return { unavailableReason: "visual readiness did not settle before failure capture" };
}

function replyMode(reply: TestingReply, fallback: JourneyStep["command"]): unknown {
  const result = recordOf(reply.result);
  return result?.mode ?? result?.inputMode ?? fallback;
}

async function run(spec: JourneySpec, jobId: string, home: string, p: ReturnType<typeof paths>, status: JourneyStatus): Promise<void> {
  const evidence: Record<string, unknown> = { format: "realmz-journey/1", completed: false, jobId, name: spec.name, sessionId: spec.sessionId, baseline: null, initialObservation: null, acceptedInputs: [], steps: [], failureObservation: null, failureCapture: null, failure: null };
  let evidenceBytes = 0;
  let mediaBytes = 0;
  let baselineBytes = 0;
  const actualEvidenceBytes = (): number => Buffer.byteLength(`${JSON.stringify(evidence, null, 2)}\n`, "utf8") + baselineBytes + mediaBytes;
  const persist = async (): Promise<void> => {
    const bytes = actualEvidenceBytes();
    if (bytes > MAX_EVIDENCE_BYTES) failure("evidence_limit", "the 256 MiB evidence bound would be exceeded; no further evidence was recorded", "evidence");
    evidenceBytes = bytes;
    await writeJson(p.evidence, evidence);
  };
  const deadline = Date.now() + spec.limits.timeoutMs;
  let previous: Record<string, unknown> | null = null;
  let latestObservation: Observation | null = null;
  let latestRecord: Record<string, unknown> | null = null;
  let latestStepIndex: number | undefined;
  const attachFailureCapture = async (record: Record<string, unknown>, after: Observation | null, stepIndex: number): Promise<void> => {
    let failureCaptureResult: Record<string, unknown>;
    if (actualEvidenceBytes() + MAX_CAPTURE_RESERVE_BYTES > MAX_EVIDENCE_BYTES) {
      failureCaptureResult = { unavailableReason: "evidence_budget_reserve_unavailable" };
    } else {
      try { failureCaptureResult = await failureCapture(spec.sessionId, home, after, deadline, p.cancel, stepIndex); }
      catch (error) { failureCaptureResult = { unavailableReason: error instanceof Error ? error.message : "failure capture was unavailable" }; }
    }
    const captureBytes = typeof failureCaptureResult.bytes === "number" && Number.isFinite(failureCaptureResult.bytes) ? Math.max(0, failureCaptureResult.bytes) : 0;
    const projected = Buffer.byteLength(`${JSON.stringify({ ...evidence, steps: [...(evidence.steps as unknown[]).slice(0, -1), { ...record, capture: failureCaptureResult }] }, null, 2)}\n`, "utf8") + baselineBytes + mediaBytes + captureBytes;
    if (projected > MAX_EVIDENCE_BYTES) failureCaptureResult = { unavailableReason: "evidence_limit_after_failure_capture" };
    record.capture = failureCaptureResult;
    mediaBytes += typeof failureCaptureResult.bytes === "number" && Number.isFinite(failureCaptureResult.bytes) ? Math.max(0, failureCaptureResult.bytes) : 0;
    if (failureCaptureResult.unavailableReason === undefined) status = { ...status, counts: { ...status.counts, captures: status.counts.captures + 1 } };
  };
  try {
    status = { ...status, state: "running", startedAt: now() };
    await saveStatus(p.status, status);
    const descriptor = await discoverSession(spec.sessionId, home);
    if (descriptor.access !== "fixture") failure("fixture_required", "journeys require an isolated fixture session", "journey");
    const baseline = await checkpointFixture(spec.sessionId, home, `journey-baseline-${randomUUID()}`);
    if (!baseline.ok || baseline.result === null || typeof baseline.result.checkpointPath !== "string") failure(baseline.error?.code ?? "snapshot_unavailable", baseline.error?.message ?? "a baseline checkpoint is required", "checkpoint");
    checkDeadline(deadline, "checkpoint");
    baselineBytes = (await fs.stat(baseline.result.checkpointPath)).size;
    evidence.baseline = { engine: descriptor.engine, checkpoint: baseline.result.checkpoint, canonicalSha256: baseline.result.sha256 ?? null, checkpointPath: baseline.result.checkpointPath, checkpointFileSha256: baseline.result.checkpointFileSha256 ?? null };
    status = { ...status, baselineCheckpointPath: baseline.result.checkpointPath };
    await saveStatus(p.status, status);
    if (await cancelled(p.cancel)) failure("cancelled", "journey cancellation requested", "journey");
    const initial = await observe(spec.sessionId, home);
    checkDeadline(deadline, "observe");
    evidence.initialObservation = initial.result;
    latestObservation = initial;
    await persist();
    previous = initial.result;
    for (let index = 0; index < spec.steps.length; index += 1) {
      latestRecord = null;
      latestStepIndex = index;
      if (await cancelled(p.cancel)) failure("cancelled", "journey cancellation requested", "journey", index);
      checkDeadline(deadline, "journey", index);
      if (status.counts.actions >= spec.limits.maxActions) failure("action_limit", "the journey action limit was reached", "journey", index);
      if (actualEvidenceBytes() + PER_STEP_EVIDENCE_RESERVE_BYTES > MAX_EVIDENCE_BYTES) failure("evidence_limit", "the 256 MiB evidence bound does not leave the conservative reserve for another journey action", "evidence", index);
      const step = spec.steps[index]!;
      const before = await waitSemantic(spec.sessionId, home, step, index, deadline, p.cancel, (observation) => { latestObservation = observation; });
      latestObservation = before;
      if (before.result.traceLimitReached === true) failure("trace_limit", "the engine trace capacity was reached before the next action", "trace", index);
      const requestedParams = step.params;
      const resolvedParams = step.command === "respond" ? resolvePending(requestedParams, before.result, index) : step.command === "ui" ? resolveUiParams(requestedParams, before.result, index) : requestedParams;
      const params = resolvedParams;
      const requestId = `journey-${jobId}-${index}-${randomUUID()}`;
      const expectedRevision = before.reply.revision;
      let reply: TestingReply;
      try { reply = await requestSession(spec.sessionId, step.command, params, expectedRevision, requestId, home); }
      catch (error) {
        const message = error instanceof Error ? error.message : "journey command failed";
        (evidence.acceptedInputs as unknown[]).push({ command: step.command, requestedParams, params, expectedRevision, requestId, accepted: false });
        const failedAfter = await tryObserve(spec.sessionId, home);
        const after = failedAfter.observation;
        const record: Record<string, unknown> = { index, command: step.command, mode: step.command, requestedParams, params, expectedRevision, requestId, beforeRevision: before.reply.revision, afterRevision: after?.reply.revision ?? null, before: before.result, beforeNormalized: normalizedObservation(before.result), reply: null, after: after?.result ?? null, afterNormalized: after ? normalizedObservation(after.result) : null, diff: after ? diffValues(normalizedObservation(before.result), normalizedObservation(after.result), "$.observation") : null, error: { code: "transport_error", message }, afterUnavailableReason: after ? null : failedAfter.reason, traceDelta: after && previous ? { rngTrace: traceDelta(previous, after.result, "rngTrace", index), scenarioTrace: traceDelta(previous, after.result, "scenarioTrace", index) } : null, capture: null };
        (evidence.steps as unknown[]).push(record);
        latestRecord = record;
        latestObservation = after ?? latestObservation;
        status = { ...status, counts: { ...status.counts, steps: index + 1, actions: status.counts.actions + 1 } };
        await persist();
        await attachFailureCapture(record, after, index);
        await persist();
        await saveStatus(p.status, { ...status, counts: { ...status.counts, evidenceBytes } });
        failure("transport_error", message, step.command, index);
      }
      status = { ...status, counts: { ...status.counts, actions: status.counts.actions + 1 } };
      const acceptedInputs = evidence.acceptedInputs as unknown[];
      acceptedInputs.push({ command: step.command, requestedParams, params, expectedRevision, requestId, accepted: reply.ok });
      const record: Record<string, unknown> = { index, command: step.command, mode: replyMode(reply, step.command), inputMode: replyMode(reply, step.command), requestedParams, params, expectedRevision, requestId, beforeRevision: before.reply.revision, afterRevision: null, before: before.result, beforeNormalized: normalizedObservation(before.result), reply, after: null, afterNormalized: null, diff: null, error: reply.ok ? null : reply.error, afterUnavailableReason: reply.ok ? "post_command_observation_pending" : null, postCommandPending: reply.ok, traceDelta: null, capture: null };
      (evidence.steps as unknown[]).push(record);
      latestRecord = record;
      status = { ...status, counts: { ...status.counts, steps: index + 1 } };
      // Persist the accepted input and fresh failure diagnostics before an
      // optional capture can hit the inclusive evidence limit.
      await persist();
      let after: Observation | null;
      let afterReason: string | null = null;
      if (reply.ok) {
        try { after = await waitPostCommand(spec.sessionId, home, deadline, p.cancel, index, (observation) => { latestObservation = observation; }); }
        catch (error) {
          record.afterUnavailableReason = error instanceof Error ? error.message : "the post-command observation did not settle";
          record.postCommandPending = false;
          throw error;
        }
      } else {
        const afterResult = await tryObserve(spec.sessionId, home);
        after = afterResult.observation;
        afterReason = afterResult.reason;
      }
      const executionFailure = after === null ? null : engineFailure(after.result);
      if (executionFailure !== null) {
        record.error = executionFailure.error;
      }
      record.postCommandPending = false;
      record.afterRevision = after?.reply.revision ?? null;
      record.after = after?.result ?? null;
      record.afterNormalized = after ? normalizedObservation(after.result) : null;
      record.diff = after ? diffValues(normalizedObservation(before.result), normalizedObservation(after.result), "$.observation") : null;
      record.afterUnavailableReason = after ? null : afterReason;
      record.traceDelta = after && previous ? { rngTrace: traceDelta(previous, after.result, "rngTrace", index), scenarioTrace: traceDelta(previous, after.result, "scenarioTrace", index) } : null;
      if (after) latestObservation = after;
      await persist();
      if (!reply.ok) {
        await attachFailureCapture(record, after, index);
        await persist();
        await saveStatus(p.status, { ...status, counts: { ...status.counts, evidenceBytes } });
        failure(reply.error?.code ?? "command_failed", reply.error?.message ?? "journey command failed", step.command, index);
      }
      if (executionFailure !== null) failure(executionFailure.code, executionFailure.message, "observe", index);
      if (after === null) failure("observe_failed", "the post-command observation was unavailable", "observe", index);
      verifyExpectation(after.result, step, params, index);
      if (after.result.traceLimitReached === true) failure("trace_limit", "the engine trace capacity was reached; the journey stopped before another action", "trace", index);
      if (step.capture) {
        let visual = after;
        while (Date.now() <= deadline && visualReady(visual.result) !== true) {
          if (await cancelled(p.cancel)) failure("cancelled", "journey cancellation requested", "journey", index);
          checkDeadline(deadline, "capture", index);
          visual = await observe(spec.sessionId, home);
          latestObservation = visual;
          if (visualReady(visual.result) !== true) await waitCadence(deadline);
        }
        if (visualReady(visual.result) !== true) failure("timeout", "visual readiness did not settle before capture", "capture", index);
        if (actualEvidenceBytes() + MAX_CAPTURE_RESERVE_BYTES > MAX_EVIDENCE_BYTES) failure("evidence_limit", "the 256 MiB evidence bound does not leave the conservative reserve for a capture", "capture", index);
        const capture = await requestSession(spec.sessionId, "capture", {}, null, `journey-capture-${randomUUID()}`, home);
        if (!capture.ok || capture.result === null) failure(capture.error?.code ?? "capture_failed", capture.error?.message ?? "journey capture failed", "capture", index);
        const bytes = typeof capture.result.bytes === "number" ? capture.result.bytes : 0;
        const projected = Buffer.byteLength(`${JSON.stringify({ ...evidence, steps: [...(evidence.steps as unknown[]).slice(0, -1), { ...record, capture: capture.result }] }, null, 2)}\n`, "utf8") + baselineBytes + mediaBytes + bytes;
        if (projected > MAX_EVIDENCE_BYTES) failure("evidence_limit", "the 256 MiB evidence bound would be exceeded; no further capture was recorded", "capture", index);
        record.capture = capture.result;
        mediaBytes += bytes;
        status = { ...status, counts: { ...status.counts, captures: status.counts.captures + 1 } };
      }
      previous = after.result;
      await persist();
      await saveStatus(p.status, { ...status, counts: { ...status.counts, evidenceBytes } });
    }
    evidence.completed = true;
    await persist();
    status = { ...status, state: "completed", finishedAt: now(), counts: { ...status.counts, evidenceBytes } };
    await saveStatus(p.status, status);
  } catch (error) {
    const journeyError = error instanceof JourneyError ? error : new JourneyError("journey_failed", error instanceof Error ? error.message : "journey failed");
    evidence.failure = { code: journeyError.code, message: journeyError.message, mode: journeyError.mode, stepIndex: journeyError.stepIndex };
    if (latestRecord === null) {
      if (latestObservation !== null) {
        evidence.failureObservation = latestObservation.result;
        const observedFailure = engineFailure(latestObservation.result);
        if (observedFailure !== null && journeyError.code === observedFailure.code) evidence.failure = { ...(recordOf(evidence.failure) ?? {}), engine: observedFailure.error };
      } else {
        evidence.failureObservation = null;
        evidence.failureObservationUnavailableReason = "no complete observation was available at the failure boundary";
      }
      try {
        let failureCaptureResult: Record<string, unknown>;
        if (actualEvidenceBytes() + MAX_CAPTURE_RESERVE_BYTES > MAX_EVIDENCE_BYTES) {
          failureCaptureResult = { unavailableReason: "evidence_budget_reserve_unavailable" };
        } else {
          failureCaptureResult = await failureCapture(spec.sessionId, home, latestObservation, deadline, p.cancel, journeyError.stepIndex ?? -1);
        }
        const captureBytes = typeof failureCaptureResult.bytes === "number" && Number.isFinite(failureCaptureResult.bytes) ? Math.max(0, failureCaptureResult.bytes) : 0;
        const projected = Buffer.byteLength(`${JSON.stringify({ ...evidence, failureCapture: failureCaptureResult }, null, 2)}\n`, "utf8") + baselineBytes + mediaBytes + captureBytes;
        evidence.failureCapture = projected > MAX_EVIDENCE_BYTES ? { unavailableReason: "evidence_limit_after_failure_capture" } : failureCaptureResult;
        mediaBytes += projected > MAX_EVIDENCE_BYTES ? 0 : captureBytes;
        if (projected <= MAX_EVIDENCE_BYTES && failureCaptureResult.unavailableReason === undefined) status = { ...status, counts: { ...status.counts, captures: status.counts.captures + 1 } };
      } catch (captureError) {
        evidence.failureCapture = { unavailableReason: captureError instanceof Error ? captureError.message : "failure capture was unavailable" };
      }
    }
    if (latestRecord !== null && latestStepIndex !== undefined && latestRecord.capture === null) {
      if (latestRecord.after === null && latestObservation !== null) {
        const postCommandReason = latestRecord.afterUnavailableReason;
        latestRecord.afterRevision = latestObservation.reply.revision;
        latestRecord.after = latestObservation.result;
        latestRecord.afterNormalized = normalizedObservation(latestObservation.result);
        latestRecord.diff = previous === null ? null : diffValues(normalizedObservation(latestRecord.before), normalizedObservation(latestObservation.result), "$.observation");
        latestRecord.afterUnavailableReason = postCommandReason === "post_command_observation_pending" ? null : postCommandReason;
        latestRecord.postCommandPending = false;
        const observedFailure = engineFailure(latestObservation.result);
        if (observedFailure !== null) latestRecord.error = observedFailure.error;
        try {
          latestRecord.traceDelta = previous === null ? null : { rngTrace: traceDelta(previous, latestObservation.result, "rngTrace", latestStepIndex), scenarioTrace: traceDelta(previous, latestObservation.result, "scenarioTrace", latestStepIndex) };
        } catch (traceError) {
          latestRecord.traceUnavailableReason = traceError instanceof Error ? traceError.message : "trace delta was unavailable";
        }
      }
      try {
        await attachFailureCapture(latestRecord, latestObservation, latestStepIndex);
        await persist();
      } catch (captureError) {
        latestRecord.capture = { unavailableReason: captureError instanceof Error ? captureError.message : "failure capture was unavailable" };
        try { await persist(); } catch { /* preserve the primary failure and last bounded evidence */ }
      }
    }
    try { await persist(); } catch { /* preserve the explicit status failure when evidence is at capacity */ }
    const state = journeyError.code === "cancelled" ? "cancelled" : "failed";
    await saveStatus(p.status, { ...status, state, finishedAt: now(), counts: { ...status.counts, evidenceBytes }, failure: { code: journeyError.code, message: journeyError.message, mode: journeyError.mode, ...(journeyError.stepIndex === undefined ? {} : { stepIndex: journeyError.stepIndex }) } });
  }
}

export async function runJourneyJob(jobId: string, homeInput: string): Promise<void> {
  const home = homePath(homeInput);
  const p = paths(home, jobId);
  const spec = JourneySpecSchema.parse(await readJson<unknown>(p.spec));
  const status = await readStatus(jobId, home);
  await run(spec, jobId, home, p, status);
}

export async function runWorkerFromCommandLine(): Promise<void> {
  const [, , jobId, home] = process.argv;
  if (!jobId || !home) throw new JourneyError("invalid_worker_args", "journey worker requires job ID and testing home");
  await runJourneyJob(jobId, home);
}
