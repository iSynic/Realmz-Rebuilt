## Identifies the loaded code independently of the native destination header.
class_name ScenarioClassicProgramState
extends RefCounted

enum Kind { PROGRAM, EMPTY, KEEP_CODES, UNAVAILABLE }

var kind: Kind = Kind.PROGRAM
var program_id: String
var context := ScenarioExecutionContext.empty()
## Present only when an interleaved Safe call needs lexical bindings.
var timeline_values: ScenarioExpressionScope


func _init(id: String = "", source_context: ScenarioExecutionContext = null, loaded_kind: Kind = Kind.PROGRAM) -> void:
	kind = loaded_kind
	program_id = id
	context = ScenarioExecutionContext.empty() if source_context == null else source_context.copy()


func copy() -> ScenarioClassicProgramState:
	var result := ScenarioClassicProgramState.new(program_id, context, kind)
	result.timeline_values = timeline_values.copy() if timeline_values != null else null
	return result


func keep_operand(definition: ScenarioDefinition) -> int:
	var program := definition.program_by_id(program_id)
	if program != null:
		for index: int in program.instruction_count():
			var instruction: Variant = program.instruction_at(index)
			if instruction is ClassicActionDefinition:
				var action: ClassicActionDefinition = instruction
				if action.slot == 7: return action.operand_id
	return 0


func to_data() -> Dictionary:
	return {"kind": kind, "programId": program_id, "context": ScenarioExecutionContextCodec.encode(context), "timelineValues": null if timeline_values == null else timeline_values.to_data()}


static func from_data(value: Variant) -> ScenarioClassicProgramState:
	if not ScenarioExecutionWire.fields(value, ["kind", "programId", "context", "timelineValues"]):
		return null
	var data: Dictionary = value
	if not data["programId"] is String:
		return null
	var id: String = data["programId"]
	var loaded_kind := ScenarioExecutionWire.integer(data["kind"], Kind.PROGRAM, Kind.UNAVAILABLE)
	var restored_context := ScenarioExecutionContextCodec.decode(data["context"])
	if loaded_kind < 0 or id.is_empty() and loaded_kind == Kind.PROGRAM or restored_context == null:
		return null
	if loaded_kind == Kind.UNAVAILABLE and (not id.is_empty() or data["timelineValues"] != null or not ScenarioExecutionContextCodec.encode(restored_context).is_empty()):
		return null
	var result := ScenarioClassicProgramState.new(id, restored_context, loaded_kind as Kind)
	if data["timelineValues"] != null:
		if loaded_kind != Kind.PROGRAM: return null
		result.timeline_values = ScenarioExpressionScope.from_data(data["timelineValues"])
		if result.timeline_values == null or result.timeline_values.definition_id != id:
			return null
	return result
