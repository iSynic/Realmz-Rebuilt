## Defines the typed scenario runtime handoff boundary used by the scenario VM.

class_name ScenarioRuntimeHandoff
extends RefCounted

const VERSION: int = 1
const PARTY_DEFEAT: StringName = &"party-defeat"
const CLASSIC_COMBAT: StringName = &"classic-combat"
const SAFE_COMBAT: StringName = &"safe-combat"
const CLASSIC_HEALTH: StringName = &"classic-health"

var kind: StringName
var battle_id: String
var source_kind: StringName
var caller: ScenarioBattleCaller
var health_opcode: int
var health_extra_code: Array[int] = []
var health_target_ids: Array[String] = []
var health_next_index: int


func _init(handoff_kind: StringName = &"") -> void:
	kind = handoff_kind


static func party_defeat(battle: String, source: StringName, battle_caller: ScenarioBattleCaller) -> ScenarioRuntimeHandoff:
	var result := ScenarioRuntimeHandoff.new(PARTY_DEFEAT)
	result.battle_id = battle
	result.source_kind = source
	result.caller = battle_caller.copy() if battle_caller != null else null
	return result


static func health_defeat(opcode: int, extra_code: Array[int], target_ids: Array[String], next_index: int) -> ScenarioRuntimeHandoff:
	var result := ScenarioRuntimeHandoff.new(PARTY_DEFEAT)
	result.source_kind = CLASSIC_HEALTH
	result.health_opcode = opcode
	result.health_extra_code.assign(extra_code)
	result.health_target_ids.assign(target_ids)
	result.health_next_index = next_index
	return result


func copy() -> ScenarioRuntimeHandoff:
	var duplicate := from_data(to_data())
	assert(duplicate != null, "A live typed runtime handoff must round-trip through its wire codec")
	return duplicate


func to_data() -> Dictionary:
	if kind == PARTY_DEFEAT and source_kind == CLASSIC_HEALTH:
		if not health_fields_are_valid():
			return {}
		return {"kind": String(kind), "version": VERSION, "data": {"sourceKind": String(CLASSIC_HEALTH), "opcode": health_opcode, "extraCode": health_extra_code.duplicate(), "targetIds": health_target_ids.duplicate(), "nextIndex": health_next_index}}
	if kind != PARTY_DEFEAT or battle_id.is_empty() or source_kind not in [CLASSIC_COMBAT, SAFE_COMBAT] or caller == null or not caller_matches_source():
		return {}
	var caller_data := caller.to_data()
	if caller_data.is_empty():
		return {}
	return {
		"kind": String(kind),
		"version": VERSION,
		"data": {
			"battleId": battle_id,
			"sourceKind": String(source_kind),
			"caller": caller_data,
		},
	}


static func from_data(value: Variant) -> ScenarioRuntimeHandoff:
	if not value is Dictionary or value.size() != 3 or not value.get("kind") is String or _integer(value.get("version")) != VERSION or not value.get("data") is Dictionary or value["kind"] != String(PARTY_DEFEAT):
		return null
	var data: Dictionary = value["data"]
	if data.get("sourceKind") == String(CLASSIC_HEALTH):
		if data.size() != 5 or _integer(data.get("opcode")) == null or not data.get("extraCode") is Array or not data.get("targetIds") is Array or _integer(data.get("nextIndex")) == null:
			return null
		var extra: Array[int] = []
		for entry: Variant in data["extraCode"]:
			if _integer(entry) == null:
				return null
			extra.append(int(entry))
		var ids: Array[String] = []
		for entry: Variant in data["targetIds"]:
			if not entry is String:
				return null
			ids.append(entry)
		var health := health_defeat(int(data["opcode"]), extra, ids, int(data["nextIndex"]))
		return health if health.health_fields_are_valid() else null
	if data.size() != 3 or not data.get("battleId") is String or data["battleId"].is_empty() or not data.get("sourceKind") is String or data["sourceKind"] not in [String(CLASSIC_COMBAT), String(SAFE_COMBAT)]:
		return null
	var parsed_caller := ScenarioBattleCaller.from_data(data.get("caller"))
	if parsed_caller == null:
		return null
	var result := party_defeat(data["battleId"], StringName(data["sourceKind"]), parsed_caller)
	return result if result.caller_matches_source() else null


func caller_matches_source() -> bool:
	if caller == null:
		return false
	return source_kind == SAFE_COMBAT and caller.kind == ScenarioBattleCaller.SAFE or source_kind == CLASSIC_COMBAT and caller.kind == ScenarioBattleCaller.CLASSIC


func health_fields_are_valid() -> bool:
	if not battle_id.is_empty() or caller != null or health_opcode not in [15, 16] or health_extra_code.size() != 5 or health_target_ids.is_empty() or health_next_index <= 0 or health_next_index > health_target_ids.size():
		return false
	var unique_ids := {}
	for id: String in health_target_ids:
		if id.is_empty() or unique_ids.has(id):
			return false
		unique_ids[id] = true
	return true


static func _integer(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return null
