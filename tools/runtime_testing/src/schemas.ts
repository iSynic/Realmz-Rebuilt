import * as z from "zod/v4";
import path from "node:path";

export const PROTOCOL = "realmz-testing/1" as const;
export const MAX_MESSAGE_BYTES = 16 * 1024 * 1024;

export const SessionIdSchema = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/);
export const FixtureIdSchema = z.string().regex(/^[a-f0-9]{32}$/);
const AbsolutePathSchema = z.string().min(1).refine((value) => path.isAbsolute(value), "path must be absolute");
const Sha256Schema = z.string().regex(/^[a-f0-9]{64}$/);
const NonEmptyString = z.string().min(1).max(4096);
const RequestIdString = z.string().min(1).max(128);

export const RequestSchema = z.object({
  protocol: z.literal(PROTOCOL),
  sessionId: SessionIdSchema,
  token: NonEmptyString,
  requestId: RequestIdString,
  expectedRevision: z.number().int().nonnegative().safe().nullable(),
  command: z.string().min(1).max(128),
  params: z.record(z.string(), z.unknown())
}).strict();
export type TestingRequest = z.infer<typeof RequestSchema>;

export const ErrorSchema = z.object({
  code: z.string().min(1).max(128),
  message: z.string().min(1).max(4096)
}).strict();

export const ReplySchema = z.object({
  protocol: z.literal(PROTOCOL),
  sessionId: SessionIdSchema,
  requestId: RequestIdString,
  revision: z.number().int().nonnegative().safe(),
  ok: z.boolean(),
  result: z.record(z.string(), z.unknown()).nullable(),
  error: ErrorSchema.nullable()
}).strict().superRefine((value, ctx) => {
  if (value.ok && value.error !== null) ctx.addIssue({ code: "custom", message: "successful replies must not contain an error" });
  if (value.ok && value.result === null) ctx.addIssue({ code: "custom", message: "successful replies must contain a result object" });
  if (!value.ok && value.error === null) ctx.addIssue({ code: "custom", message: "failed replies must contain an error" });
  if (!value.ok && value.result !== null) ctx.addIssue({ code: "custom", message: "failed replies must not contain a result" });
});
export type TestingReply = z.infer<typeof ReplySchema>;

export const DescriptorSchema = z.object({
  protocol: z.literal(PROTOCOL),
  sessionId: SessionIdSchema,
  engine: z.enum(["rebuilt", "castle"]),
  build: NonEmptyString,
  pid: z.number().int().nonnegative(),
  port: z.number().int().min(1).max(65535),
  token: NonEmptyString,
  fixtureId: FixtureIdSchema.optional(),
  access: z.enum(["observe", "fixture"]),
  capabilities: z.array(z.string().min(1).max(128)).max(256),
  startedAt: z.string().datetime({ offset: true })
}).strict();
export type SessionDescriptor = z.infer<typeof DescriptorSchema>;

export const PublicDescriptorSchema = DescriptorSchema.omit({ token: true });
export type PublicDescriptor = z.infer<typeof PublicDescriptorSchema>;

export const FixtureClassicSourceSchema = z.object({
  kind: z.literal("classic-starters"),
  seed: z.number().int().min(1).max(2_147_483_646),
  location: z.object({ mapId: z.string().min(1).max(128), x: z.number().int().min(0).max(32767), y: z.number().int().min(0).max(32767) }).strict()
}).strict();
export const FixtureCheckpointSourceSchema = z.object({
  kind: z.literal("checkpoint"),
  checkpointPath: AbsolutePathSchema,
  checkpointSha256: Sha256Schema
}).strict();
export const FixtureConfigSchema = z.object({
  protocol: z.literal(PROTOCOL),
  kind: z.literal("fixture"),
  fixtureId: FixtureIdSchema,
  scratchRoot: AbsolutePathSchema,
  discoveryRoot: AbsolutePathSchema,
  build: NonEmptyString,
  packagePath: AbsolutePathSchema.refine((value) => /\.realmz2$/i.test(value), "packagePath must name a .realmz2 package"),
  packageSha256: Sha256Schema,
  source: z.union([FixtureClassicSourceSchema, FixtureCheckpointSourceSchema])
}).strict();
const GitCommitSchema = z.string().regex(/^[a-f0-9]{40}$/);
const FixtureFileIdentitySchema = z.object({ name: z.string().min(1).max(4096), sha256: Sha256Schema }).strict();
export const CastleFixtureConfigSchema = z.object({
  protocol: z.literal(PROTOCOL),
  kind: z.literal("castle-fixture"),
  fixtureId: FixtureIdSchema,
  scratchRoot: AbsolutePathSchema,
  discoveryRoot: AbsolutePathSchema,
  build: NonEmptyString,
  seed: z.number().int().min(1).max(2_147_483_646),
  location: z.object({ mapId: z.literal("land:0"), x: z.union([z.literal(7), z.literal(8)]), y: z.literal(20) }).strict(),
  identity: z.object({
    baseCommit: z.literal("491816ad60037394f92c428e99c004494d3c28b3"),
    instrumentationCommit: GitCommitSchema,
    sourceFingerprint: NonEmptyString,
    executableSha256: Sha256Schema,
    characters: z.array(FixtureFileIdentitySchema).length(6),
    scenarioFiles: z.array(FixtureFileIdentitySchema).min(1).max(4096)
  }).strict()
}).strict();
export const RestoreParamsSchema = z.object({ checkpoint: z.record(z.string(), z.unknown()) }).strict();
export const FixtureReadinessSchema = z.object({ fixtureReady: z.boolean(), fixtureError: z.record(z.string(), z.unknown()).nullable() }).loose();

export const JourneyCommandSchema = z.enum(["act", "respond", "ui", "invoke"]);
export const JourneyExpectSchema = z.object({
  interactionKind: z.string().max(128).nullable(),
  location: z.object({ mapId: z.string().min(1).max(128), x: z.number().int().min(0).max(32767), y: z.number().int().min(0).max(32767) }).strict().optional(),
  currentControlId: z.string().min(1).max(128).optional()
}).strict();
export const JourneyStepSchema = z.object({
  command: JourneyCommandSchema,
  params: z.record(z.string(), z.unknown()),
  expect: JourneyExpectSchema,
  capture: z.boolean().default(false)
}).strict();
export const JourneyLimitsSchema = z.object({
  maxActions: z.number().int().min(1).max(10_000).default(200),
  timeoutMs: z.number().int().min(1).max(3_600_000).default(120_000)
}).strict();
export const JourneySpecSchema = z.object({
  name: z.string().min(1).max(128),
  sessionId: SessionIdSchema,
  steps: z.array(JourneyStepSchema).min(1).max(10_000),
  limits: JourneyLimitsSchema.default(() => ({ maxActions: 200, timeoutMs: 120_000 }))
}).strict();
export type JourneySpec = z.infer<typeof JourneySpecSchema>;
export type JourneyStep = z.infer<typeof JourneyStepSchema>;

export const JourneyFailureSchema = z.object({ code: z.string().min(1).max(128), message: z.string().min(1).max(4096), mode: z.string().min(1).max(64), stepIndex: z.number().int().nonnegative().optional() }).strict();
export const JourneyStatusSchema = z.object({
  jobId: z.string().regex(/^[a-f0-9]{32}$/),
  name: z.string().min(1).max(128),
  sessionId: SessionIdSchema,
  state: z.enum(["queued", "running", "completed", "failed", "cancelled"]),
  specPath: AbsolutePathSchema,
  statusPath: AbsolutePathSchema,
  evidencePath: AbsolutePathSchema,
  baselineCheckpointPath: AbsolutePathSchema.nullable(),
  startedAt: z.string().datetime({ offset: true }).nullable(),
  finishedAt: z.string().datetime({ offset: true }).nullable(),
  counts: z.object({ steps: z.number().int().nonnegative(), actions: z.number().int().nonnegative(), captures: z.number().int().nonnegative(), evidenceBytes: z.number().int().nonnegative() }).strict(),
  failure: JourneyFailureSchema.nullable()
}).strict();
export type JourneyStatus = z.infer<typeof JourneyStatusSchema>;

export const MUTATING_COMMANDS = ["restore", "act", "respond", "ui", "invoke", "close"] as const;
export const READ_COMMANDS = ["describe", "observe", "checkpoint", "capture"] as const;
export const ALLOWED_COMMANDS = [...READ_COMMANDS, ...MUTATING_COMMANDS] as const;
export type AllowedCommand = (typeof ALLOWED_COMMANDS)[number];

export function isMutatingCommand(command: string): boolean {
  return (MUTATING_COMMANDS as readonly string[]).includes(command);
}

export function publicDescriptor(descriptor: SessionDescriptor): PublicDescriptor {
  const { token: _token, ...publicValue } = descriptor;
  return publicValue;
}

export function makeError(code: string, message: string): z.infer<typeof ErrorSchema> {
  return { code, message };
}

export function makeReply(
  sessionId: string,
  requestId: string,
  revision: number,
  result: Record<string, unknown> | null,
  error: z.infer<typeof ErrorSchema> | null
): TestingReply {
  return ReplySchema.parse({ protocol: PROTOCOL, sessionId, requestId, revision, ok: error === null, result, error });
}
