## Names a suspended gameplay operation and its exact execution return owner.
class_name ScenarioOperationExecutionRecord
extends RefCounted

enum Phase { RESPONSE, CHILD, CHILD_RETURN, HOST_RETURN }
enum ReturnKind { CLASSIC, SAFE, DIRECT, APPLICATION }

var phase: Phase = Phase.RESPONSE
var return_kind: ReturnKind = ReturnKind.CLASSIC
var continuation: ScenarioRuntimeContinuation
var handoff: ScenarioRuntimeHandoff
var result_target: String = ""
var instruction_program_id: String = ""
var instruction_cursor: int = -1
var restore_code: ScenarioClassicProgramState
var child_call: ScenarioProgramCall
var child_restore_code: ScenarioClassicProgramState
var restore_encounter_flag: int = -1
var child_return_value: int = 0


func to_data() -> Dictionary:
	return {"phase": phase, "returnKind": return_kind, "continuation": null if continuation == null else continuation.to_data(), "handoff": null if handoff == null else handoff.to_data(), "resultTarget": result_target, "instructionProgramId": instruction_program_id, "instructionCursor": instruction_cursor, "restoreCode": null if restore_code == null else restore_code.to_data(), "childCall": null if child_call == null else child_call.to_data(), "childRestoreCode": null if child_restore_code == null else child_restore_code.to_data(), "restoreEncounterFlag": restore_encounter_flag, "childReturnValue": child_return_value}


static func from_data(value: Variant, depth: int = 0) -> ScenarioOperationExecutionRecord:
	if not ScenarioExecutionWire.fields(value, ["phase", "returnKind", "continuation", "handoff", "resultTarget", "instructionProgramId", "instructionCursor", "restoreCode", "childCall", "childRestoreCode", "restoreEncounterFlag", "childReturnValue"]):
		return null
	var data: Dictionary = value
	var restored_phase := ScenarioExecutionWire.integer(data["phase"], Phase.RESPONSE, Phase.HOST_RETURN)
	var restored_kind := ScenarioExecutionWire.integer(data["returnKind"], ReturnKind.CLASSIC, ReturnKind.APPLICATION)
	if restored_phase < 0 or restored_kind < 0 or not data["resultTarget"] is String or not data["instructionProgramId"] is String:
		return null
	var result := ScenarioOperationExecutionRecord.new()
	result.phase = restored_phase as Phase
	result.return_kind = restored_kind as ReturnKind
	if data["continuation"] != null:
		result.continuation = ScenarioRuntimeContinuation.from_data(data["continuation"], depth)
		if result.continuation == null or result.continuation.nested_vm() != null or result.continuation.body is ScenarioClockContinuationBody: return null
		var age := result.continuation.age()
		if age != null and age.directive != null and age.directive.kind in [ScenarioVmDirective.FINISH, ScenarioVmDirective.FINISH_TIMELINE, ScenarioVmDirective.CLOCK_TIMER_RETURN, ScenarioVmDirective.BLOWOUT]: return null
	if data["handoff"] != null:
		result.handoff = ScenarioRuntimeHandoff.from_data(data["handoff"], depth)
		if result.handoff == null: return null
	result.result_target = data["resultTarget"]
	result.instruction_program_id = data["instructionProgramId"]
	result.instruction_cursor = ScenarioExecutionWire.integer(data["instructionCursor"], -1, 4095)
	result.child_return_value = ScenarioExecutionWire.integer(data["childReturnValue"], -1, 1)
	if result.child_return_value < -1 or result.child_return_value != 0 and result.phase != Phase.CHILD_RETURN: return null
	result.restore_encounter_flag = ScenarioExecutionWire.integer(data["restoreEncounterFlag"], -1, 2)
	if result.restore_encounter_flag < -1 or result.restore_encounter_flag >= 0 and (result.return_kind != ReturnKind.CLASSIC or data["restoreCode"] != null): return null
	if data["childCall"] != null:
		result.child_call = ScenarioProgramCall.from_data(data["childCall"])
		if result.child_call == null: return null
	if data["childRestoreCode"] != null:
		result.child_restore_code = ScenarioClassicProgramState.from_data(data["childRestoreCode"])
		if result.child_restore_code == null: return null
	if (result.phase == Phase.HOST_RETURN) != (result.handoff != null) or (result.phase == Phase.RESPONSE) != (result.continuation != null) or (result.phase in [Phase.CHILD, Phase.CHILD_RETURN]) != (result.child_call != null) or result.instruction_cursor < -1 or (result.instruction_program_id.is_empty() != (result.instruction_cursor == -1)):
		return null
	if result.child_restore_code != null and (result.child_call == null or not result.child_call.restores_code()): return null
	if result.child_call != null and not result.child_owner_is_valid(): return null
	if result.return_kind != ReturnKind.SAFE and not result.result_target.is_empty():
		return null
	if data["restoreCode"] != null:
		result.restore_code = ScenarioClassicProgramState.from_data(data["restoreCode"])
		if result.restore_code == null:
			return null
	return result if result.child_call == null or result.child_owner_is_valid() else null


func child_owner_is_valid() -> bool:
	if child_call.kind == ScenarioProgramCall.Kind.APPLICATION: return return_kind == ReturnKind.APPLICATION and instruction_cursor == -1 and restore_code == null and restore_encounter_flag == -1
	if child_call.kind == ScenarioProgramCall.Kind.TIMER: return return_kind == ReturnKind.CLASSIC
	if return_kind == ReturnKind.APPLICATION: return false
	var returning := child_call.macro.return_kind
	match return_kind:
		ReturnKind.DIRECT: return returning == ScenarioMacroCall.ReturnKind.DIRECT
		ReturnKind.SAFE: return returning == ScenarioMacroCall.ReturnKind.SAFE
		ReturnKind.CLASSIC: return returning in [ScenarioMacroCall.ReturnKind.CLASSIC, ScenarioMacroCall.ReturnKind.DESTRUCTION]
	return false
