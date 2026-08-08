class_name SpellView
extends RefCounted

var id: String
var classic_id: int
var name: String
var cost: int
var description: String
var spell_class: int
var range_min: int
var range_max: int
var duration_min: int
var duration_max: int
var target_type: int
var castable_in_combat: bool
var castable_in_camp: bool
var icon_id: int
var icon_resource_type: String = "CICN"


func _init(definition: SpellDefinition) -> void:
	id = definition.id
	classic_id = definition.classic_id
	name = definition.name
	cost = definition.cost
	description = definition.description
	spell_class = definition.spell_class
	range_min = definition.range_min
	range_max = definition.range_max
	duration_min = definition.duration_min
	duration_max = definition.duration_max
	target_type = definition.target_type
	castable_in_combat = definition.in_combat
	castable_in_camp = definition.in_camp
	icon_id = definition.queue_icon
