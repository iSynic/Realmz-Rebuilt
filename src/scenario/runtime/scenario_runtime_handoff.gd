class_name ScenarioRuntimeHandoff
extends RefCounted

const VERSION: int = 1
const PARTY_DEFEAT: StringName = &"party-defeat"
const CLASSIC_COMBAT: StringName = &"classic-combat"
const SAFE_COMBAT: StringName = &"safe-combat"

var kind: StringName
var battle_id: String
var source_kind: StringName
var caller: ScenarioBattleCaller


func _init(handoff_kind: StringName = &"") -> void:
	kind = handoff_kind


static func party_defeat(battle: String, source: StringName, battle_caller: ScenarioBattleCaller) -> ScenarioRuntimeHandoff:
	var result := ScenarioRuntimeHandoff.new(PARTY_DEFEAT)
	result.battle_id = battle
	result.source_kind = source
	result.caller = battle_caller.copy() if battle_caller != null else null
	return result


func copy() -> ScenarioRuntimeHandoff:
	var duplicate := from_data(to_data())
	assert(duplicate != null, "A live typed runtime handoff must round-trip through its wire codec")
	return duplicate


func to_data() -> Dictionary:
	if kind != PARTY_DEFEAT or battle_id.is_empty() or source_kind not in [CLASSIC_COMBAT, SAFE_COMBAT] or caller == null or not _caller_matches_source():
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
	if data.size() != 3 or not data.get("battleId") is String or data["battleId"].is_empty() or not data.get("sourceKind") is String or data["sourceKind"] not in [String(CLASSIC_COMBAT), String(SAFE_COMBAT)]:
		return null
	var parsed_caller := ScenarioBattleCaller.from_data(data.get("caller"))
	if parsed_caller == null:
		return null
	var result := party_defeat(data["battleId"], StringName(data["sourceKind"]), parsed_caller)
	return result if result._caller_matches_source() else null


func _caller_matches_source() -> bool:
	if caller == null:
		return false
	return source_kind == SAFE_COMBAT and caller.kind == ScenarioBattleCaller.SAFE or source_kind == CLASSIC_COMBAT and caller.kind == ScenarioBattleCaller.CLASSIC


static func _integer(value: Variant) -> Variant:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return null
