import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import * as z from "zod/v4";
import { discoverSessions, requestSession } from "./client.js";
import { SessionIdSchema } from "./schemas.js";

const EmptyArgs = z.object({}).strict();
const RequestId = z.string().min(1).max(128).optional();
const SessionArgs = z.object({ sessionId: SessionIdSchema, params: z.record(z.string(), z.unknown()).default({}), requestId: RequestId }).strict();
const FixtureArgs = z.object({ sessionId: SessionIdSchema, operation: z.string().min(1).max(128), params: z.record(z.string(), z.unknown()).default({}), requestId: RequestId }).strict();

function result(value: unknown, isError = false) {
  return { content: [{ type: "text" as const, text: JSON.stringify(value) }], ...(isError ? { isError: true } : {}) };
}

export function createServer(): McpServer {
  const server = new McpServer({ name: "realmz-runtime-testing", version: "0.1.0" }, {
    instructions: "Discover enabled sessions first. Live adventures permit observation and validated checkpoint export only. Automated actions require isolated fixtures. Preserve ordinary gameplay, actual UI input, and direct invocation as distinct proof modes; direct execution does not prove normal trigger eligibility. Retry uncertain requests only with the identical request ID and payload. Unsupported capabilities or unexplained differences never establish parity."
  });
  server.registerTool("realmz_sessions", { description: "List live locally discovered Realmz testing sessions.", inputSchema: EmptyArgs, annotations: { readOnlyHint: true, openWorldHint: false } }, async () => {
    try { return result(await discoverSessions()); }
    catch (error) { return result({ code: "discovery_error", message: error instanceof Error ? error.message : "session discovery failed" }, true); }
  });
  server.registerTool("realmz_observe", { description: "Observe a live Realmz testing session.", inputSchema: SessionArgs, annotations: { readOnlyHint: true, openWorldHint: false } }, async ({ sessionId, params, requestId }) => {
    try {
      const reply = await requestSession(sessionId, "observe", params, null, requestId ?? randomUUID());
      return result(reply, !reply.ok);
    } catch (error) { return result({ code: "transport_error", message: error instanceof Error ? error.message : "observation failed" }, true); }
  });
  server.registerTool("realmz_fixture", { description: "Run the supported checkpoint fixture operation for a live Realmz testing session.", inputSchema: FixtureArgs, annotations: { readOnlyHint: true, openWorldHint: false } }, async ({ sessionId, operation, params, requestId }) => {
    if (operation !== "checkpoint") return result({ code: "unsupported_operation", message: `fixture operation is not supported: ${operation}` }, true);
    try {
      const reply = await requestSession(sessionId, "checkpoint", params, null, requestId ?? randomUUID());
      return result(reply, !reply.ok);
    } catch (error) { return result({ code: "transport_error", message: error instanceof Error ? error.message : "fixture operation failed" }, true); }
  });
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  void serveStdio(createServer);
}
