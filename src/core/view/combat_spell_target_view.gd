class_name CombatSpellTargetView
extends RefCounted

var id: String
var kind: StringName
var name: String
var current_health: int
var maximum_health: int


func _init(target_id: String, target_kind: StringName, display_name: String, health: int, maximum: int) -> void:
	id = target_id
	kind = target_kind
	name = display_name
	current_health = health
	maximum_health = maximum
