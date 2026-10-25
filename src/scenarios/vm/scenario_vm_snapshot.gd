## Defines the scenario VM snapshot contract for scenario execution.

class_name ScenarioVmSnapshot
extends RefCounted

const SCHEMA_VERSION: int = 5

var execution: ScenarioExecutionState

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


func has_execution_records() -> bool:
	return not execution.records.is_empty() if execution != null else not frames.is_empty()


func to_data() -> Dictionary:
	if execution != null: return execution.to_data()
	var frame_data: Array[Dictionary] = []
	for frame: ScenarioFrame in frames:
		frame_data.append(frame.to_data(not legacy_values))
	var pending_data: Variant = null
	if pending_request != null:
		pending_data = pending_request.to_data()
	var data := {
		# An unrestored legacy snapshot keeps its schema-3 shape so nested copies
		# retain the declared-type coercion owed when the VM finally restores it.
		"schemaVersion": 3 if legacy_values else 4,
		"frames": frame_data,
		"pendingRequest": pending_data,
		"pendingContinuation": null if pending_continuation == null else pending_continuation.to_data(),
		"trace": trace.duplicate(true),
		"requestCounter": request_counter,
		"halted": halted,
		"lastOutcome": detached(last_outcome) if legacy_values else ScenarioValueCodec.encode(last_outcome),
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


static func from_data(value: Variant, depth: int = 0) -> ScenarioVmSnapshot:
	if depth > 32 or not value is Dictionary:
		return null
	var data: Dictionary = value
	if data.get("schemaVersion") == SCHEMA_VERSION:
		return from_execution(data, depth)
	if not ((data.size() == 9 and data.get("schemaVersion") == 2) or (data.size() == 14 and (data.get("schemaVersion") == 3 or data.get("schemaVersion") == 4) and data.get("classicRecordId") is String)):
		return null
	var typed: bool = data.get("schemaVersion") == 4
	for field: String in ["frames", "pendingRequest", "pendingContinuation", "trace", "requestCounter", "nativeInvocationBegun" if typed else "stepCount", "halted", "lastOutcome"]:
		if not data.has(field):
			return null
	var saved_request_counter := _integer(data["requestCounter"])
	var native_begun: Variant = data["nativeInvocationBegun"] if typed else (_integer(data["stepCount"]) > 0 if _integer(data["stepCount"]) >= 0 else null)
	if not data["frames"] is Array or not (data["pendingContinuation"] == null or data["pendingContinuation"] is Dictionary) or not data["trace"] is Array or saved_request_counter < 0 or not native_begun is bool or not data["halted"] is bool:
		return null
	var snapshot := ScenarioVmSnapshot.new()
	snapshot.legacy_values = data["schemaVersion"] != 4
	if data["schemaVersion"] != 2 and not snapshot.read_legacy_native_state(data): return null
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
		var trace_entry: Dictionary = entry
		snapshot.trace.append(trace_entry.duplicate(true))
	snapshot.request_counter = saved_request_counter
	snapshot.native_invocation_begun = native_begun
	snapshot.legacy_step_count = 0 if typed else _integer(data["stepCount"])
	snapshot.halted = data["halted"]
	if snapshot.legacy_values:
		snapshot.last_outcome = detached(data["lastOutcome"])
	else:
		var outcome := ScenarioValueCodec.decode(data["lastOutcome"])
		if not outcome["ok"]:
			return null
		snapshot.last_outcome = outcome["value"]
	snapshot.classic_record_id = data.get("classicRecordId", "")
	return snapshot


func read_legacy_native_state(data: Dictionary) -> bool:
	if not data.has_all(["nativeContext", "secondaryDoor", "noSecondDoor", "returnedEarly"]): return false
	for field: String in ["secondaryDoor", "noSecondDoor", "returnedEarly"]:
		if not data.get(field) is bool: return false
	if data.get("nativeContext") != null:
		native_context = ScenarioExecutionContextCodec.decode(data["nativeContext"])
		if native_context == null or not native_context.is_native_mode_one(): return false
	secondary_door = data["secondaryDoor"]
	no_second_door = data["noSecondDoor"]
	returned_early = data["returnedEarly"]
	return true


static func from_execution(data: Dictionary, depth: int) -> ScenarioVmSnapshot:
	var state := ScenarioExecutionState.from_data(data, depth)
	if state == null: return null
	var current := ScenarioVmSnapshot.new()
	current.set_execution(state)
	return current


## Transitional read projections for session validators; only execution is written.
func set_execution(state: ScenarioExecutionState) -> void:
	execution = state
	pending_request = state.pending_request
	halted = state.halted
	request_counter = state.request_counter
	trace = state.trace.duplicate(true)
	last_outcome = state.last_outcome
	classic_record_id = state.classic.code.program_id if state.classic.code != null else ""
	secondary_door = state.completion.header_suppressed
	no_second_door = state.completion.recheck_suppressed
	returned_early = state.completion.exit_path == ScenarioNativeCompletion.Exit.NATIVE_RETURN
	if state.pending_request == null: return
	var record: ScenarioExecutionRecord = state.records.back()
	var call := record.operation
	pending_continuation = ScenarioVmPendingContinuation.safe(call.continuation, state.records.size() - 2, call.result_target) if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE else ScenarioVmPendingContinuation.classic(call.continuation)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and absf(number) <= 9_007_199_254_740_991.0:
			return int(number)
	return -1


## Returns a deep copy of an Array or Dictionary value and any other value unchanged.
static func detached(value: Variant) -> Variant:
	if value is Array:
		var items: Array = value
		return items.duplicate(true)
	if value is Dictionary:
		var record: Dictionary = value
		return record.duplicate(true)
	return value
