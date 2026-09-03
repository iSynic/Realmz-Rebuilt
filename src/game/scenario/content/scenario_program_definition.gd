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
