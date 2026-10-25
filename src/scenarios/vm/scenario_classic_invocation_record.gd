## Retains one newland call's local cursor, entry mode, guards and encounter exit.
class_name ScenarioClassicInvocationRecord
extends RefCounted

enum Mode { PLACED, MODE_ONE, MACRO, DEBUG }
enum Phase { ENTRY, CODE, ENCOUNTER, COMPLETE }

var mode: Mode = Mode.PLACED
var phase: Phase = Phase.ENTRY
var cursor: int = 0
var native_slot: int = 0
var position_program_id: String = ""
## Empty retains unavailable legacy entry history; new invocations always name it.
var entry_program_id: String = ""
var placed_trigger_id: String = ""
var completion := ScenarioNativeCompletion.new()
var position_kind: ScenarioClassicProgramState.Kind = ScenarioClassicProgramState.Kind.PROGRAM
var context := ScenarioExecutionContext.empty()
var encounter_exit: ScenarioClassicReturnRecord
var secondary_door: bool = false
var no_second_door: bool = false
var returned_early: bool = false
var return_value: int = 0
var encounter_reload: bool = true
var encounter_save_id: int = -1
var queued_source: CombatQueuedMacroSource


func to_data() -> Dictionary:
	return {"mode": mode, "phase": phase, "cursor": cursor, "nativeSlot": native_slot, "positionProgramId": position_program_id, "entryProgramId": entry_program_id, "placedTriggerId":placed_trigger_id,"completion":completion.to_data(), "positionKind": position_kind, "context": ScenarioExecutionContextCodec.encode(context), "encounterExit": null if encounter_exit == null else encounter_exit.to_data(), "secondaryDoor": secondary_door, "noSecondDoor": no_second_door, "returnedEarly": returned_early, "returnValue": return_value, "encounterReload": encounter_reload, "encounterSaveId": encounter_save_id, "queuedSource":null if queued_source == null else queued_source.to_data()}


static func from_data(value: Variant) -> ScenarioClassicInvocationRecord:
	if not ScenarioExecutionWire.fields(value, ["mode", "phase", "cursor", "nativeSlot", "positionProgramId", "entryProgramId", "placedTriggerId", "completion", "positionKind", "context", "encounterExit", "secondaryDoor", "noSecondDoor", "returnedEarly", "returnValue", "encounterReload", "encounterSaveId", "queuedSource"]):
		return null
	var data: Dictionary = value
	var restored_mode := ScenarioExecutionWire.integer(data["mode"], Mode.PLACED, Mode.DEBUG)
	var restored_phase := ScenarioExecutionWire.integer(data["phase"], Phase.ENTRY, Phase.COMPLETE)
	if restored_mode < 0 or restored_phase < 0 or not data["positionProgramId"] is String or not data["entryProgramId"] is String or not data["placedTriggerId"] is String:
		return null
	for field: String in ["secondaryDoor", "noSecondDoor", "returnedEarly", "encounterReload"]:
		if not data[field] is bool:
			return null
	var result := ScenarioClassicInvocationRecord.new()
	result.mode = restored_mode as Mode
	result.phase = restored_phase as Phase
	result.cursor = ScenarioExecutionWire.integer(data["cursor"], 0, 4096)
	result.native_slot = ScenarioExecutionWire.integer(data["nativeSlot"], 0, 8)
	result.position_program_id = data["positionProgramId"]
	result.entry_program_id = data["entryProgramId"]
	result.placed_trigger_id = data["placedTriggerId"]
	result.completion = ScenarioNativeCompletion.from_data(data["completion"])
	if result.entry_program_id.length() > 256 or result.placed_trigger_id.length() > 256 or result.completion == null: return null
	if not result.placed_trigger_id.is_empty() and result.mode != Mode.PLACED: return null
	if result.completion.exit_path != ScenarioNativeCompletion.Exit.NONE and result.phase != Phase.COMPLETE: return null
	if result.completion.remove_selected_ap and result.placed_trigger_id.is_empty(): return null
	var code_kind := ScenarioExecutionWire.integer(data["positionKind"], ScenarioClassicProgramState.Kind.PROGRAM, ScenarioClassicProgramState.Kind.KEEP_CODES)
	if code_kind < 0: return null
	result.position_kind = code_kind as ScenarioClassicProgramState.Kind
	result.context = ScenarioExecutionContextCodec.decode(data["context"])
	result.secondary_door = data["secondaryDoor"]
	result.no_second_door = data["noSecondDoor"]
	result.returned_early = data["returnedEarly"]
	result.return_value = ScenarioExecutionWire.integer(data["returnValue"], -1, 1)
	if result.return_value < -1 or result.return_value != 0 and (not result.returned_early or result.phase != Phase.COMPLETE): return null
	if result.completion.exit_path == ScenarioNativeCompletion.Exit.NATIVE_RETURN and not result.returned_early: return null
	if result.completion.backout != ScenarioNativeCompletion.Backout.NONE and result.return_value != 1: return null
	if not result.placed_trigger_id.is_empty() and (result.context == null or result.context.trigger_id != result.placed_trigger_id): return null
	result.encounter_reload = data["encounterReload"]
	result.encounter_save_id = ScenarioExecutionWire.integer(data["encounterSaveId"], -2, 32767)
	if result.encounter_save_id < -2: return null
	if data["queuedSource"] != null:
		result.queued_source = CombatQueuedMacroSource.from_data(data["queuedSource"])
		if result.queued_source == null or result.mode != Mode.MACRO: return null
	if result.cursor < 0 or result.native_slot < 0 or result.context == null or (result.position_program_id.is_empty() and result.position_kind == ScenarioClassicProgramState.Kind.PROGRAM and result.phase not in [Phase.ENCOUNTER, Phase.COMPLETE]):
		return null
	if data["encounterExit"] != null:
		result.encounter_exit = ScenarioClassicReturnRecord.from_data(data["encounterExit"])
		if result.encounter_exit == null:
			return null
	return result


func execution_context(code_context: ScenarioExecutionContext) -> ScenarioExecutionContext:
	var result := code_context.copy()
	# newland's mode/data and caller facts belong to the invocation even when
	# a nested call leaves another record's code in the shared infodoor.
	result.calling_context = context.calling_context
	result.trigger_id = context.trigger_id
	result.map_id = context.map_id
	result.coordinate = context.coordinate
	result.has_coordinate = context.has_coordinate
	result.timed_encounter_id = context.timed_encounter_id
	result.random_region_id = context.random_region_id
	result.application_hook = context.application_hook
	result.service_id = context.service_id
	result.has_service_id = context.has_service_id
	result.battle_id = context.battle_id
	result.combatant_id = context.combatant_id
	result.classic_monster_id = context.classic_monster_id
	result.has_classic_monster_id = context.has_classic_monster_id
	result.traitor = context.traitor
	result.has_traitor = context.has_traitor
	return result
