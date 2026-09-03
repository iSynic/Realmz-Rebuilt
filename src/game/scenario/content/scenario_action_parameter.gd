class_name ScenarioActionParameter
extends RefCounted

var name: String
var value_type: StringName
var max_length: int


func _init(parameter_name: String, parameter_type: StringName, parameter_max_length: int = -1) -> void:
	name = parameter_name
	value_type = parameter_type
	max_length = parameter_max_length
