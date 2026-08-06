class_name RandomRegionState
extends RefCounted

var id: String
var chance_percent: int
var battle_minimum: int
var battle_maximum: int


func _init(region_id: String, chance: int, battle_min: int, battle_max: int) -> void:
	id = region_id
	chance_percent = clampi(chance, 0, 100)
	battle_minimum = battle_min
	battle_maximum = battle_max


func to_data() -> Dictionary:
	return {"id": id, "chancePercent": chance_percent, "battleMinimum": battle_minimum, "battleMaximum": battle_maximum}


static func from_data(data: Variant) -> RandomRegionState:
	if not data is Dictionary:
		return null
	for field: String in ["id", "chancePercent", "battleMinimum", "battleMaximum"]:
		if not data.has(field):
			return null
	if not data["id"] is String or data["id"].is_empty():
		return null
	var chance := _integer(data["chancePercent"])
	var battle_min := _signed_integer(data["battleMinimum"])
	var battle_max := _signed_integer(data["battleMaximum"])
	if chance < 0 or chance > 100 or battle_min == -100_000 or battle_max == -100_000:
		return null
	return RandomRegionState.new(data["id"], chance, battle_min, battle_max)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
