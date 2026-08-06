class_name ScenarioDefinition
extends RefCounted

var _programs: Dictionary = {}
var _actions: Dictionary = {}


func _init(programs: Array[ScenarioProgramDefinition], actions: Array[ScenarioActionDefinition]) -> void:
	for program: ScenarioProgramDefinition in programs:
		_programs[program.id] = program
	for action: ScenarioActionDefinition in actions:
		_actions[action.id] = action


func program_by_id(program_id: String) -> ScenarioProgramDefinition:
	return _programs.get(program_id) as ScenarioProgramDefinition


func action_by_id(action_id: String) -> ScenarioActionDefinition:
	return _actions.get(action_id) as ScenarioActionDefinition


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
