class_name SpellView
extends RefCounted

var id: String
var classic_id: int
var name: String
var cost: int


func _init(definition: SpellDefinition) -> void:
	id = definition.id
	classic_id = definition.classic_id
	name = definition.name
	cost = definition.cost
