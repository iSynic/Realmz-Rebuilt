## Retains the explicit native control values required by the Party Death safety return.
class_name ScenarioClassicCallerState
extends RefCounted

var code: ScenarioClassicProgramState
var returns: Array[ScenarioClassicReturnRecord] = []
var gosub: bool = false
var encounter_kind: StringName = &""
var encounter_id: int = -1
var encounter_attempt: int = 0
var repeat_encounter: bool = false
var encounter_remaining: int = 0
var macro_monster_index: int = 0
var battle_macro_active: bool = false


static func capture(shared: ScenarioClassicExecutionState) -> ScenarioClassicCallerState:
	var result := ScenarioClassicCallerState.new()
	result.code = shared.code.copy() if shared.code != null else null
	for saved: ScenarioClassicReturnRecord in shared.returns: result.returns.append(saved.copy())
	result.gosub = shared.gosub
	result.encounter_kind = shared.encounter_kind
	result.encounter_id = shared.encounter_id
	result.encounter_attempt = shared.encounter_attempt
	result.repeat_encounter = shared.repeat_encounter
	result.encounter_remaining = shared.encounter_remaining
	result.macro_monster_index = shared.macro_monster_index
	result.battle_macro_active = shared.battle_macro_active
	return result


func restore_into(shared: ScenarioClassicExecutionState) -> void:
	# FD-SCENARIO-026 retains the suspended control, never a stale live header.
	shared.code = code.copy() if code != null else null
	shared.returns.clear()
	for saved: ScenarioClassicReturnRecord in returns: shared.returns.append(saved.copy())
	shared.gosub = gosub
	shared.encounter_kind = encounter_kind
	shared.encounter_id = encounter_id
	shared.encounter_attempt = encounter_attempt
	shared.repeat_encounter = repeat_encounter
	shared.encounter_remaining = encounter_remaining
	shared.macro_monster_index = macro_monster_index
	shared.battle_macro_active = battle_macro_active


func to_data() -> Dictionary:
	var saved: Array[Dictionary] = []
	for entry: ScenarioClassicReturnRecord in returns: saved.append(entry.to_data())
	return {"code": null if code == null else code.to_data(), "returns": saved, "gosub": gosub, "encounterKind": String(encounter_kind), "encounterId": encounter_id, "encounterAttempt": encounter_attempt, "repeatEncounter": repeat_encounter, "encounterRemaining": encounter_remaining, "macroMonsterIndex": macro_monster_index, "battleMacroActive": battle_macro_active}


static func from_data(value: Variant) -> ScenarioClassicCallerState:
	if not ScenarioExecutionWire.fields(value, ["code", "returns", "gosub", "encounterKind", "encounterId", "encounterAttempt", "repeatEncounter", "encounterRemaining", "macroMonsterIndex", "battleMacroActive"]): return null
	var data: Dictionary = value
	var detached := data.duplicate(true)
	detached["header"] = ClassicExecutionState.new().to_data()
	var shared := ScenarioClassicExecutionState.from_data(detached)
	return null if shared == null else capture(shared)
