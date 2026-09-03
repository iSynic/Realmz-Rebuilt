class_name SafeExpressionDefinition
extends RefCounted

enum Kind {
	LITERAL,
	VARIABLE,
	ARRAY,
	RECORD,
	UNARY,
	BINARY,
	MEMBER,
	COLLECTION,
}

var kind: Kind
var value: Variant
var scope: StringName = &""
var state_scope: String = ""
var owner_id: String = ""
var name: String = ""
var operator: StringName = &""
var operand: SafeExpressionDefinition
var left: SafeExpressionDefinition
var right: SafeExpressionDefinition
var object: SafeExpressionDefinition
var member: String = ""
var collection: SafeExpressionDefinition
var item_name: String = ""
var predicate: SafeExpressionDefinition
var _values: Array[SafeExpressionDefinition] = []
var _fields: Dictionary = {}


func _init(expression_kind: Kind) -> void:
	kind = expression_kind


func values() -> Array[SafeExpressionDefinition]:
	return _values.duplicate()


func set_values(entries: Array[SafeExpressionDefinition]) -> void:
	_values = entries.duplicate()


func field_names() -> Array[String]:
	var names: Array[String] = []
	for field_name: Variant in _fields.keys():
		names.append(String(field_name))
	names.sort()
	return names


func field(field_name: String) -> SafeExpressionDefinition:
	return _fields.get(field_name) as SafeExpressionDefinition


func set_fields(fields: Dictionary) -> void:
	_fields = fields.duplicate()
