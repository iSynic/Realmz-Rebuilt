import { createHash, randomBytes, randomUUID } from "node:crypto";
import { execFile as execFileCallback, spawn } from "node:child_process";
import { closeSync, openSync, promises as fs } from "node:fs";
import path from "node:path";
import { promisify } from "node:util";
import { discoverSessions } from "./discovery.js";
import { requestSession } from "./client.js";
import { FixtureError, type ClassicStartersSource, type FixtureHandle, type FixtureLauncher, type FixtureProcessHandle } from "./fixtures.js";
import { CastleFixtureConfigSchema, FixtureIdSchema, PROTOCOL, type PublicDescriptor } from "./schemas.js";

const execFile = promisify(execFileCallback);
const BASE_COMMIT = "491816ad60037394f92c428e99c004494d3c28b3";
const RECIPE = "native-griloch-starters" as const;
const MAP_ID = "land:0";
const DEFAULT_X = 7;
const DEFAULT_Y = 20;
const MAX_SOURCE_ENTRIES = 4096;
const MAX_SOURCE_BYTES = 32 * 1024 * 1024;
const MAX_SOURCE_FILE_BYTES = 8 * 1024 * 1024;
const STARTER_NAMES = ["Kevlar", "Lothlorian", "Silver Leaf", "Traskelion", "Trevor", "Vormale"] as const;
const DEFAULT_TIMEOUT_MS = 30_000;

export interface CastleFixtureEnvironment {
  testingHome: string;
  castlePath: string;
  castleRoot: string;
  rebuiltRoot: string;
}

export interface CastleFixtureCreateInput {
  engine: "castle";
  recipe?: typeof RECIPE;
  source: ClassicStartersSource;
}

export interface CastleFixtureLaunchRequest {
  castlePath: string;
  castleRoot: string;
  args: string[];
  fixtureRoot: string;
  configPath: string;
  stdoutLogPath: string;
  testingHome: string;
}

export type CastleFixtureLauncher = (request: CastleFixtureLaunchRequest) => Promise<FixtureProcessHandle> | FixtureProcessHandle;

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
  let current = root;
  const relative = path.relative(root, target);
  for (const component of relative === "" ? [] : relative.split(path.sep)) {
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

export function castleFixtureEnvironment(env: NodeJS.ProcessEnv = process.env): CastleFixtureEnvironment {
  return {
    testingHome: absolute(env.REALMZ_TESTING_HOME ?? "", "REALMZ_TESTING_HOME"),
    castlePath: absolute(env.REALMZ_CASTLE_PATH ?? "", "REALMZ_CASTLE_PATH"),
    castleRoot: absolute(env.REALMZ_CASTLE_ROOT ?? "", "REALMZ_CASTLE_ROOT"),
    rebuiltRoot: absolute(env.REALMZ_REBUILT_ROOT ?? "", "REALMZ_REBUILT_ROOT")
  };
}

async function gitOutput(root: string, args: string[], maxBuffer = MAX_SOURCE_BYTES): Promise<string> {
  try {
    return (await execFile("git", ["-C", root, ...args], { maxBuffer })).stdout;
  } catch (error) {
    if (error instanceof Error && /maxBuffer/i.test(error.message)) throw new FixtureError("source_too_large", "the Castle instrumentation source exceeds the fixture fingerprint bound");
    throw error;
  }
}

async function gitHead(root: string): Promise<string> {
  try {
    const head = (await gitOutput(root, ["rev-parse", "HEAD"])).trim();
    if (!/^[0-9a-f]{40}$/.test(head)) throw new Error("invalid git HEAD");
    return head;
  } catch {
    throw new FixtureError("castle_source_unversioned", "REALMZ_CASTLE_ROOT must be a Git checkout with a resolvable 40-hex HEAD");
  }
}

async function assertBaseCommit(root: string): Promise<string> {
  const head = await gitHead(root);
  try {
    await gitOutput(root, ["merge-base", "--is-ancestor", BASE_COMMIT, head], 4096);
  } catch {
    throw new FixtureError("castle_base_mismatch", `Castle instrumentation must retain base commit ${BASE_COMMIT} as an ancestor`);
  }
  return head;
}

async function sourceFingerprint(root: string, head: string): Promise<string> {
  // The checkout also contains the native install tree; it is runtime output,
  // not instrumentation provenance. Fingerprint source and build inputs only.
  const relevant = ["CMakeLists.txt", "CMakePresets.json", "src"];
  const diff = await gitOutput(root, ["diff", "--binary", "HEAD", "--", ...relevant]);
  const untracked = await gitOutput(root, ["ls-files", "--others", "--exclude-standard", "-z", "--", ...relevant]);
  const paths = untracked.split("\0").filter(Boolean).sort();
  if (paths.length > MAX_SOURCE_ENTRIES) throw new FixtureError("source_too_large", "too many dirty Castle instrumentation entries");
  let total = Buffer.byteLength(diff, "utf8");
  if (total > MAX_SOURCE_BYTES) throw new FixtureError("source_too_large", "dirty Castle instrumentation source exceeds the fingerprint bound");
  const material: string[] = [diff];
  for (const relative of paths) {
    const file = path.resolve(root, relative);
    if (!contained(root, file)) throw new FixtureError("invalid_path", "Git reported a Castle source path outside REALMZ_CASTLE_ROOT");
    const stat = await fs.lstat(file).catch(() => null);
    if (stat?.isFile() && !stat.isSymbolicLink()) {
      if (stat.size > MAX_SOURCE_FILE_BYTES || total + stat.size > MAX_SOURCE_BYTES) throw new FixtureError("source_too_large", "dirty Castle instrumentation source exceeds the fingerprint bound");
      total += stat.size;
      material.push(relative, await sha256File(file));
    } else {
      material.push(relative, "non-regular");
    }
  }
  return total === 0 && paths.length === 0 ? `git:${head};clean` : `git:${head};dirty:${sha256Bytes(Buffer.from(material.join("\n"), "utf8"))}`;
}

async function pinnedCharacterHashes(root: string): Promise<Map<string, string>> {
  const metadata = path.join(root, "tools", "fixtures", "classic-character-files", "README.md");
  const result = new Map<string, string>();
  const text = await fs.readFile(metadata, "utf8").catch(() => "");
  for (const match of text.matchAll(/^\|\s*([^|]+?)\s*\|\s*`([0-9a-f]{64})`\s*\|\s*$/gim)) result.set(match[1]!.trim(), match[2]!.toLowerCase());
  return result;
}

async function prepareCharacters(rebuiltRoot: string, fixtureRootPath: string): Promise<Array<{ name: string; sha256: string }>> {
  const sourceRoot = path.join(rebuiltRoot, "tools", "fixtures", "classic-character-files", "7.1.2");
  const expected = await pinnedCharacterHashes(rebuiltRoot);
  if (STARTER_NAMES.some((name) => !expected.has(name))) throw new FixtureError("starter_provenance_missing", "all six Character Files require pinned source hashes");
  const targetRoot = path.join(fixtureRootPath, "userdata", "Character Files");
  await makeSafeDirectory(fixtureRootPath, targetRoot, "Castle Character Files directory");
  const characters: Array<{ name: string; sha256: string }> = [];
  for (const name of STARTER_NAMES) {
    const source = path.join(sourceRoot, name);
    await regularFile(source, `starter character ${name}`);
    const stat = await fs.stat(source);
    if (stat.size !== 872) throw new FixtureError("starter_source_mismatch", `${name} is not the pinned 872-byte Realmz 7.1.2 Character File`);
    const sha256 = await sha256File(source);
    const pinned = expected.get(name);
    if (pinned !== sha256) throw new FixtureError("starter_source_mismatch", `${name} does not match its pinned Character File hash`);
    await fs.copyFile(source, path.join(targetRoot, name));
    characters.push({ name, sha256 });
  }
  return characters;
}

interface ScenarioFile {
  name: string;
  sha256: string;
}

async function regularFiles(root: string, current = root): Promise<string[]> {
  const entries = await fs.readdir(current, { withFileTypes: true }).catch(() => { throw new FixtureError("castle_scenario_missing", `Castle scenario directory is unavailable: ${root}`); });
  const files: string[] = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    const full = path.join(current, entry.name);
    if (entry.isSymbolicLink()) throw new FixtureError("invalid_path", `Castle scenario contains a symbolic link: ${entry.name}`);
    if (entry.isDirectory()) files.push(...await regularFiles(root, full));
    else if (entry.isFile()) files.push(full);
    else throw new FixtureError("invalid_path", `Castle scenario contains a non-regular entry: ${entry.name}`);
  }
  return files;
}

async function validateScenario(castlePath: string, castleRoot: string): Promise<ScenarioFile[]> {
  const installed = path.join(path.dirname(castlePath), "Scenarios", "Grilochs Revenge");
  const source = path.join(castleRoot, "base", "Realmz", "Scenarios", "Grilochs Revenge");
  await directory(installed, "installed Grilochs Revenge scenario");
  await directory(source, "Castle checkout Grilochs Revenge scenario");
  const installedFiles = await regularFiles(installed);
  const sourceFiles = await regularFiles(source);
  const installedByName = new Map(installedFiles.map((file) => [path.relative(installed, file).split(path.sep).join("/"), file]));
  const sourceByName = new Map(sourceFiles.map((file) => [path.relative(source, file).split(path.sep).join("/"), file]));
  if (installedByName.size !== sourceByName.size || [...installedByName.keys()].some((name) => !sourceByName.has(name))) throw new FixtureError("castle_scenario_mismatch", "installed Grilochs Revenge files do not match the pinned Castle checkout");
  const files: ScenarioFile[] = [];
  for (const name of [...sourceByName.keys()].sort()) {
    const installedFile = installedByName.get(name)!;
    const sourceFile = sourceByName.get(name)!;
    const [installedBytes, sourceBytes] = await Promise.all([fs.readFile(installedFile), fs.readFile(sourceFile)]);
    if (!installedBytes.equals(sourceBytes)) throw new FixtureError("castle_scenario_mismatch", `installed Grilochs Revenge file differs: ${name}`);
    files.push({ name, sha256: sha256Bytes(installedBytes) });
  }
  return files;
}

async function prepareRoot(home: string, fixtureId: string): Promise<string> {
  await fs.mkdir(home, { recursive: true });
  await directory(home, "REALMZ_TESTING_HOME");
  const fixtures = path.resolve(home, "fixtures");
  await makeSafeDirectory(home, fixtures, "fixture discovery root");
  const root = fixtureRoot(home, fixtureId);
  await assertNoSymlinkAncestors(home, root, "Castle fixture scratch root");
  await fs.mkdir(root, { recursive: false });
  await assertNoSymlinkAncestors(home, root, "Castle fixture scratch root");
  return root;
}

async function defaultCastleLauncher(request: CastleFixtureLaunchRequest): Promise<FixtureProcessHandle> {
  const stdoutFd = openSync(request.stdoutLogPath, "a");
  try {
    const child = spawn(request.castlePath, request.args, {
      cwd: request.fixtureRoot,
      windowsHide: true,
      detached: true,
      shell: false,
      env: { ...process.env, REALMZ_CASTLE_TEST_CONFIG: request.configPath, REALMZ_TESTING_HOME: request.testingHome },
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

function validateSource(source: ClassicStartersSource, recipe: string | undefined): void {
  if (recipe !== undefined && recipe !== RECIPE) throw new FixtureError("unsupported_recipe", `Castle fixture recipe must be ${RECIPE}`);
  if (source.kind !== "classic-starters" || source.location.mapId !== MAP_ID || !Number.isSafeInteger(source.seed) || source.seed < 1 || source.seed > 2_147_483_646 || !Number.isSafeInteger(source.location.x) || ![7, 8].includes(source.location.x) || source.location.y !== DEFAULT_Y) {
    throw new FixtureError("invalid_source", "Castle supports only classic-starters on Grilochs Revenge land:0 at x=7 (or direct-baseline x=8), y=20");
  }
}

export class CastleFixtureManager {
  constructor(private readonly env: CastleFixtureEnvironment = castleFixtureEnvironment(), private readonly launcher: CastleFixtureLauncher = defaultCastleLauncher) {}

  async create(input: CastleFixtureCreateInput, timeoutMs = DEFAULT_TIMEOUT_MS, signal?: AbortSignal): Promise<FixtureHandle> {
    if (input.engine !== "castle") throw new FixtureError("unsupported_engine", "Castle fixture creation requires engine castle");
    validateSource(input.source, input.recipe);
    await directory(this.env.castleRoot, "REALMZ_CASTLE_ROOT");
    await regularFile(this.env.castlePath, "REALMZ_CASTLE_PATH");
    await directory(this.env.rebuiltRoot, "REALMZ_REBUILT_ROOT");
    const instrumentationCommit = await assertBaseCommit(this.env.castleRoot);
    const sourceFingerprintValue = await sourceFingerprint(this.env.castleRoot, instrumentationCommit);
    const executableSha256 = await sha256File(this.env.castlePath);
    const fixtureId = randomBytes(16).toString("hex");
    const root = await prepareRoot(this.env.testingHome, fixtureId);
    const configPath = path.join(root, "config.json");
    const stdoutLogPath = path.join(root, "stdout.log");
    try {
      const [characters, scenarioFiles] = await Promise.all([prepareCharacters(this.env.rebuiltRoot, root), validateScenario(this.env.castlePath, this.env.castleRoot)]);
      const config = {
        protocol: PROTOCOL,
        kind: "castle-fixture",
        fixtureId,
        scratchRoot: root,
        discoveryRoot: this.env.testingHome,
        build: `castle:${sourceFingerprintValue}`,
        seed: input.source.seed,
        location: { mapId: MAP_ID, x: input.source.location.x, y: DEFAULT_Y },
        identity: { baseCommit: BASE_COMMIT, instrumentationCommit, sourceFingerprint: sourceFingerprintValue, executableSha256, characters, scenarioFiles }
      };
      CastleFixtureConfigSchema.parse(config);
      await fs.writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
      await fs.writeFile(stdoutLogPath, "", { encoding: "utf8", mode: 0o600 });
      let process: FixtureProcessHandle;
      try {
        process = await this.launcher({ castlePath: this.env.castlePath, castleRoot: this.env.castleRoot, args: [], fixtureRoot: root, configPath, stdoutLogPath, testingHome: this.env.testingHome });
      } catch (error) {
        throw new FixtureError("fixture_start_failed", error instanceof Error ? error.message : "Castle process failed to start", root);
      }
      const descriptor = await this.waitReady(fixtureId, timeoutMs, signal);
      return { fixtureId, fixtureRoot: root, configPath, descriptor, process };
    } catch (error) {
      throw error instanceof FixtureError ? error : new FixtureError("fixture_start_failed", error instanceof Error ? error.message : "Castle fixture startup failed", root);
    }
  }

  private async waitReady(fixtureId: string, timeoutMs: number, signal?: AbortSignal): Promise<PublicDescriptor> {
    const started = Date.now();
    while (Date.now() - started <= timeoutMs) {
      const root = fixtureRoot(this.env.testingHome, fixtureId);
      if (signal?.aborted) throw new FixtureError("fixture_cancelled", "Castle fixture startup was cancelled", root);
      const descriptor = (await discoverSessions(this.env.testingHome)).find((candidate) => candidate.engine === "castle" && candidate.fixtureId === fixtureId);
      if (descriptor) {
        const reply = await requestSession(descriptor.sessionId, "observe", {}, null, `castle-fixture-ready-${randomUUID()}`, this.env.testingHome);
        const readiness = reply.ok && reply.result !== null && typeof reply.result.readiness === "object" && reply.result.readiness !== null ? reply.result.readiness as Record<string, unknown> : null;
        const fixtureError = readiness?.fixtureError;
        if (fixtureError !== null && fixtureError !== undefined && typeof fixtureError === "object" && !Array.isArray(fixtureError)) {
          const errorFields = fixtureError as Record<string, unknown>;
          const code = typeof errorFields.code === "string" && errorFields.code.length > 0 ? errorFields.code : "fixture_not_ready";
          const message = typeof errorFields.message === "string" && errorFields.message.length > 0 ? errorFields.message : "Castle fixture preparation failed";
          throw new FixtureError(code, message, root);
        }
        if (readiness?.fixtureReady === true && readiness.semanticReady === true && readiness.visualReady === true) return descriptor;
      }
      await new Promise((resolve) => setTimeout(resolve, 100));
    }
    throw new FixtureError("fixture_timeout", "Castle fixture readiness timed out; scratch artifacts were retained", fixtureRoot(this.env.testingHome, fixtureId));
  }
}

export { BASE_COMMIT as CASTLE_BASE_COMMIT, DEFAULT_X as CASTLE_DEFAULT_X, DEFAULT_Y as CASTLE_DEFAULT_Y, MAP_ID as CASTLE_MAP_ID, RECIPE as CASTLE_RECIPE };
