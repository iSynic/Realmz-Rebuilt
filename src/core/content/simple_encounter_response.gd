class_name SimpleEncounterResponse
extends RefCounted

var id: String
var label: String
var result_program_id: String


func _init(response_id: String, response_label: String, program_id: String) -> void:
	id = response_id
	label = response_label
	result_program_id = program_id
