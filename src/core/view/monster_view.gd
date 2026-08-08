class_name MonsterView
extends RefCounted

var id: String
var definition_id: String
var name: String
var current_health: int
var maximum_health: int
var traitor: bool
var icon_id: int
var icon_resource_type: String = "CICN"


func _init(monster: MonsterState) -> void:
	id = monster.id
	definition_id = monster.definition_id
	name = monster.name
	current_health = monster.current_health
	maximum_health = monster.maximum_health
	traitor = monster.traitor
	icon_id = monster.icon_id
