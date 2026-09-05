## Defines the typed scenario execution context boundary used by the scenario VM.

class_name ScenarioExecutionContext
extends RefCounted

var calling_context: StringName = &""
var trigger_id: String = ""
var map_id: String = ""
var coordinate: Vector2i = Vector2i.ZERO
var timed_encounter_id: int = -1
var random_region_id: String = ""
var application_hook: StringName = &""
var service_id: String = ""
var battle_id: String = ""
var combatant_id: String = ""
var classic_monster_id: int = 0
var traitor: bool = false
var encounter_kind: StringName = &""
var encounter_id: int = -1
var encounter_attempt: int = -1
var response_id: String = ""
var option_index: int = -1
var response_kind: StringName = &""
var option_slot: int = -1
var action_index: int = -1
var character_id: String = ""
var program_resolved: bool = false
var original_program_id: String = ""
var origin_program_id: String = ""

var has_coordinate: bool = false
var has_service_id: bool = false
var has_classic_monster_id: bool = false
var has_traitor: bool = false


static func empty() -> ScenarioExecutionContext:
	return ScenarioExecutionContext.new()


static func calling(kind: StringName) -> ScenarioExecutionContext:
	var result := ScenarioExecutionContext.new()
	result.calling_context = kind
	return result


static func trigger(kind: StringName, trigger_identity: String, map_identity: String = "", location: Vector2i = Vector2i.ZERO, include_location: bool = false) -> ScenarioExecutionContext:
	var result := calling(kind)
	result.trigger_id = trigger_identity
	result.map_id = map_identity
	result.coordinate = location
	result.has_coordinate = include_location
	return result


static func combatant(combatant_identity: String) -> ScenarioExecutionContext:
	var result := ScenarioExecutionContext.new()
	result.combatant_id = combatant_identity
	return result


static func encounter(kind: StringName, encounter_identity: int, selected_response_id: String = "", selected_option_index: int = -1, selected_response_kind: StringName = &"", selected_option_slot: int = -1) -> ScenarioExecutionContext:
	var result := ScenarioExecutionContext.new()
	result.encounter_kind = kind
	result.encounter_id = encounter_identity
	result.response_id = selected_response_id
	result.option_index = selected_option_index
	result.response_kind = selected_response_kind
	result.option_slot = selected_option_slot
	return result


func set_encounter_attempt(value: int) -> ScenarioExecutionContext:
	encounter_attempt = value
	return self


func without_encounter() -> ScenarioExecutionContext:
	var result := copy()
	result.encounter_kind = &""
	result.encounter_id = -1
	result.encounter_attempt = -1
	result.response_id = ""
	result.option_index = -1
	result.response_kind = &""
	result.option_slot = -1
	result.action_index = -1
	result.character_id = ""
	return result


func for_new_program_frame() -> ScenarioExecutionContext:
	var result := copy()
	result.calling_context = &""
	result.program_resolved = false
	result.original_program_id = ""
	result.origin_program_id = ""
	return result


func set_thief_action(selected_action_index: int, selected_character_id: String) -> ScenarioExecutionContext:
	action_index = selected_action_index
	character_id = selected_character_id
	return self


func set_timed_encounter(value: int) -> ScenarioExecutionContext:
	timed_encounter_id = value
	return self


func set_random_region(value: String) -> ScenarioExecutionContext:
	random_region_id = value
	return self


func set_application_hook(hook: StringName, service: String) -> ScenarioExecutionContext:
	application_hook = hook
	service_id = service
	has_service_id = true
	return self


func set_battle(value: String) -> ScenarioExecutionContext:
	battle_id = value
	return self


func set_combatant(value: String, monster_id: int = 0, monster_traitor: bool = false, include_monster_facts: bool = false) -> ScenarioExecutionContext:
	combatant_id = value
	classic_monster_id = monster_id
	traitor = monster_traitor
	has_classic_monster_id = include_monster_facts
	has_traitor = include_monster_facts
	return self


func mark_program_resolved(original_id: String) -> void:
	program_resolved = true
	original_program_id = original_id


func mark_program_transfer(origin_id: String) -> void:
	origin_program_id = origin_id


func merged(overlay: ScenarioExecutionContext) -> ScenarioExecutionContext:
	var result := copy()
	if overlay == null:
		return result
	if not overlay.calling_context.is_empty(): result.calling_context = overlay.calling_context
	if not overlay.trigger_id.is_empty(): result.trigger_id = overlay.trigger_id
	if not overlay.map_id.is_empty(): result.map_id = overlay.map_id
	if overlay.has_coordinate:
		result.coordinate = overlay.coordinate
		result.has_coordinate = true
	if overlay.timed_encounter_id >= 0: result.timed_encounter_id = overlay.timed_encounter_id
	if not overlay.random_region_id.is_empty(): result.random_region_id = overlay.random_region_id
	if not overlay.application_hook.is_empty(): result.application_hook = overlay.application_hook
	if overlay.has_service_id:
		result.service_id = overlay.service_id
		result.has_service_id = true
	if not overlay.battle_id.is_empty(): result.battle_id = overlay.battle_id
	if not overlay.combatant_id.is_empty(): result.combatant_id = overlay.combatant_id
	if overlay.has_classic_monster_id:
		result.classic_monster_id = overlay.classic_monster_id
		result.has_classic_monster_id = true
	if overlay.has_traitor:
		result.traitor = overlay.traitor
		result.has_traitor = true
	if not overlay.encounter_kind.is_empty(): result.encounter_kind = overlay.encounter_kind
	if overlay.encounter_id >= 0: result.encounter_id = overlay.encounter_id
	if overlay.encounter_attempt >= 0: result.encounter_attempt = overlay.encounter_attempt
	if not overlay.response_id.is_empty(): result.response_id = overlay.response_id
	if overlay.option_index >= 0: result.option_index = overlay.option_index
	if not overlay.response_kind.is_empty(): result.response_kind = overlay.response_kind
	if overlay.option_slot >= 0: result.option_slot = overlay.option_slot
	if overlay.action_index >= 0: result.action_index = overlay.action_index
	if not overlay.character_id.is_empty(): result.character_id = overlay.character_id
	if overlay.program_resolved: result.program_resolved = true
	if not overlay.original_program_id.is_empty(): result.original_program_id = overlay.original_program_id
	if not overlay.origin_program_id.is_empty(): result.origin_program_id = overlay.origin_program_id
	return result


func value(name: String) -> Variant:
	match name:
		"callingContext": return String(calling_context)
		"triggerId": return trigger_id
		"mapId": return map_id
		"x": return coordinate.x if has_coordinate else null
		"y": return coordinate.y if has_coordinate else null
		"timedEncounterId": return timed_encounter_id if timed_encounter_id >= 0 else null
		"randomRegionId": return random_region_id
		"applicationHook": return String(application_hook)
		"serviceId": return service_id if has_service_id else null
		"battleId": return battle_id
		"combatantId": return combatant_id
		"classicMonsterId": return classic_monster_id if has_classic_monster_id else null
		"traitor": return traitor if has_traitor else null
		"encounterKind": return String(encounter_kind)
		"encounterId": return encounter_id if encounter_id >= 0 else null
		"encounterAttempt": return encounter_attempt if encounter_attempt >= 0 else null
		"responseId": return response_id
		"optionIndex": return option_index if option_index >= 0 else null
		"responseKind": return String(response_kind)
		"optionSlot": return option_slot if option_slot >= 0 else null
		"actionIndex": return action_index if action_index >= 0 else null
		"characterId": return character_id
		"_programResolved": return program_resolved
		"originalProgramId": return original_program_id
		"originProgramId": return origin_program_id
	return null


func copy() -> ScenarioExecutionContext:
	var result := ScenarioExecutionContext.new()
	result.calling_context = calling_context
	result.trigger_id = trigger_id
	result.map_id = map_id
	result.coordinate = coordinate
	result.timed_encounter_id = timed_encounter_id
	result.random_region_id = random_region_id
	result.application_hook = application_hook
	result.service_id = service_id
	result.battle_id = battle_id
	result.combatant_id = combatant_id
	result.classic_monster_id = classic_monster_id
	result.traitor = traitor
	result.encounter_kind = encounter_kind
	result.encounter_id = encounter_id
	result.encounter_attempt = encounter_attempt
	result.response_id = response_id
	result.option_index = option_index
	result.response_kind = response_kind
	result.option_slot = option_slot
	result.action_index = action_index
	result.character_id = character_id
	result.program_resolved = program_resolved
	result.original_program_id = original_program_id
	result.origin_program_id = origin_program_id
	result.has_coordinate = has_coordinate
	result.has_service_id = has_service_id
	result.has_classic_monster_id = has_classic_monster_id
	result.has_traitor = has_traitor
	return result
