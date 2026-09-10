## Validates the developer testing wire envelope and preserves retry identities.
class_name RuntimeTestingProtocol
extends RefCounted

const VERSION := "realmz-testing/1"
const MAX_MESSAGE_BYTES := 16 * 1024 * 1024
const MAX_RECORD_BYTES := 256 * 1024 * 1024
const MAX_REQUESTS := 10_000
const READ_COMMANDS := ["describe", "observe", "checkpoint", "capture"]
const COMMANDS := ["describe", "observe", "checkpoint", "restore", "act", "respond", "ui", "invoke", "close", "capture"]
const FIELDS := ["protocol", "sessionId", "token", "requestId", "expectedRevision", "command", "params"]

var session_id: String
var access: String
var _token: String
var _records: Dictionary = {}
var _record_bytes: int = 0


func _init(identity: String, secret: String, access_mode: String) -> void:
	session_id = identity
	_token = secret
	access = access_mode


func execute(value: Variant, revision: int, dispatch: Callable) -> Dictionary:
	var request_id := String(value["requestId"]).left(128) if value is Dictionary and value.get("requestId") is String and not value["requestId"].is_empty() else "invalid"
	var invalid := _validate(value)
	if not invalid.is_empty():
		return failure(request_id, revision, invalid, "The testing request failed envelope validation.")
	var request: Dictionary = value
	var fingerprint := JSON.stringify(request, "", true, true).sha256_text()
	if _records.has(request_id):
		var previous: Dictionary = _records[request_id]
		if previous["fingerprint"] != fingerprint:
			return failure(request_id, revision, "request_id_conflict", "This request identity was already used with different input.")
		return previous["reply"].duplicate(true)
	if _records.size() >= MAX_REQUESTS or _record_bytes + MAX_MESSAGE_BYTES > MAX_RECORD_BYTES:
		return failure(request_id, revision, "recording_limit", "The retry ledger is full; no further command was executed.")
	var reply: Dictionary
	if access != "fixture" and request["command"] not in READ_COMMANDS:
		reply = failure(request_id, revision, "live_read_only", "Live adventures permit observation and checkpoint export only.")
	elif request["expectedRevision"] != null and int(request["expectedRevision"]) != revision:
		reply = failure(request_id, revision, "stale_revision", "Observe the session again before submitting a new command.")
	else:
		var result: Variant = dispatch.call(request["command"], request["params"])
		if not result is Dictionary or not result.has("error") or not result.has("result") or (result["error"] == null and not result["result"] is Dictionary):
			reply = failure(request_id, revision, "adapter_failure", "The adapter did not return a valid result; inspect runtime diagnostics.")
		else:
			reply = _reply(request_id, int(result.get("revision", revision)), result.get("result"), result.get("error"))
	var encoded := JSON.stringify(reply, "", true, true).to_utf8_buffer()
	if encoded.size() + 1 > MAX_MESSAGE_BYTES:
		reply = failure(request_id, int(reply["revision"]), "message_limit", "The result exceeds the protocol bound; no evidence was silently truncated.")
	_record_bytes += JSON.stringify(reply, "", true, true).to_utf8_buffer().size()
	_records[request_id] = {"fingerprint": fingerprint, "reply": reply.duplicate(true)}
	return reply


func failure(request_id: String, revision: int, code: String, message: String) -> Dictionary:
	return _reply(request_id, revision, null, {"code": code, "message": message})


func _reply(request_id: String, revision: int, result: Variant, error: Variant) -> Dictionary:
	return {"protocol": VERSION, "sessionId": session_id, "requestId": request_id, "revision": revision, "ok": error == null, "result": result, "error": error}


func _validate(value: Variant) -> String:
	if not value is Dictionary or value.size() != FIELDS.size():
		return "invalid_request"
	for field: String in FIELDS:
		if not value.has(field):
			return "invalid_request"
	if value["protocol"] != VERSION:
		return "protocol_version"
	if value["sessionId"] != session_id or value["token"] != _token:
		return "unauthorized"
	if not value["requestId"] is String or value["requestId"].is_empty() or value["requestId"].length() > 128:
		return "invalid_request_id"
	if not value["command"] is String or value["command"] not in COMMANDS or not value["params"] is Dictionary:
		return "unsupported_command"
	var expected: Variant = value["expectedRevision"]
	if expected != null and (not (expected is int or expected is float) or not is_finite(float(expected)) or float(expected) != floor(float(expected)) or expected < 0 or expected > 9_007_199_254_740_991):
		return "invalid_revision"
	if value["command"] not in READ_COMMANDS and expected == null:
		return "expected_revision_required"
	return ""
