import * as z from "zod/v4";

export const PROTOCOL = "realmz-testing/1" as const;
export const MAX_MESSAGE_BYTES = 16 * 1024 * 1024;

export const SessionIdSchema = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/);
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
  access: z.enum(["observe", "fixture"]),
  capabilities: z.array(z.string().min(1).max(128)).max(256),
  startedAt: z.string().datetime({ offset: true })
}).strict();
export type SessionDescriptor = z.infer<typeof DescriptorSchema>;

export const PublicDescriptorSchema = DescriptorSchema.omit({ token: true });
export type PublicDescriptor = z.infer<typeof PublicDescriptorSchema>;

export const MUTATING_COMMANDS = ["restore", "act", "respond", "ui", "invoke", "close"] as const;
export const READ_COMMANDS = ["describe", "observe", "checkpoint"] as const;
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
