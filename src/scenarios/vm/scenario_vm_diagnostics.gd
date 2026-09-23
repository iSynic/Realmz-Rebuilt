## Retains the active Classic instruction when VM control crosses an interaction boundary.

class_name ScenarioVmDiagnostics
extends RefCounted

var _current_instruction: Dictionary = {}
var _last_failure: Dictionary = {}


func clear() -> void:
	_current_instruction.clear()
	_last_failure.clear()


func capture_instruction(program_id: String, action: ClassicActionDefinition) -> void:
	_current_instruction = {
		"programId": program_id,
		"slot": action.slot,
		"opcode": action.opcode,
		"operands": [action.operand_id] + action.extra_code,
	}


func clear_instruction() -> void:
	_current_instruction.clear()


func restore_pending_instruction(frames: Array[ScenarioFrame], definition: ScenarioDefinition, debug_program: ScenarioProgramDefinition, debug_program_id: String) -> void:
	if not _current_instruction.is_empty():
		return
	for index: int in range(frames.size() - 1, -1, -1):
		var frame: ScenarioFrame = frames[index]
		if frame.kind != ScenarioFrame.PROGRAM or frame.cursor <= 0:
			continue
		var program := debug_program if frame.definition_id == debug_program_id else definition.program_by_id(frame.definition_id)
		if program == null or frame.cursor > program.instruction_count():
			return
		var instruction: Variant = program.instruction_at(frame.cursor - 1)
		if instruction is ClassicActionDefinition:
			capture_instruction(program.id, instruction)
		return


func capture_failure(code: StringName, message: String) -> void:
	_last_failure = _current_instruction.duplicate(true)
	_last_failure["errorCode"] = String(code)
	_last_failure["errorMessage"] = message
	_current_instruction.clear()


func failure_context() -> Dictionary:
	return _last_failure.duplicate(true)
