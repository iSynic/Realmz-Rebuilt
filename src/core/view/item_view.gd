class_name ItemView
extends RefCounted

var instance_id: String
var definition_id: String
var classic_id: int
var name: String
var charges: int
var equipped: bool
var identified: bool
var usable: bool
var weight: int
var description: String
var value: int
var restriction_reason: String = ""


func _init(instance: ItemInstance, definition: ItemDefinition) -> void:
	instance_id = instance.id
	definition_id = instance.definition_id
	charges = instance.charges
	equipped = instance.equipped
	identified = instance.identified
	if definition == null:
		classic_id = 0
		name = instance.definition_id
		description = "Definition unavailable"
		return
	classic_id = definition.classic_id
	name = definition.name
	usable = definition.initial_charges > 0
	weight = definition.instance_weight(instance.charges)
	description = definition.description
	value = definition.cost
