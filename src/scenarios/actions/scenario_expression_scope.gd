## Holds detached lexical values for a Safe Action or an explicit timeline call.
class_name ScenarioExpressionScope
extends RefCounted

var definition_id: String
var context := ScenarioExecutionContext.empty()
var parameters: Dictionary = {}
var locals: Dictionary = {}


func _init(owner_id: String = "") -> void:
	definition_id = owner_id


func parameter(name: String) -> Variant:
	return parameters.get(name)


func has_local(name: String) -> bool:
	return locals.has(name)


func local(name: String) -> Variant:
	return locals.get(name)


func set_local(name: String, value: Variant) -> void:
	locals[name] = value


func erase_local(name: String) -> void:
	locals.erase(name)


func context_value(name: String) -> Variant:
	return context.value(name)


func copy() -> ScenarioExpressionScope:
	var result := ScenarioExpressionScope.new(definition_id)
	result.context = context.copy()
	result.parameters = parameters.duplicate(true)
	result.locals = locals.duplicate(true)
	return result


func to_data() -> Dictionary:
	return {"definitionId": definition_id, "context": ScenarioExecutionContextCodec.encode(context), "parameters": ScenarioValueCodec.encode(parameters, true), "locals": ScenarioValueCodec.encode(locals, true)}


static func from_data(value: Variant) -> ScenarioExpressionScope:
	if not ScenarioExecutionWire.fields(value, ["definitionId", "context", "parameters", "locals"]):
		return null
	var data: Dictionary = value
	if not data["definitionId"] is String:
		return null
	var restored_context := ScenarioExecutionContextCodec.decode(data["context"])
	var restored_parameters := ScenarioValueCodec.decode(data["parameters"], 0, true)
	var restored_locals := ScenarioValueCodec.decode(data["locals"], 0, true)
	if restored_context == null or not restored_parameters["ok"] or not restored_locals["ok"] or not restored_parameters["value"] is Dictionary or not restored_locals["value"] is Dictionary:
		return null
	var owner_id: String = data["definitionId"]
	if owner_id.is_empty():
		return null
	var result := ScenarioExpressionScope.new(owner_id)
	result.context = restored_context
	result.parameters = restored_parameters["value"]
	result.locals = restored_locals["value"]
	return result
