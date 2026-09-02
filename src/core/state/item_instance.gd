class_name ItemInstance
extends RefCounted

var id: String
var definition_id: String
var equipped: bool
var identified: bool
var charges: int


func _init(instance_id: String, item_definition_id: String, charge_count: int = 0, is_equipped: bool = false, is_identified: bool = false) -> void:
	id = instance_id
	definition_id = item_definition_id
	charges = clampi(charge_count, -1, 32_767)
	equipped = is_equipped
	identified = is_identified


func to_data() -> Dictionary:
	return {"id": id, "definitionId": definition_id, "equipped": equipped, "identified": identified, "charges": charges}


static func from_data(data: Variant) -> ItemInstance:
	if not data is Dictionary:
		return null
	for field: String in ["id", "definitionId", "equipped", "identified", "charges"]:
		if not data.has(field):
			return null
	if not data["id"] is String or data["id"].is_empty() or not data["definitionId"] is String or data["definitionId"].is_empty() or not data["equipped"] is bool or not data["identified"] is bool:
		return null
	var loaded_charges := _integer(data["charges"])
	if loaded_charges < -1 or loaded_charges > 32_767:
		return null
	return ItemInstance.new(data["id"], data["definitionId"], loaded_charges, data["equipped"], data["identified"])


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
