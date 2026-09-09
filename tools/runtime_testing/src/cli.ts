#!/usr/bin/env node
import { randomUUID } from "node:crypto";
import { discoverSessions, requestSession } from "./client.js";
import { ALLOWED_COMMANDS, isMutatingCommand, type AllowedCommand } from "./schemas.js";

function usage(): never {
  console.error("Usage: realmz-testing sessions | observe --session ID [--params JSON] | checkpoint --session ID [--params JSON] | request --session ID --command COMMAND [--params JSON] [--expected-revision N] [--request-id ID]");
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
  const allowedFlags = operation === "observe" || operation === "checkpoint" ? ["--session", "--params", "--request-id"] : operation === "request" ? ["--session", "--command", "--params", "--expected-revision", "--request-id"] : [];
  const flags = parseFlags(args, allowedFlags);
  const sessionId = flags.get("--session");
  if (!sessionId) usage();
  const command = operation === "observe" ? "observe" : operation === "checkpoint" ? "checkpoint" : operation === "request" ? flags.get("--command") : undefined;
  if (!command || !(ALLOWED_COMMANDS as readonly string[]).includes(command)) throw new Error(`unsupported command: ${command ?? ""}`);
  const expectedRaw = flags.get("--expected-revision");
  const expected = expectedRaw === undefined ? null : Number(expectedRaw);
  if (expected !== null && !Number.isSafeInteger(expected)) throw new Error("--expected-revision must be a safe integer");
  if (isMutatingCommand(command) && expected === null) throw new Error("mutating commands require --expected-revision");
  const reply = await requestSession(sessionId, command as AllowedCommand, params(flags), expected, flags.get("--request-id") ?? randomUUID());
  console.log(JSON.stringify(reply, null, 2));
  if (!reply.ok) process.exitCode = 1;
}

main().catch((error) => { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; });
