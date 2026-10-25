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
		"rawOpcode": action.raw_opcode,
		"operands": [action.operand_id] + action.extra_code,
	}
	if action.extra_code_fault != null:
		_current_instruction["nativePath"] = "Data EDCD"
		_current_instruction["extraCodeRow"] = action.extra_code_fault.row_id
		_current_instruction["availableBytes"] = action.extra_code_fault.available_bytes
		_current_instruction["requiredBytes"] = 10


func clear_instruction() -> void:
	_current_instruction.clear()


func capture_failure(code: StringName, message: String) -> void:
	_last_failure = _current_instruction.duplicate(true)
	_last_failure["errorCode"] = String(code)
	_last_failure["errorMessage"] = message
	_current_instruction.clear()


func failure_context() -> Dictionary:
	return _last_failure.duplicate(true)
