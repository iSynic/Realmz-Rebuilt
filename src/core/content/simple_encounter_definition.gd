class_name SimpleEncounterDefinition
extends RefCounted

var id: int
var prompt_message_id: int
var can_back_out: bool
var max_times: int
var caste_success: int
var _responses: Array[SimpleEncounterResponse] = []


func _init(encounter_id: int, prompt_id: int, encounter_responses: Array[SimpleEncounterResponse], back_out: bool, maximum_times: int, success_caste: int) -> void:
	id = encounter_id
	prompt_message_id = prompt_id
	_responses = encounter_responses.duplicate()
	can_back_out = back_out
	max_times = maximum_times
	caste_success = success_caste


func responses() -> Array[SimpleEncounterResponse]:
	return _responses.duplicate()


func response_at(index: int) -> SimpleEncounterResponse:
	return _responses[index] if index >= 0 and index < _responses.size() else null
