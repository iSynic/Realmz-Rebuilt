class_name BattleMonsterSlotDefinition
extends RefCounted

var coordinate: Vector2i
var monster_id: String
var invert_traitor: bool


func _init(position: Vector2i, definition_id: String, invert: bool) -> void:
	coordinate = position
	monster_id = definition_id
	invert_traitor = invert
