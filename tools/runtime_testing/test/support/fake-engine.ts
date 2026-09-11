import net, { type Socket, type Server } from "node:net";
import { MAX_MESSAGE_BYTES, ALLOWED_COMMANDS, DescriptorSchema, isMutatingCommand, makeError, makeReply, ReplySchema, RequestSchema, type SessionDescriptor, type TestingReply } from "../../src/schemas.js";

export interface FakeEngineAdapter {
  describe(): Promise<Record<string, unknown>> | Record<string, unknown>;
  handle(command: string, params: Record<string, unknown>, expectedRevision: number | null): Promise<{ revision: number; result: Record<string, unknown> | null }>;
}

export interface FakeTestingService {
  server: Server;
  port: number;
  close(): Promise<void>;
}

const knownCommands = new Set<string>(ALLOWED_COMMANDS);

function requestIdentity(raw: unknown): { sessionId: string; requestId: string } {
  const value = raw as Record<string, unknown> | null;
  return { sessionId: typeof value?.sessionId === "string" ? value.sessionId : "unknown", requestId: typeof value?.requestId === "string" ? value.requestId : "invalid" };
}

function sendLine(socket: Socket, reply: TestingReply): void {
  const bytes = Buffer.from(`${JSON.stringify(ReplySchema.parse(reply))}\n`, "utf8");
  if (bytes.byteLength > MAX_MESSAGE_BYTES) { socket.destroy(); return; }
  socket.write(bytes);
}

function stripCredentials(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stripCredentials);
  if (value !== null && typeof value === "object") return Object.fromEntries(Object.entries(value as Record<string, unknown>).filter(([key]) => key !== "token").map(([key, entry]) => [key, stripCredentials(entry)]));
  return value;
}

function stripCredentialObject(value: Record<string, unknown>): Record<string, unknown> {
  return stripCredentials(value) as Record<string, unknown>;
}

export async function startFakeTestingService(descriptor: SessionDescriptor, adapter: FakeEngineAdapter, port = descriptor.port): Promise<FakeTestingService> {
  DescriptorSchema.parse({ ...descriptor, port: port || descriptor.port });
  let revision = 0;
  const cache = new Map<string, { fingerprint: string; reply: TestingReply }>();
  const server = net.createServer((socket) => {
    if (socket.remoteAddress !== "127.0.0.1" && socket.remoteAddress !== "::ffff:127.0.0.1") { socket.destroy(); return; }
    socket.setNoDelay(true);
    let buffer = Buffer.alloc(0);
    let handled = false;
    const handleLine = async (line: Buffer) => {
      if (handled) return;
      handled = true;
      let raw: unknown;
      try { raw = JSON.parse(line.toString("utf8")); }
      catch { sendLine(socket, makeReply("unknown", "invalid", revision, null, makeError("malformed_request", "request is not valid JSON"))); return; }
      const parsed = RequestSchema.safeParse(raw);
      if (!parsed.success) {
        const id = requestIdentity(raw);
        sendLine(socket, makeReply(id.sessionId.match(/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/) ? id.sessionId : "unknown", id.requestId, revision, null, makeError("invalid_request", "request does not match the protocol schema")));
        return;
      }
      const request = parsed.data;
      if (request.sessionId !== descriptor.sessionId || request.token !== descriptor.token) {
        sendLine(socket, makeReply(request.sessionId, request.requestId, revision, null, makeError("unauthorized", "session authentication failed")));
        return;
      }
      const fingerprint = JSON.stringify([request.sessionId, request.token, request.expectedRevision, request.command, request.params]);
      const previous = cache.get(request.requestId);
      if (previous) {
        if (previous.fingerprint !== fingerprint) sendLine(socket, makeReply(request.sessionId, request.requestId, revision, null, makeError("request_id_conflict", "requestId was already used for a different request")));
        else sendLine(socket, previous.reply);
        return;
      }
      let reply: TestingReply;
      if (!knownCommands.has(request.command)) reply = makeReply(request.sessionId, request.requestId, revision, null, makeError("unsupported_command", `unsupported command: ${request.command}`));
      else if (isMutatingCommand(request.command) && descriptor.access === "observe") reply = makeReply(request.sessionId, request.requestId, revision, null, makeError("access_denied", "observe sessions reject mutating commands"));
      else if (isMutatingCommand(request.command) && request.expectedRevision === null) reply = makeReply(request.sessionId, request.requestId, revision, null, makeError("expected_revision_required", "mutating commands require expectedRevision"));
      else if (isMutatingCommand(request.command) && request.expectedRevision !== revision) reply = makeReply(request.sessionId, request.requestId, revision, null, makeError("revision_conflict", "expectedRevision does not match the live revision"));
      else {
        try {
          const outcome = request.command === "describe" ? { revision, result: stripCredentialObject(await adapter.describe()) } : await adapter.handle(request.command, request.params, request.expectedRevision);
          revision = outcome.revision;
          reply = makeReply(request.sessionId, request.requestId, revision, outcome.result === null ? null : stripCredentialObject(outcome.result), null);
        } catch (error) { reply = makeReply(request.sessionId, request.requestId, revision, null, makeError("engine_error", error instanceof Error ? error.message : "engine command failed")); }
      }
      cache.set(request.requestId, { fingerprint, reply });
      sendLine(socket, reply);
    };
    socket.on("data", (chunk: Buffer) => {
      if (handled) return;
      buffer = Buffer.concat([buffer, chunk]);
      if (buffer.byteLength > MAX_MESSAGE_BYTES) { sendLine(socket, makeReply("unknown", "invalid", revision, null, makeError("message_too_large", "request exceeds 16 MiB"))); socket.destroy(); return; }
      const index = buffer.indexOf(0x0a);
      if (index >= 0) {
        const line = buffer.subarray(0, index);
        if (line.byteLength + 1 > MAX_MESSAGE_BYTES) { sendLine(socket, makeReply("unknown", "invalid", revision, null, makeError("message_too_large", "request exceeds 16 MiB"))); socket.destroy(); return; }
        void handleLine(line.at(-1) === 0x0d ? line.subarray(0, line.byteLength - 1) : line);
      }
    });
  });
  await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen({ host: "127.0.0.1", port }); server.once("listening", () => resolve()); });
  const address = server.address();
  if (address === null || typeof address === "string") throw new Error("loopback service did not expose a TCP port");
  return { server, port: address.port, close: () => new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve())) };
}
