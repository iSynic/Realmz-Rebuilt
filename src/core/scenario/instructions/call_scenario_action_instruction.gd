class_name CallScenarioActionInstruction
extends RefCounted

var action_id: String
var result_target: String
var _arguments: Dictionary = {}


func _init(target_action_id: String, arguments: Dictionary = {}, target: String = "") -> void:
	action_id = target_action_id
	result_target = target
	_arguments = arguments.duplicate()


func argument_names() -> Array[String]:
	var names: Array[String] = []
	for name: Variant in _arguments.keys():
		names.append(String(name))
	names.sort()
	return names


func argument(name: String) -> SafeExpressionDefinition:
	return _arguments.get(name) as SafeExpressionDefinition
