class_name TreasureDefinition
extends RefCounted

var id: String
var classic_id: int
var experience: int
var gold: int
var gems: int
var jewelry: int
var _item_ids: Array[String]


func _init(definition_id: String, native_id: int, treasure_item_ids: Array[String], experience_value: int = 0, gold_value: int = 0, gem_value: int = 0, jewelry_value: int = 0) -> void:
	id = definition_id
	classic_id = native_id
	_item_ids = treasure_item_ids.duplicate()
	experience = experience_value
	gold = gold_value
	gems = gem_value
	jewelry = jewelry_value


func item_ids() -> Array[String]:
	return _item_ids.duplicate()
