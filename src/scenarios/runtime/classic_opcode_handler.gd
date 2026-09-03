class_name ClassicOpcodeHandler
extends RefCounted


func opcode_ids() -> Array[int]:
	return []


func execute(_action: ClassicActionDefinition, _request_id: String, _context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	return ScenarioRuntimeOperationResult.failed(&"unsupported_classic_opcode", "The Classic opcode handler does not implement this operation.")
