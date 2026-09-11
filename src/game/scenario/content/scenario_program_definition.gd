## Defines immutable scenario program definition data consumed by the scenario runtime.

class_name ScenarioProgramDefinition
extends RefCounted

var id: String
var owner_kind: StringName
var owner_id: String
var _instructions: Array[Variant] = []


func _init(program_id: String, program_owner_kind: StringName, program_owner_id: String, program_instructions: Array[Variant]) -> void:
	id = program_id
	owner_kind = program_owner_kind
	owner_id = program_owner_id
	_instructions = program_instructions.duplicate()


func instruction_count() -> int:
	return _instructions.size()


func instruction_at(index: int) -> Variant:
	return _instructions[index] if index >= 0 and index < _instructions.size() else null


func matches_extra_action_point(native_id: int) -> bool:
	if native_id < 0 or native_id > 4_294_967_295:
		return false
	var suffix := str(native_id)
	return id == "xap:%s" % suffix and owner_kind == &"extra-action-point" and owner_id in ["extra-action-point:%s" % suffix, "Data ED3:macro:%s" % suffix]
