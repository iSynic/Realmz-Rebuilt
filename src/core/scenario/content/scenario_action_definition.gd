class_name ScenarioActionDefinition
extends RefCounted

var id: String
var name: String
var description: String
var visibility: StringName
var category: StringName
var abi_version: int
var implementation_version: int
var state_schema_version: int
var return_type: StringName
var backend: StringName
var program: SafeProgramDefinition
var _parameters: Array[ScenarioActionParameter] = []
var _allowed_contexts: Array[StringName] = []
var _required_capabilities: Array[String] = []


func _init(action_id: String, action_name: String, action_description: String, action_visibility: StringName, action_category: StringName, abi: int, implementation: int, state_schema: int, action_parameters: Array[ScenarioActionParameter], action_return_type: StringName, contexts: Array[StringName], capabilities: Array[String], action_backend: StringName, safe_program: SafeProgramDefinition) -> void:
	id = action_id
	name = action_name
	description = action_description
	visibility = action_visibility
	category = action_category
	abi_version = abi
	implementation_version = implementation
	state_schema_version = state_schema
	_parameters = action_parameters.duplicate()
	return_type = action_return_type
	_allowed_contexts = contexts.duplicate()
	_required_capabilities = capabilities.duplicate()
	backend = action_backend
	program = safe_program


func parameters() -> Array[ScenarioActionParameter]:
	return _parameters.duplicate()


func allowed_contexts() -> Array[StringName]:
	return _allowed_contexts.duplicate()


func required_capabilities() -> Array[String]:
	return _required_capabilities.duplicate()


func allows_context(context: StringName) -> bool:
	return _allowed_contexts.has(context)


func parameter_names() -> Array[String]:
	var names: Array[String] = []
	for parameter: ScenarioActionParameter in _parameters:
		names.append(parameter.name)
	names.sort()
	return names
