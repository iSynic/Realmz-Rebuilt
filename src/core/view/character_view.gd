class_name CharacterView
extends RefCounted

var id: String
var name: String
var current_health: int
var maximum_health: int
var spell_points: int
var maximum_spell_points: int
var level: int
var experience: int
var condition_values: Array[int]
var item_ids: Array[String]


func _init(character: CharacterState) -> void:
	id = character.id
	name = character.name
	current_health = character.current_health
	maximum_health = character.maximum_health
	spell_points = character.spell_points
	maximum_spell_points = character.maximum_spell_points
	level = character.level
	experience = character.experience
	condition_values = character.conditions.values()
	for item: ItemInstance in character.inventory():
		item_ids.append(item.id)
