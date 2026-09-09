import { promises as fs } from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { sendRequest } from "./transport.js";
import { DescriptorSchema, PROTOCOL, PublicDescriptorSchema, SessionIdSchema, publicDescriptor, type PublicDescriptor, type SessionDescriptor } from "./schemas.js";

export type { PublicDescriptor };

const MAX_DESCRIPTOR_BYTES = 64 * 1024;
const MAX_DESCRIPTOR_COUNT = 256;

export class DiscoveryError extends Error {}

export function testingHome(env: NodeJS.ProcessEnv = process.env): string {
  const raw = env.REALMZ_TESTING_HOME;
  if (!raw) throw new DiscoveryError("REALMZ_TESTING_HOME is required");
  if (!path.isAbsolute(raw)) throw new DiscoveryError("REALMZ_TESTING_HOME must be an absolute path");
  return path.resolve(raw);
}

function assertHome(home: string): string {
  if (!path.isAbsolute(home)) throw new DiscoveryError("discovery root must be an absolute path");
  return path.resolve(home);
}

function rootPath(home: string): string {
  return path.resolve(home, "sessions");
}

function descriptorPath(home: string, sessionId: string): string {
  const safeId = SessionIdSchema.parse(sessionId);
  const root = rootPath(home);
  const target = path.resolve(root, `${safeId}.json`);
  if (path.relative(root, target).startsWith("..") || path.isAbsolute(path.relative(root, target))) throw new DiscoveryError("descriptor path escaped discovery root");
  return target;
}

async function readDescriptor(file: string): Promise<SessionDescriptor | null> {
  try {
    const stat = await fs.lstat(file);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > MAX_DESCRIPTOR_BYTES) return null;
    const parsed: unknown = JSON.parse(await fs.readFile(file, "utf8"));
    const result = DescriptorSchema.safeParse(parsed);
    return result.success ? result.data : null;
  } catch { return null; }
}

function identityMatches(descriptor: SessionDescriptor, result: Record<string, unknown>): boolean {
  const parsed = PublicDescriptorSchema.safeParse(result);
  if (!parsed.success) return false;
  return JSON.stringify(parsed.data) === JSON.stringify(publicDescriptor(descriptor));
}

export async function probeDescriptor(descriptor: SessionDescriptor, timeoutMs = 1000): Promise<PublicDescriptor | null> {
  try {
    const reply = await sendRequest(descriptor.port, {
      protocol: PROTOCOL,
      sessionId: descriptor.sessionId,
      token: descriptor.token,
      requestId: `describe-${randomUUID()}`,
      expectedRevision: null,
      command: "describe",
      params: {}
    }, timeoutMs);
    if (!reply.ok || reply.result === null || reply.sessionId !== descriptor.sessionId || !identityMatches(descriptor, reply.result)) return null;
    return publicDescriptor(descriptor);
  } catch { return null; }
}

export async function discoverSessions(home = testingHome()): Promise<PublicDescriptor[]> {
  home = assertHome(home);
  const root = rootPath(home);
  let entries;
  try { entries = await fs.readdir(root, { withFileTypes: true }); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw error;
  }
  const descriptors: SessionDescriptor[] = [];
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name)).slice(0, MAX_DESCRIPTOR_COUNT)) {
    if (!entry.isFile() || !entry.name.endsWith(".json")) continue;
    const descriptor = await readDescriptor(path.resolve(root, entry.name));
    if (descriptor === null || path.basename(entry.name, ".json") !== descriptor.sessionId) continue;
    descriptors.push(descriptor);
  }
  const live = await Promise.all(descriptors.map((descriptor) => probeDescriptor(descriptor)));
  return live.filter((value): value is PublicDescriptor => value !== null);
}

export async function discoverSession(sessionId: string, home = testingHome()): Promise<SessionDescriptor> {
  home = assertHome(home);
  const descriptor = await readDescriptor(descriptorPath(home, sessionId));
  if (descriptor === null || descriptor.sessionId !== sessionId) throw new DiscoveryError("session descriptor is missing or invalid");
  const live = await probeDescriptor(descriptor);
  if (live === null) throw new DiscoveryError("session is stale or failed authentication");
  return descriptor;
}

export async function writeDescriptor(home: string, descriptor: SessionDescriptor): Promise<void> {
  home = assertHome(home);
  DescriptorSchema.parse(descriptor);
  const root = rootPath(home);
  await fs.mkdir(root, { recursive: true });
  await fs.writeFile(descriptorPath(home, descriptor.sessionId), `${JSON.stringify(descriptor, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
}

export async function removeDescriptor(home: string, sessionId: string): Promise<void> {
  home = assertHome(home);
  try { await fs.unlink(descriptorPath(home, sessionId)); }
  catch (error) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
}
