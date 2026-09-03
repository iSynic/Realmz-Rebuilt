class_name CharacterSpellOptionView
extends RefCounted

var id: String
var classic_id: int
var name: String
var description: String
var level: int
var selection_cost: int
var selected: bool
var animation_resource_type: String = "cicn"
var animation_resource_ids: Array[int] = []


func _init(spell: SpellDefinition, cost: int, is_selected: bool) -> void:
	id = spell.id
	classic_id = spell.classic_id
	name = spell.name
	description = spell.description
	level = spell.classic_tier() + 1
	selection_cost = cost
	selected = is_selected
	var first_resource_id := 12_032 if spell.look_end == 0 else 11_992 + spell.look_end * 8
	for frame_offset: int in 8:
		animation_resource_ids.append(first_resource_id + frame_offset)
