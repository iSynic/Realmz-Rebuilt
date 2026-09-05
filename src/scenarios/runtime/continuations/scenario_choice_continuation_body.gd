## Carries Safe, Classic, or encounter choice progress.

class_name ScenarioChoiceContinuationBody
extends ScenarioRuntimeContinuationBody

var option_count: int
var values: Array[int]
var gosub: bool
var encounter_id: int = -1
var encounter_attempt: int = 0
var option_indexes: Array[int]


func wire_payload() -> Dictionary:
	if option_count > 0:
		return {"optionCount": option_count}
	if encounter_id >= 0:
		var data := {"encounterId": encounter_id, "gosub": gosub}
		if encounter_attempt > 0:
			data["encounterAttempt"] = encounter_attempt
		if not option_indexes.is_empty():
			data["optionIndexes"] = option_indexes.duplicate()
		return data
	return {"values": values.duplicate(), "gosub": gosub}
