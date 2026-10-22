## Retains opcode 63's age acknowledgements and nested midnight timer scan.
class_name ScenarioClockContinuationBody
extends ScenarioRuntimeContinuationBody

var updates: Array[AgeUpdateRequestBody] = []
var age_index: int = 0
var scan_pending: bool = false
var timer_index: int = 0
var program_id: String = ""
var timer_vm: ScenarioVmSnapshot
var resume_slot: int = 0
var return_program_id: String = ""


func as_continuation() -> ScenarioRuntimeContinuation:
	return ScenarioRuntimeContinuation.new(ScenarioRuntimeContinuation.CLASSIC_CLOCK, self)


func wire_payload() -> Dictionary:
	var age_data: Array[Dictionary] = []
	for update: AgeUpdateRequestBody in updates:
		age_data.append(update.to_data())
	return {"updates": age_data, "ageIndex": age_index, "scanPending": scan_pending, "timerIndex": timer_index, "programId": program_id, "timerVm": {} if timer_vm == null else timer_vm.to_data(), "resumeSlot": resume_slot, "returnProgramId": return_program_id}
