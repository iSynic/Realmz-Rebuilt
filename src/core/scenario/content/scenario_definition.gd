class_name ScenarioDefinition
extends RefCounted

var _programs: Dictionary = {}
var _actions: Dictionary = {}
var _application_hooks: ScenarioApplicationHooks


func _init(programs: Array[ScenarioProgramDefinition], actions: Array[ScenarioActionDefinition], application_hooks: ScenarioApplicationHooks = null) -> void:
	_application_hooks = application_hooks if application_hooks != null else ScenarioApplicationHooks.new()
	for program: ScenarioProgramDefinition in programs:
		_programs[program.id] = program
	for action: ScenarioActionDefinition in actions:
		_actions[action.id] = action


func program_by_id(program_id: String) -> ScenarioProgramDefinition:
	return _programs.get(program_id) as ScenarioProgramDefinition


func action_by_id(action_id: String) -> ScenarioActionDefinition:
	return _actions.get(action_id) as ScenarioActionDefinition


func application_hook_program(hook: StringName) -> ScenarioProgramDefinition:
	return program_by_id(_application_hooks.program_id(hook))


func application_hook_program_id(hook: StringName) -> String:
	return _application_hooks.program_id(hook)


func program_ids() -> Array[String]:
	var ids: Array[String] = []
	for program_id: Variant in _programs.keys():
		ids.append(String(program_id))
	ids.sort()
	return ids


func action_ids() -> Array[String]:
	var ids: Array[String] = []
	for action_id: Variant in _actions.keys():
		ids.append(String(action_id))
	ids.sort()
	return ids
