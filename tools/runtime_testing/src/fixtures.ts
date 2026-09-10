import { createHash, randomBytes, randomUUID } from "node:crypto";
import { execFile as execFileCallback, spawn } from "node:child_process";
import { closeSync, openSync, promises as fs } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { discoverSession, discoverSessions } from "./discovery.js";
import { requestSession } from "./client.js";
import { FixtureConfigSchema, FixtureIdSchema, FixtureReadinessSchema, PROTOCOL, ReplySchema, RestoreParamsSchema, SessionIdSchema, type PublicDescriptor, type TestingReply } from "./schemas.js";

const execFile = promisify(execFileCallback);
const SHA256 = /^[a-f0-9]{64}$/;
const SEED = zInt(1, 2_147_483_646);
const COORDINATE = zInt(0, 32_767);
const DEFAULT_TIMEOUT_MS = 30_000;
const MAX_SOURCE_ENTRIES = 4096;
const MAX_SOURCE_BYTES = 32 * 1024 * 1024;
const MAX_SOURCE_FILE_BYTES = 8 * 1024 * 1024;

function zInt(min: number, max: number) {
  return (value: number): boolean => Number.isSafeInteger(value) && value >= min && value <= max;
}

export interface FixtureEnvironment {
  testingHome: string;
  godotPath: string;
  rebuiltRoot: string;
}

export interface ClassicStartersSource {
  kind: "classic-starters";
  seed: number;
  location: { mapId: string; x: number; y: number };
}

export interface FixtureCreateInput {
  engine: "rebuilt";
  packagePath: string;
  source: ClassicStartersSource;
}

export interface FixtureCloneInput {
  engine: "rebuilt";
  packagePath: string;
  checkpointPath: string;
}

export interface FixtureProcessHandle {
  pid: number | undefined;
}

export interface FixtureLaunchRequest {
  godotPath: string;
  rebuiltRoot: string;
  args: string[];
  fixtureRoot: string;
  configPath: string;
  logPath: string;
  stdoutLogPath: string;
}

export type FixtureLauncher = (request: FixtureLaunchRequest) => Promise<FixtureProcessHandle> | FixtureProcessHandle;

export interface FixtureHandle {
  fixtureId: string;
  fixtureRoot: string;
  configPath: string;
  descriptor: PublicDescriptor;
  process: FixtureProcessHandle;
}

export class FixtureError extends Error {
  constructor(readonly code: string, message: string, readonly fixtureRoot?: string) {
    super(message);
    this.name = "FixtureError";
  }
}

function absolute(value: string, name: string): string {
  if (!path.isAbsolute(value)) throw new FixtureError("invalid_path", `${name} must be an absolute path`);
  return path.resolve(value);
}

function contained(root: string, target: string): boolean {
  const relative = path.relative(path.resolve(root), path.resolve(target));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

async function regularFile(file: string, name: string): Promise<void> {
  const stat = await fs.lstat(file).catch(() => null);
  if (stat === null || !stat.isFile() || stat.isSymbolicLink()) throw new FixtureError("invalid_path", `${name} must be a regular non-symlink file`);
}

async function directory(dir: string, name: string): Promise<void> {
  const stat = await fs.lstat(dir).catch(() => null);
  if (stat !== null && (!stat.isDirectory() || stat.isSymbolicLink())) throw new FixtureError("invalid_path", `${name} must be a regular directory`);
}

async function assertNoSymlinkAncestors(rootInput: string, targetInput: string, name: string): Promise<void> {
  const root = path.resolve(rootInput);
  const target = path.resolve(targetInput);
  if (!contained(root, target)) throw new FixtureError("invalid_path", `${name} escaped its allowed root`);
  const relative = path.relative(root, target);
  let current = root;
  const components = relative === "" ? [] : relative.split(path.sep);
  for (const component of components) {
    current = path.join(current, component);
    const stat = await fs.lstat(current).catch(() => null);
    if (stat?.isSymbolicLink()) throw new FixtureError("invalid_path", `${name} may not contain symbolic-link ancestors`);
  }
}

async function makeSafeDirectory(root: string, target: string, name: string): Promise<void> {
  await assertNoSymlinkAncestors(root, target, name);
  await fs.mkdir(target, { recursive: true });
  await assertNoSymlinkAncestors(root, target, name);
  await directory(target, name);
}

function sha256Bytes(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

async function sha256File(file: string): Promise<string> {
  return sha256Bytes(await fs.readFile(file));
}

function fixtureRoot(home: string, fixtureId: string): string {
  FixtureIdSchema.parse(fixtureId);
  const root = path.resolve(home, "fixtures");
  const target = path.resolve(root, fixtureId);
  if (!contained(root, target) || path.dirname(target) !== root) throw new FixtureError("invalid_path", "fixture path escaped the discovery root");
  return target;
}

export function fixtureEnvironment(env: NodeJS.ProcessEnv = process.env): FixtureEnvironment {
  const testingHome = absolute(env.REALMZ_TESTING_HOME ?? "", "REALMZ_TESTING_HOME");
  const godotPath = absolute(env.REALMZ_GODOT_PATH ?? "", "REALMZ_GODOT_PATH");
  const rebuiltRoot = absolute(env.REALMZ_REBUILT_ROOT ?? "", "REALMZ_REBUILT_ROOT");
  return { testingHome, godotPath, rebuiltRoot };
}

async function sourceBuild(rebuiltRoot: string): Promise<string> {
  const git = async (args: string[], maxBuffer = MAX_SOURCE_BYTES): Promise<string> => {
    try { return (await execFile("git", ["-C", rebuiltRoot, ...args], { maxBuffer })).stdout; }
    catch (error) {
      if (error instanceof Error && /maxBuffer/i.test(error.message)) throw new FixtureError("source_too_large", "the relevant dirty source exceeds the fixture fingerprint bound");
      throw error;
    }
  };
  let head: string;
  try { head = await git(["rev-parse", "HEAD"]); }
  catch { throw new FixtureError("source_unversioned", "REALMZ_REBUILT_ROOT must be a Git checkout with a resolvable HEAD"); }
  const relevant = ["project.godot", "src", "assets", "tools/runtime_testing_host.gd", "tools/runtime_testing_host.tscn", "tools/runtime_testing_host.gd.uid"];
  const diff = await git(["diff", "--binary", "HEAD", "--", ...relevant]);
  const untracked = await git(["ls-files", "--others", "--exclude-standard", "-z", "--", ...relevant]);
  const paths = untracked.split("\0").filter(Boolean).sort();
  if (paths.length > MAX_SOURCE_ENTRIES) throw new FixtureError("source_too_large", "too many relevant untracked source entries");
  let total = Buffer.byteLength(diff, "utf8");
  const material: string[] = [diff];
  for (const relative of paths) {
    const file = path.resolve(rebuiltRoot, relative);
    if (!contained(rebuiltRoot, file)) throw new FixtureError("invalid_path", "Git reported a source path outside REALMZ_REBUILT_ROOT");
    const stat = await fs.lstat(file).catch(() => null);
    if (stat?.isFile() && !stat.isSymbolicLink()) {
      if (stat.size > MAX_SOURCE_FILE_BYTES || total + stat.size > MAX_SOURCE_BYTES) throw new FixtureError("source_too_large", "relevant dirty source exceeds the fixture fingerprint bound");
      total += stat.size;
      material.push(relative, await sha256File(file));
    } else material.push(relative, "non-regular");
  }
  if (total === 0 && paths.length === 0) return `git:${head.trim()};clean`;
  return `git:${head.trim()};dirty:${sha256Bytes(Buffer.from(material.join("\n"), "utf8"))}`;
}

async function defaultLauncher(request: FixtureLaunchRequest): Promise<FixtureProcessHandle> {
  const stdoutFd = openSync(request.stdoutLogPath, "a");
  try {
    const args = [...request.args];
    const projectIndex = args.findIndex((value) => value.startsWith("res://"));
    args.splice(projectIndex < 0 ? args.length : projectIndex, 0, "--log-file", request.logPath);
    const child = spawn(request.godotPath, args, {
      cwd: request.rebuiltRoot,
      windowsHide: true,
      detached: true,
      shell: false,
      env: { ...process.env, GODOT_MCP_HEADLESS_CHILD: "1" },
      stdio: ["ignore", stdoutFd, stdoutFd]
    });
    return await new Promise<FixtureProcessHandle>((resolve, reject) => {
      child.once("error", reject);
      child.once("spawn", () => {
        child.unref();
        resolve({ pid: child.pid });
      });
    });
  } finally {
    closeSync(stdoutFd);
  }
}

function validateClassicSource(source: ClassicStartersSource): void {
  if (source.kind !== "classic-starters" || !SEED(source.seed) || typeof source.location?.mapId !== "string" || source.location.mapId.length < 1 || source.location.mapId.length > 128 || !COORDINATE(source.location.x) || !COORDINATE(source.location.y)) throw new FixtureError("invalid_source", "classic-starters requires a bounded seed and map coordinates in the inclusive 0..32767 range");
}

async function writeJson(file: string, value: unknown): Promise<void> {
  await fs.writeFile(file, `${JSON.stringify(value, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
}

async function writeJsonExclusive(file: string, value: unknown): Promise<void> {
  const handle = await fs.open(file, "wx", 0o600);
  try { await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`, "utf8"); }
  finally { await handle.close(); }
}

async function newCheckpointPath(root: string): Promise<string> {
  const directoryPath = path.join(root, "checkpoints");
  await makeSafeDirectory(root, directoryPath, "fixture checkpoint directory");
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const target = path.join(directoryPath, `${randomUUID()}.r2save`);
    await assertNoSymlinkAncestors(root, target, "fixture checkpoint path");
    try { const handle = await fs.open(target, "wx", 0o600); await handle.close(); return target; }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
  }
  throw new FixtureError("checkpoint_write_failed", "could not allocate a unique checkpoint path", root);
}

async function newCheckpointFileInDirectory(root: string, directoryPath: string, value: unknown, extension = "r2save"): Promise<string> {
  await makeSafeDirectory(root, directoryPath, "checkpoint directory");
  for (let attempt = 0; attempt < 8; attempt += 1) {
    const target = path.join(directoryPath, `${randomUUID()}.${extension}`);
    await assertNoSymlinkAncestors(root, target, "fixture checkpoint path");
    try { await writeJsonExclusive(target, value); return target; }
    catch (error) { if ((error as NodeJS.ErrnoException).code !== "EEXIST") throw error; }
  }
  throw new FixtureError("checkpoint_write_failed", "could not allocate a unique checkpoint path", root);
}

async function newCheckpointFile(root: string, value: unknown, extension = "r2save"): Promise<string> {
  return newCheckpointFileInDirectory(root, path.join(root, "checkpoints"), value, extension);
}

async function prepareRoot(home: string, fixtureId: string): Promise<string> {
  const fixtures = path.resolve(home, "fixtures");
  await makeSafeDirectory(home, fixtures, "fixture discovery root");
  const root = fixtureRoot(home, fixtureId);
  await assertNoSymlinkAncestors(home, root, "fixture scratch root");
  await fs.mkdir(root, { recursive: false });
  await assertNoSymlinkAncestors(home, root, "fixture scratch root");
  await directory(root, "fixture scratch root");
  return root;
}

export class FixtureManager {
  constructor(private readonly env: FixtureEnvironment = fixtureEnvironment(), private readonly launcher: FixtureLauncher = defaultLauncher) {}

  async create(input: FixtureCreateInput, timeoutMs = DEFAULT_TIMEOUT_MS, signal?: AbortSignal): Promise<FixtureHandle> {
    if (input.engine !== "rebuilt") throw new FixtureError("unsupported_engine", "fixture creation currently supports engine rebuilt only");
    validateClassicSource(input.source);
    return this.launch(input.packagePath, { ...input.source }, timeoutMs, signal);
  }

  async clone(input: FixtureCloneInput, timeoutMs = DEFAULT_TIMEOUT_MS, signal?: AbortSignal): Promise<FixtureHandle> {
    if (input.engine !== "rebuilt") throw new FixtureError("unsupported_engine", "fixture cloning currently supports engine rebuilt only");
    const checkpointPath = absolute(input.checkpointPath, "checkpointPath");
    await regularFile(checkpointPath, "checkpointPath");
    return this.launch(input.packagePath, { kind: "checkpoint", checkpointPath }, timeoutMs, signal);
  }

  private async launch(packagePathInput: string, source: Record<string, unknown>, timeoutMs: number, signal?: AbortSignal): Promise<FixtureHandle> {
    const packagePath = absolute(packagePathInput, "packagePath");
    if (!packagePath.toLowerCase().endsWith(".realmz2")) throw new FixtureError("invalid_package", "packagePath must name a .realmz2 package");
    await regularFile(packagePath, "packagePath");
    await directory(this.env.rebuiltRoot, "REALMZ_REBUILT_ROOT");
    await regularFile(this.env.godotPath, "REALMZ_GODOT_PATH");
    await fs.mkdir(this.env.testingHome, { recursive: true });
    await directory(this.env.testingHome, "REALMZ_TESTING_HOME");
    const fixtureId = randomBytes(16).toString("hex");
    const root = await prepareRoot(this.env.testingHome, fixtureId);
    const configPath = path.join(root, "fixture.json");
    const logPath = path.join(root, "engine.log");
    const sourceValue: Record<string, unknown> = { ...source };
    if (source.kind === "checkpoint") {
      const original = String(source.checkpointPath);
      const copied = await newCheckpointPath(root);
      await fs.copyFile(original, copied);
      sourceValue.checkpointPath = copied;
      sourceValue.checkpointSha256 = await sha256File(copied);
    }
    const config = {
      protocol: PROTOCOL,
      kind: "fixture",
      fixtureId,
      scratchRoot: root,
      discoveryRoot: this.env.testingHome,
      build: await sourceBuild(this.env.rebuiltRoot),
      packagePath,
      packageSha256: await sha256File(packagePath),
      source: sourceValue
    };
    FixtureConfigSchema.parse(config);
    await writeJson(configPath, config);
    const stdoutLogPath = path.join(root, "stdout.log");
    await fs.writeFile(logPath, "", { encoding: "utf8", mode: 0o600 });
    await fs.writeFile(stdoutLogPath, "", { encoding: "utf8", mode: 0o600 });
    const args = ["--path", this.env.rebuiltRoot, "--resolution", "1280x720", "--rendering-method", "mobile", "res://tools/runtime_testing_host.tscn", "--", configPath];
    let process: FixtureProcessHandle;
    try {
      process = await this.launcher({ godotPath: this.env.godotPath, rebuiltRoot: this.env.rebuiltRoot, args, fixtureRoot: root, configPath, logPath, stdoutLogPath });
    } catch (error) {
      throw new FixtureError("fixture_start_failed", error instanceof Error ? error.message : "fixture process failed to start", root);
    }
    try {
      const descriptor = await this.waitReady(fixtureId, timeoutMs, signal);
      return { fixtureId, fixtureRoot: root, configPath, descriptor, process };
    } catch (error) {
      // The process is deliberately left alone: on timeout/cancellation the descriptor may belong to a wrapper child.
      throw error instanceof FixtureError ? error : new FixtureError("fixture_start_failed", error instanceof Error ? error.message : "fixture startup failed", root);
    }
  }

  private async waitReady(fixtureId: string, timeoutMs: number, signal?: AbortSignal): Promise<PublicDescriptor> {
    const started = Date.now();
    while (Date.now() - started <= timeoutMs) {
      if (signal?.aborted) throw new FixtureError("fixture_cancelled", "fixture startup was cancelled", fixtureRoot(this.env.testingHome, fixtureId));
      const sessions = await discoverSessions(this.env.testingHome);
      const descriptor = sessions.find((candidate) => candidate.fixtureId === fixtureId);
      if (descriptor) {
        const reply = await requestSession(descriptor.sessionId, "observe", {}, null, `fixture-ready-${randomUUID()}`, this.env.testingHome);
        const readiness = reply.ok && reply.result !== null ? FixtureReadinessSchema.safeParse(reply.result.readiness) : null;
        if (readiness?.success && readiness.data.fixtureError !== null) {
          const fixtureError = readiness.data.fixtureError;
          const code = typeof fixtureError.code === "string" && fixtureError.code.length > 0 ? fixtureError.code : "fixture_not_ready";
          const message = typeof fixtureError.message === "string" && fixtureError.message.length > 0 ? fixtureError.message : "engine reported fixture preparation failure";
          throw new FixtureError(code, message, fixtureRoot(this.env.testingHome, fixtureId));
        }
        if (readiness?.success && readiness.data.fixtureReady) return descriptor;
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new FixtureError("fixture_timeout", "fixture readiness timed out; scratch artifacts were retained", fixtureRoot(this.env.testingHome, fixtureId));
  }
}

export async function checkpointFixture(sessionId: string, home?: string, requestId: string = randomUUID()): Promise<TestingReply> {
  const descriptor = await discoverSession(sessionId, home);
  const reply = await requestSession(sessionId, "checkpoint", {}, null, requestId, home);
  if (!reply.ok || reply.result === null) return reply;
  const resolvedHome = absolute(home ?? process.env.REALMZ_TESTING_HOME ?? "", "REALMZ_TESTING_HOME");
  const checkpoint = reply.result.checkpoint;
  if (checkpoint === null || typeof checkpoint !== "object" || Array.isArray(checkpoint)) return reply;
  const checkpointPath = descriptor.fixtureId
    ? await (async () => {
      const root = fixtureRoot(resolvedHome, descriptor.fixtureId!);
      await assertNoSymlinkAncestors(resolvedHome, root, "fixture scratch root");
      return newCheckpointFile(root, checkpoint, descriptor.engine === "castle" ? "json" : "r2save");
    })()
    : await newCheckpointFileInDirectory(resolvedHome, path.join(resolvedHome, "checkpoints", SessionIdSchema.parse(sessionId)), checkpoint);
  const checkpointFileSha256 = await sha256File(checkpointPath);
  // `reply.result` is the engine's canonical checkpoint contract.  Keep every
  // engine-owned digest intact; the retained transport file has its own hash
  // because it is a JSON export rather than the canonical binary checkpoint.
  const result = { ...reply.result, checkpointPath, checkpointFileSha256 };
  return ReplySchema.parse({ ...reply, result });
}

export async function restoreFixture(sessionId: string, checkpoint: Record<string, unknown>, expectedRevision: number, home?: string, requestId: string = randomUUID()): Promise<TestingReply> {
  const params = RestoreParamsSchema.parse({ checkpoint });
  return requestSession(sessionId, "restore", params, expectedRevision, requestId, home);
}
