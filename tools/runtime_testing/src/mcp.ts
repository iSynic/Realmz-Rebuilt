import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
import path from "node:path";
import { McpServer } from "@modelcontextprotocol/server";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import * as z from "zod/v4";
import { discoverSessions, requestSession } from "./client.js";
import { CastleFixtureManager, castleFixtureEnvironment } from "./castle-fixtures.js";
import { checkpointFixture, FixtureManager, fixtureEnvironment, restoreFixture } from "./fixtures.js";
import { cancelJourney, compactJourneyStatus, readStatus, startJourney } from "./journeys.js";
import { compareJourneyRuns } from "./comparison.js";
import { FixtureClassicSourceSchema, JourneySpecSchema, SessionIdSchema } from "./schemas.js";

const EmptyArgs = z.object({}).strict();
const RequestId = z.string().min(1).max(128).optional();
const SessionArgs = z.object({ sessionId: SessionIdSchema, params: z.record(z.string(), z.unknown()).default({}), requestId: RequestId }).strict();
const FixtureCreateArgs = z.object({ operation: z.literal("create"), engine: z.literal("rebuilt"), packagePath: z.string().min(1), source: FixtureClassicSourceSchema }).strict();
const CastleFixtureCreateArgs = z.object({ operation: z.literal("create"), engine: z.literal("castle"), recipe: z.literal("native-griloch-starters").optional(), source: FixtureClassicSourceSchema }).strict();
const FixtureCloneArgs = z.object({ operation: z.literal("clone"), engine: z.literal("rebuilt"), packagePath: z.string().min(1), checkpointPath: z.string().min(1) }).strict();
const FixtureSessionArgs = z.object({ operation: z.enum(["checkpoint", "restore", "close", "capture"]), sessionId: SessionIdSchema, params: z.record(z.string(), z.unknown()).default({}), checkpoint: z.record(z.string(), z.unknown()).optional(), expectedRevision: z.number().int().nonnegative().safe().optional(), requestId: RequestId }).strict();
const FixtureArgs = z.union([FixtureCreateArgs, CastleFixtureCreateArgs, FixtureCloneArgs, FixtureSessionArgs]);
const CommandArgs = z.object({ sessionId: SessionIdSchema, params: z.record(z.string(), z.unknown()), expectedRevision: z.number().int().nonnegative().safe(), requestId: RequestId }).strict();
const CaptureArgs = z.object({ sessionId: SessionIdSchema, requestId: RequestId }).strict();
const JourneyArgs = z.union([
  z.object({ operation: z.literal("start"), spec: JourneySpecSchema }).strict(),
  z.object({ operation: z.literal("status"), jobId: z.string().regex(/^[a-f0-9]{32}$/) }).strict(),
  z.object({ operation: z.literal("cancel"), jobId: z.string().regex(/^[a-f0-9]{32}$/) }).strict()
]);
const CompareArgs = z.object({ leftPath: z.string().min(1).refine((value) => path.isAbsolute(value), "leftPath must be absolute"), rightPath: z.string().min(1).refine((value) => path.isAbsolute(value), "rightPath must be absolute") }).strict();

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
  for (const command of ["act", "respond", "ui", "invoke"] as const) {
    server.registerTool(`realmz_${command}`, { description: `Submit one validated ${command} command to an isolated fixture.`, inputSchema: CommandArgs, annotations: { readOnlyHint: false, openWorldHint: false } }, async ({ sessionId, params, expectedRevision, requestId }) => {
      try {
        const reply = await requestSession(sessionId, command, params, expectedRevision, requestId ?? randomUUID());
        return result(reply, !reply.ok);
      } catch (error) { return result({ code: "transport_error", message: error instanceof Error ? error.message : `${command} failed` }, true); }
    });
  }
  server.registerTool("realmz_capture", { description: "Capture the current rendered frame from an isolated fixture.", inputSchema: CaptureArgs, annotations: { readOnlyHint: true, openWorldHint: false } }, async ({ sessionId, requestId }) => {
    try {
      const reply = await requestSession(sessionId, "capture", {}, null, requestId ?? randomUUID());
      return result(reply, !reply.ok);
    } catch (error) { return result({ code: "transport_error", message: error instanceof Error ? error.message : "capture failed" }, true); }
  });
  server.registerTool("realmz_journey", { description: "Start, inspect, or cancel a persistent asynchronous fixture journey.", inputSchema: JourneyArgs, annotations: { readOnlyHint: false, openWorldHint: false } }, async (args) => {
    try {
      if (args.operation === "start") return result(await startJourney(args.spec, process.env.REALMZ_TESTING_HOME));
      if (args.operation === "status") return result(compactJourneyStatus(await readStatus(args.jobId, process.env.REALMZ_TESTING_HOME)));
      return result(await cancelJourney(args.jobId, process.env.REALMZ_TESTING_HOME));
    } catch (error) { return result({ code: error instanceof Error && "code" in error ? (error as { code: string }).code : "journey_error", message: error instanceof Error ? error.message : "journey operation failed" }, true); }
  });
  server.registerTool("realmz_compare", { description: "Compare two saved journey evidence files by normalized semantic outcomes and report the first difference.", inputSchema: CompareArgs, annotations: { readOnlyHint: true, openWorldHint: false } }, async ({ leftPath, rightPath }) => {
    try { return result(await compareJourneyRuns(leftPath, rightPath)); }
    catch (error) { return result({ code: "compare_error", message: error instanceof Error ? error.message : "journey comparison failed" }, true); }
  });
  server.registerTool("realmz_fixture", { description: "Create or clone an isolated fixture, or run its checkpoint, restore, close, and capture operations.", inputSchema: FixtureArgs, annotations: { readOnlyHint: false, openWorldHint: false } }, async (args) => {
    try {
      if (args.operation === "create" && args.engine === "castle") {
        const castleManager = new CastleFixtureManager(castleFixtureEnvironment());
        return result(args.recipe === undefined ? await castleManager.create({ engine: "castle", source: args.source }) : await castleManager.create({ engine: "castle", recipe: args.recipe, source: args.source }));
      }
      if (args.operation === "create" && args.engine === "rebuilt") return result(await new FixtureManager(fixtureEnvironment()).create(args));
      if (args.operation === "clone") return result(await new FixtureManager(fixtureEnvironment()).clone(args));
      if (args.operation === "checkpoint") return result(await checkpointFixture(args.sessionId, process.env.REALMZ_TESTING_HOME, args.requestId ?? randomUUID()));
      if (args.operation === "restore") {
        if (args.expectedRevision === undefined || args.checkpoint === undefined) return result({ code: "invalid_fixture_args", message: "restore requires checkpoint and expectedRevision" }, true);
        return result(await restoreFixture(args.sessionId, args.checkpoint, args.expectedRevision, process.env.REALMZ_TESTING_HOME, args.requestId ?? randomUUID()));
      }
      if (args.operation === "close") {
        if (args.expectedRevision === undefined) return result({ code: "invalid_fixture_args", message: "close requires expectedRevision" }, true);
        return result(await requestSession(args.sessionId, "close", {}, args.expectedRevision, args.requestId ?? randomUUID()));
      }
      return result(await requestSession(args.sessionId, "capture", args.params, null, args.requestId ?? randomUUID()));
    } catch (error) { return result({ code: error instanceof Error && "code" in error ? (error as FixtureErrorLike).code : "transport_error", message: error instanceof Error ? error.message : "fixture operation failed" }, true); }
  });
  return server;
}

type FixtureErrorLike = { code: string };

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  void serveStdio(createServer);
}
