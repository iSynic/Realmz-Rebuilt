#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import { discoverSessions, requestSession } from "./client.js";
import { CastleFixtureManager, castleFixtureEnvironment } from "./castle-fixtures.js";
import { checkpointFixture, FixtureManager, fixtureEnvironment, restoreFixture } from "./fixtures.js";
import { cancelJourney, compactJourneyStatus, readStatus, startJourney } from "./journeys.js";
import { compareJourneyRuns } from "./comparison.js";
import { ALLOWED_COMMANDS, isMutatingCommand, type AllowedCommand } from "./schemas.js";

function usage(): never {
  console.error("Usage: realmz-testing sessions | create ... | clone ... | observe|capture|act|respond|ui|invoke --session ID --params JSON --expected-revision N [--request-id ID] | checkpoint ... | restore ... | close ... | journey-start --spec JSON | journey-status --job ID | journey-cancel --job ID | compare --left P --right P");
  process.exit(2);
  throw new Error("unreachable");
}

function parseFlags(args: string[], allowed: readonly string[]): Map<string, string> {
  const values = new Map<string, string>();
  for (let index = 0; index < args.length; index += 2) {
    const name = args[index];
    const value = args[index + 1];
    if (!name || !allowed.includes(name) || value === undefined || value.startsWith("--")) throw new Error(`unsupported or incomplete flag: ${name ?? ""}`);
    if (values.has(name)) throw new Error(`duplicate flag: ${name}`);
    values.set(name, value);
  }
  return values;
}

function params(flags: Map<string, string>): Record<string, unknown> {
  const raw = flags.get("--params");
  if (!raw) return {};
  const value: unknown = JSON.parse(raw);
  if (value === null || typeof value !== "object" || Array.isArray(value)) throw new Error("--params must be a JSON object");
  return value as Record<string, unknown>;
}

async function main(): Promise<void> {
  const [operation, ...args] = process.argv.slice(2);
  if (!operation) usage();
  if (operation === "sessions") {
    if (args.length !== 0) throw new Error("sessions does not accept flags");
    console.log(JSON.stringify(await discoverSessions(), null, 2));
    return;
  }
  if (operation === "create" || operation === "clone") {
    const flags = parseFlags(args, operation === "create" ? ["--engine", "--package-path", "--recipe", "--source", "--seed", "--map-id", "--x", "--y"] : ["--engine", "--package-path", "--checkpoint-path"]);
    const engine = flags.get("--engine");
    if (engine === "castle") {
      if (operation !== "create") throw new Error("Castle does not support checkpoint cloning");
      if (flags.has("--package-path")) throw new Error("--package-path is not valid for Castle fixtures");
      if (flags.get("--source") !== "classic-starters") throw new Error("--source must be classic-starters");
      const castleInput = {
        engine: "castle",
        source: { kind: "classic-starters", seed: integerFlag(flags, "--seed"), location: { mapId: requiredFlag(flags, "--map-id"), x: integerFlag(flags, "--x"), y: integerFlag(flags, "--y") } }
      } as const;
      const recipe = flags.get("--recipe");
      if (recipe !== undefined && recipe !== "native-griloch-starters") throw new Error("--recipe must be native-griloch-starters");
      const handle = await new CastleFixtureManager(castleFixtureEnvironment()).create(recipe === undefined ? castleInput : { ...castleInput, recipe: "native-griloch-starters" });
      console.log(JSON.stringify(handle, null, 2));
      return;
    }
    if (engine !== "rebuilt") throw new Error("--engine must be rebuilt or castle");
    const packagePath = flags.get("--package-path");
    if (!packagePath) throw new Error("--package-path is required");
    const manager = new FixtureManager(fixtureEnvironment());
    if (operation === "create" && flags.get("--source") !== "classic-starters") throw new Error("--source must be classic-starters");
    const handle = operation === "create"
      ? await manager.create({ engine: "rebuilt", packagePath, source: { kind: "classic-starters", seed: integerFlag(flags, "--seed"), location: { mapId: requiredFlag(flags, "--map-id"), x: integerFlag(flags, "--x"), y: integerFlag(flags, "--y") } } })
      : await manager.clone({ engine: "rebuilt", packagePath, checkpointPath: requiredFlag(flags, "--checkpoint-path") });
    console.log(JSON.stringify(handle, null, 2));
    return;
  }
  if (operation === "journey-start") {
    const flags = parseFlags(args, ["--spec"]);
    console.log(JSON.stringify(await startJourney(parseObject(flags.get("--spec"), "--spec"), process.env.REALMZ_TESTING_HOME), null, 2));
    return;
  }
  if (operation === "journey-status" || operation === "journey-cancel") {
    const flags = parseFlags(args, ["--job"]);
    const jobId = requiredFlag(flags, "--job");
    const value = operation === "journey-status" ? compactJourneyStatus(await readStatus(jobId, process.env.REALMZ_TESTING_HOME)) : await cancelJourney(jobId, process.env.REALMZ_TESTING_HOME);
    console.log(JSON.stringify(value, null, 2));
    return;
  }
  if (operation === "compare") {
    const flags = parseFlags(args, ["--left", "--right"]);
    console.log(JSON.stringify(await compareJourneyRuns(requiredFlag(flags, "--left"), requiredFlag(flags, "--right")), null, 2));
    return;
  }
  const allowedFlags = ["act", "respond", "ui", "invoke"].includes(operation) ? ["--session", "--params", "--expected-revision", "--request-id"] : operation === "observe" || operation === "capture" ? ["--session", "--params", "--request-id"] : operation === "checkpoint" ? ["--session", "--request-id"] : operation === "restore" ? ["--session", "--checkpoint", "--expected-revision", "--request-id"] : operation === "close" ? ["--session", "--expected-revision", "--request-id"] : operation === "request" ? ["--session", "--command", "--params", "--expected-revision", "--request-id"] : [];
  const flags = parseFlags(args, allowedFlags);
  const sessionId = flags.get("--session");
  if (!sessionId) usage();
  const command = operation === "observe" ? "observe" : operation === "capture" ? "capture" : ["act", "respond", "ui", "invoke"].includes(operation) ? operation : operation === "checkpoint" ? "checkpoint" : operation === "restore" ? "restore" : operation === "close" ? "close" : operation === "request" ? flags.get("--command") : undefined;
  if (!command || !(ALLOWED_COMMANDS as readonly string[]).includes(command)) throw new Error(`unsupported command: ${command ?? ""}`);
  const expectedRaw = flags.get("--expected-revision");
  const expected = expectedRaw === undefined ? null : Number(expectedRaw);
  if (expected !== null && !Number.isSafeInteger(expected)) throw new Error("--expected-revision must be a safe integer");
  if (isMutatingCommand(command) && expected === null) throw new Error("mutating commands require --expected-revision");
  const reply = operation === "checkpoint"
    ? await checkpointFixture(sessionId, process.env.REALMZ_TESTING_HOME, flags.get("--request-id") ?? randomUUID())
    : operation === "restore"
      ? await restoreFixture(sessionId, parseObject(flags.get("--checkpoint"), "--checkpoint"), expected!, process.env.REALMZ_TESTING_HOME, flags.get("--request-id") ?? randomUUID())
      : await requestSession(sessionId, command as AllowedCommand, params(flags), expected, flags.get("--request-id") ?? randomUUID());
  console.log(JSON.stringify(reply, null, 2));
  if (!reply.ok) process.exitCode = 1;
}

function requiredFlag(flags: Map<string, string>, name: string): string {
  const value = flags.get(name);
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function integerFlag(flags: Map<string, string>, name: string): number {
  const value = Number(requiredFlag(flags, name));
  if (!Number.isSafeInteger(value)) throw new Error(`${name} must be a safe integer`);
  return value;
}

function parseObject(value: string | undefined, name: string): Record<string, unknown> {
  if (!value) throw new Error(`${name} is required`);
  const parsed: unknown = JSON.parse(value);
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error(`${name} must be a JSON object`);
  return parsed as Record<string, unknown>;
}

main().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; });
