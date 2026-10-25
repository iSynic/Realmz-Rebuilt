## Holds native state shared by every invocation under the one execution runner.
class_name ScenarioClassicExecutionState
extends RefCounted

const ENCOUNTER_KINDS: Array[StringName] = [&"", &"simple", &"complex"]

var header := ClassicExecutionState.new()
var code: ScenarioClassicProgramState
var gosub: bool = false
var returns: Array[ScenarioClassicReturnRecord] = []
var encounter_kind: StringName = &""
var encounter_id: int = -1
var encounter_attempt: int = 0
var repeat_encounter: bool = false
var encounter_remaining: int = 0
var macro_monster_index: int = 0
var battle_macro_active: bool = false


func to_data() -> Dictionary:
	var saved_returns: Array[Dictionary] = []
	for entry: ScenarioClassicReturnRecord in returns:
		saved_returns.append(entry.to_data())
	return {"header": header.to_data(), "code": null if code == null else code.to_data(), "gosub": gosub, "returns": saved_returns, "encounterKind": String(encounter_kind), "encounterId": encounter_id, "encounterAttempt": encounter_attempt, "repeatEncounter": repeat_encounter, "encounterRemaining": encounter_remaining, "macroMonsterIndex": macro_monster_index, "battleMacroActive": battle_macro_active}


static func from_data(value: Variant) -> ScenarioClassicExecutionState:
	if not ScenarioExecutionWire.fields(value, ["header", "code", "gosub", "returns", "encounterKind", "encounterId", "encounterAttempt", "repeatEncounter", "encounterRemaining", "macroMonsterIndex", "battleMacroActive"]):
		return null
	var data: Dictionary = value
	if not data["gosub"] is bool or not data["repeatEncounter"] is bool or not data["battleMacroActive"] is bool or not data["returns"] is Array or not data["encounterKind"] is String or data["encounterKind"] not in ["", "simple", "complex"]:
		return null
	var saved_returns: Array = data["returns"]
	if saved_returns.size() > 20:
		return null
	var result := ScenarioClassicExecutionState.new()
	result.header = ClassicExecutionState.from_data(data["header"])
	result.gosub = data["gosub"]
	result.repeat_encounter = data["repeatEncounter"]
	var kind: String = data["encounterKind"]
	result.encounter_kind = StringName(kind)
	result.encounter_id = ScenarioExecutionWire.integer(data["encounterId"], -1)
	result.encounter_attempt = ScenarioExecutionWire.integer(data["encounterAttempt"])
	result.encounter_remaining = ScenarioExecutionWire.integer(data["encounterRemaining"], -32768, 32767)
	result.macro_monster_index = ScenarioExecutionWire.integer(data["macroMonsterIndex"], -1, 99)
	result.battle_macro_active = data["battleMacroActive"]
	if result.encounter_remaining < -32768 or result.macro_monster_index < -1: return null
	if result.header == null or result.encounter_id < -1 or result.encounter_attempt < 0 or (kind.is_empty() != (result.encounter_id == -1)) or (kind.is_empty() and (result.encounter_attempt != 0 or result.repeat_encounter)):
		return null
	if data["code"] != null:
		result.code = ScenarioClassicProgramState.from_data(data["code"])
		if result.code == null:
			return null
	for entry: Variant in saved_returns:
		var restored := ScenarioClassicReturnRecord.from_data(entry)
		if restored == null:
			return null
		result.returns.append(restored)
	if result.code == null and not result.returns.is_empty():
		return null
	return result
