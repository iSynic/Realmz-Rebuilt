class_name SafeProgramDefinition
extends RefCounted

var _instructions: Array[SafeInstructionDefinition] = []


func _init(program_instructions: Array[SafeInstructionDefinition]) -> void:
	_instructions = program_instructions.duplicate()


func instruction_count() -> int:
	return _instructions.size()


func instruction_at(index: int) -> SafeInstructionDefinition:
	return _instructions[index] if index >= 0 and index < _instructions.size() else null
