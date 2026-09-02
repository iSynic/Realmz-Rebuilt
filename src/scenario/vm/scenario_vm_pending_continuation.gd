class_name ScenarioVmPendingContinuation
extends RefCounted

const VERSION: int = 1
const CLASSIC_OPERATION: StringName = &"classic-operation"
const SAFE_OPERATION: StringName = &"safe-operation"

var kind: StringName
var runtime: ScenarioRuntimeContinuation
var frame_index: int = -1
var result_target: String


func _init(continuation_kind: StringName = &"") -> void:
	kind = continuation_kind


static func classic(runtime_continuation: ScenarioRuntimeContinuation) -> ScenarioVmPendingContinuation:
	var result := ScenarioVmPendingContinuation.new(CLASSIC_OPERATION)
	result.runtime = runtime_continuation.copy() if runtime_continuation != null else null
	return result


static func safe(runtime_continuation: ScenarioRuntimeContinuation, action_frame_index: int, target: String) -> ScenarioVmPendingContinuation:
	var result := ScenarioVmPendingContinuation.new(SAFE_OPERATION)
	result.runtime = runtime_continuation.copy() if runtime_continuation != null else null
	result.frame_index = action_frame_index
	result.result_target = target
	return result


func copy() -> ScenarioVmPendingContinuation:
	return from_data(to_data())


func to_data() -> Dictionary:
	if runtime == null:
		return {}
	var runtime_data := runtime.to_data()
	if runtime_data.is_empty():
		return {}
	var data := {"runtime": runtime_data}
	match kind:
		CLASSIC_OPERATION:
			pass
		SAFE_OPERATION:
			if frame_index < 0:
				return {}
			data["frameIndex"] = frame_index
			data["resultTarget"] = result_target
		_:
			return {}
	return {"kind": String(kind), "version": VERSION, "data": data}


static func from_data(value: Variant) -> ScenarioVmPendingContinuation:
	if not value is Dictionary or value.size() != 3 or not value.get("kind") is String or _integer(value.get("version")) != VERSION or not value.get("data") is Dictionary:
		return null
	var data: Dictionary = value["data"]
	var runtime_continuation := ScenarioRuntimeContinuation.from_data(data.get("runtime"))
	if runtime_continuation == null:
		return null
	match StringName(value["kind"]):
		CLASSIC_OPERATION:
			return classic(runtime_continuation) if data.size() == 1 else null
		SAFE_OPERATION:
			var parsed_frame_index := _integer(data.get("frameIndex"))
			if data.size() != 3 or parsed_frame_index < 0 or not data.get("resultTarget") is String:
				return null
			return safe(runtime_continuation, parsed_frame_index, data["resultTarget"])
	return null


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
