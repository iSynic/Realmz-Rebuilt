## Defines the scenario VM handoff contract for scenario execution.

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
	if duplicate == null:
		push_error("A live typed VM handoff must round-trip through its wire codec.")
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


static func from_data(value: Variant, depth: int = 0) -> ScenarioVmHandoff:
	if not value is Dictionary:
		return null
	var envelope: Dictionary = value
	if envelope.size() != 3 or not envelope.get("kind") is String or _integer(envelope.get("version")) != VERSION or not envelope.get("data") is Dictionary:
		return null
	var data: Dictionary = envelope["data"]
	var runtime_handoff := ScenarioRuntimeHandoff.from_data(data.get("runtime"), depth)
	if runtime_handoff == null:
		return null
	var kind_text: String = envelope["kind"]
	var result := ScenarioVmHandoff.new(StringName(kind_text))
	result.runtime = runtime_handoff
	match result.kind:
		CLASSIC_OPERATION:
			return result if data.size() == 1 else null
		SAFE_OPERATION:
			var parsed_frame_index := _integer(data.get("frameIndex"))
			if data.size() != 3 or parsed_frame_index < 0 or not data.get("resultTarget") is String:
				return null
			result.frame_index = parsed_frame_index
			result.result_target = data["resultTarget"]
			return result
	return null


static func is_valid(handoff: ScenarioVmHandoff, saved: ScenarioVmSnapshot) -> bool:
	if saved == null or saved.halted or not saved.has_execution_records() or saved.pending_request != null or saved.pending_continuation != null or handoff == null or handoff.runtime == null:
		return false
	if saved.execution != null:
		var record: ScenarioExecutionRecord = saved.execution.records.back()
		if record.kind != ScenarioExecutionRecord.Kind.OPERATION or record.operation.phase != ScenarioOperationExecutionRecord.Phase.HOST_RETURN: return false
		return record.operation.handoff.to_data() == handoff.runtime.to_data()
	match handoff.kind:
		ScenarioVmHandoff.CLASSIC_OPERATION:
			return saved.frames.back().kind == ScenarioFrame.PROGRAM
		ScenarioVmHandoff.SAFE_OPERATION:
			var frame_index: int = handoff.frame_index
			return frame_index >= 0 and frame_index < saved.frames.size() and saved.frames[frame_index].kind == ScenarioFrame.ACTION
	return false


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float:
		var number: float = value
		if is_equal_approx(number, roundf(number)):
			return int(number)
	return -1
