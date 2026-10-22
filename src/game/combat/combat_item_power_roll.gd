## Retains an instance's already-drawn power until consumption or activation end.
class_name CombatItemPowerRoll
extends RefCounted

var instance_id: String
var definition_id: String
var power: int


func _init(instance: String, definition: String, value: int) -> void:
	instance_id = instance
	definition_id = definition
	power = value


func to_data() -> Dictionary:
	return {"instanceId": instance_id, "definitionId": definition_id, "power": power}


static func from_data(data: Variant) -> CombatItemPowerRoll:
	if not data is Dictionary:
		return null
	var record: Dictionary = data
	if record.size() != 3 or not record.get("instanceId") is String or not record.get("definitionId") is String:
		return null
	var raw_value: Variant = record.get("power")
	if not (raw_value is int or raw_value is float):
		return null
	var value: float = raw_value
	if not is_finite(value) or value != floor(value):
		return null
	var instance: String = record["instanceId"]
	var definition: String = record["definitionId"]
	if instance.is_empty() or definition.is_empty() or value < 1 or value > 7:
		return null
	return CombatItemPowerRoll.new(instance, definition, int(value))
