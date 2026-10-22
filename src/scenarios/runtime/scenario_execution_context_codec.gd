## Encodes and decodes the strict saved form of scenario execution provenance.

class_name ScenarioExecutionContextCodec
extends RefCounted

const _FIELDS: Array[String] = [
	"_programResolved",
	"applicationHook",
	"actionIndex",
	"battleId",
	"callingContext",
	"characterId",
	"classicMonsterId",
	"combatantId",
	"encounterId",
	"encounterAttempt",
	"encounterKind",
	"mapId",
	"optionIndex",
	"optionSlot",
	"originProgramId",
	"originalProgramId",
	"randomRegionId",
	"responseId",
	"responseKind",
	"serviceId",
	"timedEncounterId",
	"traitor",
	"transferredProgramId",
	"triggerId",
	"x",
	"y",
]


static func encode(context: ScenarioExecutionContext) -> Dictionary:
	var result: Dictionary = {}
	if not context.calling_context.is_empty(): result["callingContext"] = String(context.calling_context)
	if not context.trigger_id.is_empty(): result["triggerId"] = context.trigger_id
	if not context.map_id.is_empty(): result["mapId"] = context.map_id
	if context.has_coordinate:
		result["x"] = context.coordinate.x
		result["y"] = context.coordinate.y
	if context.timed_encounter_id >= 0: result["timedEncounterId"] = context.timed_encounter_id
	if not context.random_region_id.is_empty(): result["randomRegionId"] = context.random_region_id
	if not context.application_hook.is_empty(): result["applicationHook"] = String(context.application_hook)
	if context.has_service_id: result["serviceId"] = context.service_id
	if not context.battle_id.is_empty(): result["battleId"] = context.battle_id
	if not context.combatant_id.is_empty(): result["combatantId"] = context.combatant_id
	if context.has_classic_monster_id: result["classicMonsterId"] = context.classic_monster_id
	if context.has_traitor: result["traitor"] = context.traitor
	if not context.encounter_kind.is_empty(): result["encounterKind"] = String(context.encounter_kind)
	if context.encounter_id >= 0: result["encounterId"] = context.encounter_id
	if context.encounter_attempt >= 0: result["encounterAttempt"] = context.encounter_attempt
	if not context.response_id.is_empty(): result["responseId"] = context.response_id
	if context.option_index >= 0: result["optionIndex"] = context.option_index
	if not context.response_kind.is_empty(): result["responseKind"] = String(context.response_kind)
	if context.option_slot >= 0: result["optionSlot"] = context.option_slot
	if context.action_index >= 0: result["actionIndex"] = context.action_index
	if not context.character_id.is_empty(): result["characterId"] = context.character_id
	if context.program_resolved: result["_programResolved"] = true
	if not context.original_program_id.is_empty(): result["originalProgramId"] = context.original_program_id
	if not context.origin_program_id.is_empty(): result["originProgramId"] = context.origin_program_id
	if not context.transferred_program_id.is_empty(): result["transferredProgramId"] = context.transferred_program_id
	return result


static func decode(value: Variant) -> ScenarioExecutionContext:
	if not value is Dictionary:
		return null
	var data: Dictionary = value
	for key: Variant in data.keys():
		if not key is String or key not in _FIELDS:
			return null
	var result := ScenarioExecutionContext.new()
	if not _read_string_name(data, "callingContext", result, "calling_context"): return null
	if not _read_string(data, "triggerId", result, "trigger_id"): return null
	if not _read_string(data, "mapId", result, "map_id"): return null
	if data.has("x") != data.has("y") or data.has("x") and (not _whole_number(data["x"]) or not _whole_number(data["y"])): return null
	if data.has("x"):
		var x: int = data["x"]
		var y: int = data["y"]
		result.coordinate = Vector2i(x, y)
		result.has_coordinate = true
	if not _read_nonnegative_int(data, "timedEncounterId", result, "timed_encounter_id"): return null
	if not _read_string(data, "randomRegionId", result, "random_region_id"): return null
	if not _read_string_name(data, "applicationHook", result, "application_hook"): return null
	if data.has("serviceId"):
		if not data["serviceId"] is String: return null
		result.service_id = data["serviceId"]
		result.has_service_id = true
	if not _read_string(data, "battleId", result, "battle_id"): return null
	if not _read_string(data, "combatantId", result, "combatant_id"): return null
	if data.has("classicMonsterId"):
		if not _whole_number(data["classicMonsterId"]): return null
		var classic_monster_id: int = data["classicMonsterId"]
		result.classic_monster_id = classic_monster_id
		result.has_classic_monster_id = true
	if data.has("traitor"):
		if not data["traitor"] is bool: return null
		result.traitor = data["traitor"]
		result.has_traitor = true
	if not _read_string_name(data, "encounterKind", result, "encounter_kind"): return null
	if not _read_nonnegative_int(data, "encounterId", result, "encounter_id"): return null
	if not _read_nonnegative_int(data, "encounterAttempt", result, "encounter_attempt"): return null
	if not _read_string(data, "responseId", result, "response_id"): return null
	if not _read_nonnegative_int(data, "optionIndex", result, "option_index"): return null
	if not _read_string_name(data, "responseKind", result, "response_kind"): return null
	if not _read_nonnegative_int(data, "optionSlot", result, "option_slot"): return null
	if not _read_nonnegative_int(data, "actionIndex", result, "action_index"): return null
	if not _read_string(data, "characterId", result, "character_id"): return null
	if data.has("_programResolved"):
		if data["_programResolved"] != true: return null
		result.program_resolved = true
	if not _read_string(data, "originalProgramId", result, "original_program_id"): return null
	if not _read_string(data, "originProgramId", result, "origin_program_id"): return null
	if not _read_string(data, "transferredProgramId", result, "transferred_program_id"): return null
	return result


static func _read_string(data: Dictionary, key: String, target: ScenarioExecutionContext, property: StringName) -> bool:
	if not data.has(key): return true
	if not data[key] is String: return false
	target.set(property, data[key])
	return true


static func _read_string_name(data: Dictionary, key: String, target: ScenarioExecutionContext, property: StringName) -> bool:
	if not data.has(key): return true
	if not data[key] is String: return false
	var text: String = data[key]
	target.set(property, StringName(text))
	return true


static func _read_nonnegative_int(data: Dictionary, key: String, target: ScenarioExecutionContext, property: StringName) -> bool:
	if not data.has(key): return true
	if not _whole_number(data[key]): return false
	var number: int = data[key]
	if number < 0: return false
	target.set(property, number)
	return true


static func _whole_number(value: Variant) -> bool:
	if value is int:
		return true
	if not value is float:
		return false
	var number: float = value
	return is_equal_approx(number, roundf(number))
