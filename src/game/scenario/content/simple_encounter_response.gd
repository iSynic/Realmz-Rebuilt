## Defines the immutable simple encounter response record loaded from campaign content.

class_name SimpleEncounterResponse
extends RefCounted

var id: String
var label: String
var result_program_id: String


func _init(response_id: String, response_label: String, program_id: String) -> void:
	id = response_id
	label = response_label
	result_program_id = program_id


func is_classic_eliminated(encounter_id: int) -> bool:
	return result_program_id == "simple:%d:result:-1" % encounter_id
