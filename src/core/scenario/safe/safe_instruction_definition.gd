class_name SafeInstructionDefinition
extends RefCounted

enum Kind {
	OPERATION,
	CALL_ACTION,
	SET_VALUE,
	JUMP_IF_FALSE,
	JUMP,
	BEGIN_FOR_EACH,
	NEXT_FOR_EACH,
	RETURN,
	HALT,
}

var kind: Kind
var capability: String = ""
var action_id: String = ""
var result_target: String = ""
var scope: StringName = &""
var state_scope: String = ""
var owner_id: String = ""
var name: String = ""
var value: SafeExpressionDefinition
var condition: SafeExpressionDefinition
var target: int = 0
var item_name: String = ""
var collection: SafeExpressionDefinition
var outcome: Variant
var _arguments: Dictionary = {}


func _init(instruction_kind: Kind) -> void:
	kind = instruction_kind


func set_arguments(arguments: Dictionary) -> void:
	_arguments = arguments.duplicate()


func argument_names() -> Array[String]:
	var names: Array[String] = []
	for argument_name: Variant in _arguments.keys():
		names.append(String(argument_name))
	names.sort()
	return names


func argument(argument_name: String) -> SafeExpressionDefinition:
	return _arguments.get(argument_name) as SafeExpressionDefinition
