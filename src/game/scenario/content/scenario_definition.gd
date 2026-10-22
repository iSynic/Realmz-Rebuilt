## Defines immutable scenario definition data consumed by the scenario runtime.

class_name ScenarioDefinition
extends RefCounted

var _programs: Dictionary = {}
var _actions: Dictionary = {}
var _application_hooks: ScenarioApplicationHooks
var _classic_fallthrough: bool = false
var classic_records: ClassicRecordCatalog


func native_xap_is_unavailable(native_id: int) -> bool:
	return classic_records != null and classic_records.lookup("Data ED3", native_id, "extra-action-points").availability != ClassicRecordCatalog.Availability.COMPLETE


func native_program_is_unavailable(program_id: String) -> bool:
	if classic_records == null: return false
	var parts := program_id.split(":")
	if parts.size() == 2 and parts[0] == "xap" and parts[1].is_valid_int():
		return native_xap_is_unavailable(int(parts[1]))
	if parts.size() == 4 and parts[0] in ["simple", "complex"] and parts[1].is_valid_int() and parts[2] == "result" and parts[3].is_valid_int():
		var path := "Data ED" if parts[0] == "simple" else "Data ED2"
		return int(parts[3]) not in range(4) or classic_records.lookup(path, int(parts[1])).availability != ClassicRecordCatalog.Availability.COMPLETE
	return false


func _init(programs: Array[ScenarioProgramDefinition], actions: Array[ScenarioActionDefinition], application_hooks: ScenarioApplicationHooks = null, classic_fallthrough: bool = false) -> void:
	_application_hooks = application_hooks if application_hooks != null else ScenarioApplicationHooks.new()
	_classic_fallthrough = classic_fallthrough
	for program: ScenarioProgramDefinition in programs:
		_programs[program.id] = program
	for action: ScenarioActionDefinition in actions:
		_actions[action.id] = action


func allows_classic_fallthrough() -> bool:
	return _classic_fallthrough


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
