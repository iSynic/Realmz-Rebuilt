## Defines the scenario VM snapshot contract for scenario execution.

class_name ScenarioVmSnapshot
extends RefCounted

const SCHEMA_VERSION: int = 4

var frames: Array[ScenarioFrame] = []
var pending_request: InteractionRequest
var pending_continuation: ScenarioVmPendingContinuation
var trace: Array[Dictionary] = []
var request_counter: int = 0
var native_invocation_begun: bool = false
var halted: bool = true
var last_outcome: Variant
var classic_record_id: String = ""
var native_context: ScenarioExecutionContext
var secondary_door: bool = false
var no_second_door: bool = false
var returned_early: bool = false
## True for schema 2/3 snapshots, whose frame values are untagged JSON.
var legacy_values: bool = false
## The exact schema 2/3 stepCount, written back verbatim so legacy envelopes still match byte for byte.
var legacy_step_count: int = 0


func rekey_pending_request(request_id: String, depth: int = 0) -> bool:
	if depth > 32 or pending_request == null: return false
	pending_request.request_id = request_id
	var runtime := pending_continuation.runtime if pending_continuation != null else null
	var nested := runtime.nested_vm() if runtime != null else null
	return nested == null or nested.rekey_pending_request(request_id, depth + 1)


func to_data() -> Dictionary:
	var frame_data: Array[Dictionary] = []
	for frame: ScenarioFrame in frames:
		frame_data.append(frame.to_data(not legacy_values))
	var pending_data: Variant = null
	if pending_request != null:
		pending_data = pending_request.to_data()
	var data := {
		# An unrestored legacy snapshot keeps its schema-3 shape so nested copies
		# retain the declared-type coercion owed when the VM finally restores it.
		"schemaVersion": 3 if legacy_values else SCHEMA_VERSION,
		"frames": frame_data,
		"pendingRequest": pending_data,
		"pendingContinuation": null if pending_continuation == null else pending_continuation.to_data(),
		"trace": trace.duplicate(true),
		"requestCounter": request_counter,
		"halted": halted,
		"lastOutcome": _detached(last_outcome) if legacy_values else ScenarioValueCodec.encode(last_outcome),
		"classicRecordId": classic_record_id,
		"nativeContext": null if native_context == null else ScenarioExecutionContextCodec.encode(native_context),
		"secondaryDoor": secondary_door,
		"noSecondDoor": no_second_door,
		"returnedEarly": returned_early,
	}
	# ADR 0027: schema 4 persists only whether the native invocation began; the
	# per-run step budget is never saved.
	if legacy_values: data["stepCount"] = legacy_step_count
	else: data["nativeInvocationBegun"] = native_invocation_begun
	return data


static func from_data(data: Variant, depth: int = 0) -> ScenarioVmSnapshot:
	if depth > 32 or not data is Dictionary or not ((data.size() == 9 and data.get("schemaVersion") == 2) or (data.size() == 14 and (data.get("schemaVersion") == 3 or data.get("schemaVersion") == SCHEMA_VERSION) and data.get("classicRecordId") is String)):
		return null
	var typed: bool = data.get("schemaVersion") == SCHEMA_VERSION
	for field: String in ["frames", "pendingRequest", "pendingContinuation", "trace", "requestCounter", "nativeInvocationBegun" if typed else "stepCount", "halted", "lastOutcome"]:
		if not data.has(field):
			return null
	var saved_request_counter := _integer(data["requestCounter"])
	var native_begun: Variant = data["nativeInvocationBegun"] if typed else (_integer(data["stepCount"]) > 0 if _integer(data["stepCount"]) >= 0 else null)
	if not data["frames"] is Array or not (data["pendingContinuation"] == null or data["pendingContinuation"] is Dictionary) or not data["trace"] is Array or saved_request_counter < 0 or not native_begun is bool or not data["halted"] is bool:
		return null
	var snapshot := ScenarioVmSnapshot.new()
	snapshot.legacy_values = data["schemaVersion"] != SCHEMA_VERSION
	if data["schemaVersion"] != 2:
		if not data.has_all(["nativeContext", "secondaryDoor", "noSecondDoor", "returnedEarly"]): return null
		for field: String in ["secondaryDoor", "noSecondDoor", "returnedEarly"]:
			if not data.get(field) is bool: return null
		if data.get("nativeContext") != null:
			snapshot.native_context = ScenarioExecutionContextCodec.decode(data["nativeContext"])
			if snapshot.native_context == null or not snapshot.native_context.is_native_mode_one(): return null
		snapshot.secondary_door = data["secondaryDoor"]
		snapshot.no_second_door = data["noSecondDoor"]
		snapshot.returned_early = data["returnedEarly"]
	for frame_data: Variant in data["frames"]:
		var frame := ScenarioFrame.from_data(frame_data, not snapshot.legacy_values)
		if frame == null:
			return null
		snapshot.frames.append(frame)
	if data["pendingRequest"] != null:
		snapshot.pending_request = InteractionRequest.from_data(data["pendingRequest"])
		if snapshot.pending_request == null:
			return null
	if data["pendingContinuation"] != null:
		snapshot.pending_continuation = ScenarioVmPendingContinuation.from_data(data["pendingContinuation"], depth)
		if snapshot.pending_continuation == null:
			return null
	if (snapshot.pending_request == null and snapshot.pending_continuation != null) or (snapshot.pending_request != null and snapshot.pending_continuation == null):
		return null
	for entry: Variant in data["trace"]:
		if not entry is Dictionary:
			return null
		snapshot.trace.append(entry.duplicate(true))
	snapshot.request_counter = saved_request_counter
	snapshot.native_invocation_begun = native_begun
	snapshot.legacy_step_count = 0 if typed else _integer(data["stepCount"])
	snapshot.halted = data["halted"]
	if snapshot.legacy_values:
		snapshot.last_outcome = _detached(data["lastOutcome"])
	else:
		var outcome := ScenarioValueCodec.decode(data["lastOutcome"])
		if not outcome["ok"]:
			return null
		snapshot.last_outcome = outcome["value"]
	snapshot.classic_record_id = data.get("classicRecordId", "")
	return snapshot


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_finite(value) and value == floor(value) and absf(value) <= 9_007_199_254_740_991.0:
		return int(value)
	return -1


static func _detached(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value
