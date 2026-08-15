class_name ScenarioVmHandoff
extends RefCounted

const VERSION: int = 1
const CLASSIC_OPERATION: StringName = &"classic-operation"
const SAFE_OPERATION: StringName = &"safe-operation"

var kind: StringName
var runtime: ScenarioRuntimeHandoff
var frame_index: int = -1
var result_target: String


func _init(handoff_kind: StringName = &"") -> void:
	kind = handoff_kind


static func classic(runtime_handoff: ScenarioRuntimeHandoff) -> ScenarioVmHandoff:
	var result := ScenarioVmHandoff.new(CLASSIC_OPERATION)
	result.runtime = runtime_handoff.copy() if runtime_handoff != null else null
	return result


static func safe(runtime_handoff: ScenarioRuntimeHandoff, action_frame_index: int, target: String) -> ScenarioVmHandoff:
	var result := ScenarioVmHandoff.new(SAFE_OPERATION)
	result.runtime = runtime_handoff.copy() if runtime_handoff != null else null
	result.frame_index = action_frame_index
	result.result_target = target
	return result


func copy() -> ScenarioVmHandoff:
	var duplicate := from_data(to_data())
	assert(duplicate != null, "A live typed VM handoff must round-trip through its wire codec")
	return duplicate


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


static func from_data(value: Variant) -> ScenarioVmHandoff:
	if not value is Dictionary or value.size() != 3 or not value.get("kind") is String or _integer(value.get("version")) != VERSION or not value.get("data") is Dictionary:
		return null
	var data: Dictionary = value["data"]
	var runtime_handoff := ScenarioRuntimeHandoff.from_data(data.get("runtime"))
	if runtime_handoff == null:
		return null
	match StringName(value["kind"]):
		CLASSIC_OPERATION:
			return classic(runtime_handoff) if data.size() == 1 else null
		SAFE_OPERATION:
			var parsed_frame_index := _integer(data.get("frameIndex"))
			if data.size() != 3 or parsed_frame_index < 0 or not data.get("resultTarget") is String:
				return null
			return safe(runtime_handoff, parsed_frame_index, data["resultTarget"])
	return null


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
