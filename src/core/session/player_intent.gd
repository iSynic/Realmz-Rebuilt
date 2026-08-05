class_name PlayerIntent
extends RefCounted

enum Kind {
	MOVE,
	SEARCH,
	CAMP,
	USE_ITEM,
	CAST_SPELL,
	CHOOSE_COMBAT_ACTION,
}

var kind: Kind
var arguments: Dictionary


func _init(intent_kind: Kind, intent_arguments: Dictionary = {}) -> void:
	kind = intent_kind
	arguments = intent_arguments.duplicate(true)
