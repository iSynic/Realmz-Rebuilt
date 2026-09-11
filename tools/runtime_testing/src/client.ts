import { randomUUID } from "node:crypto";
import { discoverSession, discoverSessions } from "./discovery.js";
import { PROTOCOL, isMutatingCommand, type TestingReply, type AllowedCommand } from "./schemas.js";
import { sendRequest } from "./transport.js";

export { discoverSession, discoverSessions };

export async function requestSession(sessionId: string, command: AllowedCommand, params: Record<string, unknown> = {}, expectedRevision: number | null = null, requestId: string = randomUUID(), home?: string): Promise<TestingReply> {
  const descriptor = await discoverSession(sessionId, home);
  if (isMutatingCommand(command) && expectedRevision === null) throw new Error("mutating commands require expectedRevision");
  if (isMutatingCommand(command) && descriptor.access === "observe") throw new Error("observe sessions reject mutating commands");
  if (command !== "describe" && !descriptor.capabilities.includes(command)) throw new Error(`session does not advertise capability: ${command}`);
  return sendRequest(descriptor.port, { protocol: PROTOCOL, sessionId: descriptor.sessionId, token: descriptor.token, requestId, expectedRevision, command, params });
}
