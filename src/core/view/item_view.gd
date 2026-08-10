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
var icon_id: int
var icon_resource_type: String = "CICN"
var item_type: int
var actions := InventoryItemActionsView.new()


func _init(instance: ItemInstance, definition: ItemDefinition) -> void:
	instance_id = instance.id
	charges = instance.charges
	equipped = instance.equipped
	identified = instance.identified
	if definition == null:
		classic_id = 0
		definition_id = ""
		name = "Unknown item"
		description = "Definition unavailable"
		return
	icon_id = definition.icon_id
	item_type = definition.item_type
	name = definition.name if identified else definition.unidentified_name
	usable = definition.initial_charges > 0
	weight = definition.instance_weight(instance.charges)
	description = definition.description if identified else "This item's properties are unknown until it is identified."
	value = definition.cost if identified else 0
	definition_id = definition.id if identified else ""
	classic_id = definition.classic_id if identified else 0
