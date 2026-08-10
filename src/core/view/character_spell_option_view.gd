class_name CharacterSpellOptionView
extends RefCounted

var id: String
var classic_id: int
var name: String
var description: String
var level: int
var selection_cost: int
var selected: bool


func _init(spell: SpellDefinition, cost: int, is_selected: bool) -> void:
	id = spell.id
	classic_id = spell.classic_id
	name = spell.name
	description = spell.description
	level = spell.classic_tier() + 1
	selection_cost = cost
	selected = is_selected
