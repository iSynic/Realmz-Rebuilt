import net from "node:net";
import { MAX_MESSAGE_BYTES, ReplySchema, RequestSchema, type TestingReply, type TestingRequest } from "./schemas.js";

export class ProtocolError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.name = "ProtocolError";
    this.code = code;
  }
}

function encode(value: unknown): Buffer {
  const bytes = Buffer.from(JSON.stringify(value), "utf8");
  if (bytes.byteLength + 1 > MAX_MESSAGE_BYTES) throw new ProtocolError("message_too_large", "message exceeds 16 MiB");
  return Buffer.concat([bytes, Buffer.from("\n")]);
}

export async function sendRequest(port: number, request: TestingRequest, timeoutMs = 5000): Promise<TestingReply> {
  const parsedRequest = RequestSchema.parse(request);
  const line = encode(parsedRequest);
  const socket = new net.Socket();
  socket.setNoDelay(true);
  let settled = false;
  try {
    const reply = await new Promise<TestingReply>((resolve, reject) => {
      let buffer = Buffer.alloc(0);
      let completed = false;
      const fail = (error: Error) => { if (!completed) { completed = true; reject(error); } };
      const timer = setTimeout(() => { socket.destroy(); fail(new ProtocolError("timeout", "timed out waiting for engine reply")); }, timeoutMs);
      socket.on("connect", () => socket.write(line));
      socket.on("data", (chunk: Buffer) => {
        if (completed) return;
        buffer = Buffer.concat([buffer, chunk]);
        if (buffer.byteLength > MAX_MESSAGE_BYTES) { clearTimeout(timer); fail(new ProtocolError("message_too_large", "reply exceeds 16 MiB")); return; }
        const index = buffer.indexOf(0x0a);
        if (index < 0) return;
        clearTimeout(timer);
        if (buffer.byteLength !== index + 1) { fail(new ProtocolError("malformed_reply", "engine returned trailing data")); return; }
        const raw = buffer.subarray(0, index);
        const replyBytes = raw.at(-1) === 0x0d ? raw.subarray(0, raw.byteLength - 1) : raw;
        if (replyBytes.byteLength + 1 > MAX_MESSAGE_BYTES) { fail(new ProtocolError("message_too_large", "reply exceeds 16 MiB")); return; }
        let decoded: unknown;
        try { decoded = JSON.parse(replyBytes.toString("utf8")); }
        catch { fail(new ProtocolError("malformed_reply", "engine returned malformed JSON")); return; }
        const parsed = ReplySchema.safeParse(decoded);
        if (!parsed.success) { fail(new ProtocolError("malformed_reply", "engine returned a reply with an invalid shape")); return; }
        if (parsed.data.sessionId !== parsedRequest.sessionId || parsed.data.requestId !== parsedRequest.requestId) { fail(new ProtocolError("malformed_reply", "engine reply identity does not match the request")); return; }
        completed = true;
        resolve(parsed.data);
      });
      socket.on("error", (error) => { clearTimeout(timer); fail(new ProtocolError("disconnected", error.message)); });
      socket.on("close", () => { clearTimeout(timer); fail(new ProtocolError("disconnected", "engine disconnected before replying")); });
      socket.connect({ host: "127.0.0.1", port });
    });
    settled = true;
    return reply;
  } catch (error) {
    if (error instanceof ProtocolError) throw error;
    throw new ProtocolError("disconnected", error instanceof Error ? error.message : "engine connection failed");
  } finally {
    if (!settled) socket.destroy();
    else socket.end();
  }
}

export function isRequest(value: unknown): value is TestingRequest {
  return RequestSchema.safeParse(value).success;
}
