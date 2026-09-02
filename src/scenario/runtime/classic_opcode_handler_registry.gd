class_name ClassicOpcodeHandlerRegistry
extends RefCounted

var _handlers_by_opcode: Dictionary = {}
var _registration_error: String = ""


func register(handler: ClassicOpcodeHandler) -> bool:
	if handler == null:
		_registration_error = "Classic opcode handlers cannot be null."
		return false
	for opcode: int in handler.opcode_ids():
		if ClassicOpcodeCatalog.VM_CONTROL_FLOW_OPCODES.has(opcode):
			_registration_error = "Classic opcode %d belongs to VM control flow and cannot be registered as a runtime handler." % opcode
			return false
		if _handlers_by_opcode.has(opcode):
			_registration_error = "Classic opcode %d has duplicate runtime handlers." % opcode
			return false
		_handlers_by_opcode[opcode] = handler
	return true


func has_handler(opcode: int) -> bool:
	return _handlers_by_opcode.has(opcode)


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var handler := _handlers_by_opcode.get(action.opcode) as ClassicOpcodeHandler
	if handler == null:
		return ScenarioRuntimeOperationResult.failed(&"unsupported_classic_opcode", "Classic opcode %d has no runtime handler." % action.opcode)
	return handler.execute(action, request_id, context)


func registration_error() -> String:
	return _registration_error


func registered_opcodes() -> Array[int]:
	var result: Array[int] = []
	for opcode: Variant in _handlers_by_opcode.keys():
		result.append(int(opcode))
	result.sort()
	return result


func is_complete() -> bool:
	var expected := ClassicOpcodeCatalog.runtime_handler_opcodes()
	return _registration_error.is_empty() and registered_opcodes() == expected
