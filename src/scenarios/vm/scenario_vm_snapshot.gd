class_name ScenarioVmSnapshot
extends RefCounted

const SCHEMA_VERSION: int = 2

var frames: Array[ScenarioFrame] = []
var pending_request: InteractionRequest
var pending_continuation: ScenarioVmPendingContinuation
var trace: Array[Dictionary] = []
var request_counter: int = 0
var step_count: int = 0
var halted: bool = true
var last_outcome: Variant


func to_data() -> Dictionary:
	var frame_data: Array[Dictionary] = []
	for frame: ScenarioFrame in frames:
		frame_data.append(frame.to_data())
	var pending_data: Variant = null
	if pending_request != null:
		pending_data = pending_request.to_data()
	return {
		"schemaVersion": SCHEMA_VERSION,
		"frames": frame_data,
		"pendingRequest": pending_data,
		"pendingContinuation": null if pending_continuation == null else pending_continuation.to_data(),
		"trace": trace.duplicate(true),
		"requestCounter": request_counter,
		"stepCount": step_count,
		"halted": halted,
		"lastOutcome": _detached(last_outcome),
	}


static func from_data(data: Variant) -> ScenarioVmSnapshot:
	if not data is Dictionary or data.size() != 9 or data.get("schemaVersion") != SCHEMA_VERSION:
		return null
	for field: String in ["frames", "pendingRequest", "pendingContinuation", "trace", "requestCounter", "stepCount", "halted", "lastOutcome"]:
		if not data.has(field):
			return null
	var saved_request_counter := _integer(data["requestCounter"])
	var saved_step_count := _integer(data["stepCount"])
	if not data["frames"] is Array or not (data["pendingContinuation"] == null or data["pendingContinuation"] is Dictionary) or not data["trace"] is Array or saved_request_counter < 0 or saved_step_count < 0 or not data["halted"] is bool:
		return null
	var snapshot := ScenarioVmSnapshot.new()
	for frame_data: Variant in data["frames"]:
		var frame := ScenarioFrame.from_data(frame_data)
		if frame == null:
			return null
		snapshot.frames.append(frame)
	if data["pendingRequest"] != null:
		snapshot.pending_request = InteractionRequest.from_data(data["pendingRequest"])
		if snapshot.pending_request == null:
			return null
	if data["pendingContinuation"] != null:
		snapshot.pending_continuation = ScenarioVmPendingContinuation.from_data(data["pendingContinuation"])
		if snapshot.pending_continuation == null:
			return null
	if (snapshot.pending_request == null and snapshot.pending_continuation != null) or (snapshot.pending_request != null and snapshot.pending_continuation == null):
		return null
	for entry: Variant in data["trace"]:
		if not entry is Dictionary:
			return null
		snapshot.trace.append(entry.duplicate(true))
	snapshot.request_counter = saved_request_counter
	snapshot.step_count = saved_step_count
	snapshot.halted = data["halted"]
	snapshot.last_outcome = _detached(data["lastOutcome"])
	return snapshot


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _detached(value: Variant) -> Variant:
	return value.duplicate(true) if value is Array or value is Dictionary else value
