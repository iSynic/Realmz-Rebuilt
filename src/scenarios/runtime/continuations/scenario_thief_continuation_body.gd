## Carries a Classic thief encounter, pick-lock attempt, or staged result.

class_name ScenarioThiefContinuationBody
extends ScenarioRuntimeContinuationBody

var encounter_id: int
var encounter_attempt: int = 0
var gosub: bool
var action_index: int = -1
var character_id: String
var phase: StringName
var succeeded: bool
var trap_pending: bool


func wire_payload() -> Dictionary:
	var data := {"encounterId": encounter_id, "gosub": gosub}
	if encounter_attempt > 0:
		data["encounterAttempt"] = encounter_attempt
	if action_index >= 0:
		data["actionIndex"] = action_index
		data["characterId"] = character_id
	if not phase.is_empty():
		data["phase"] = String(phase)
		data["succeeded"] = succeeded
		data["trapPending"] = trap_pending
	return data
