class_name RandomRegionState
extends RefCounted

var id: String
var chance_ten_thousand: int
var battle_minimum: int
var battle_maximum: int
var _random_door_percents: Array[int]


func _init(region_id: String, chance: int, battle_min: int, battle_max: int, door_percents: Array[int] = []) -> void:
	id = region_id
	chance_ten_thousand = chance
	battle_minimum = battle_min
	battle_maximum = battle_max
	_random_door_percents = door_percents.duplicate()


func random_door_percents() -> Array[int]:
	return _random_door_percents.duplicate()


func consume_random_door(index: int) -> void:
	if index >= 0 and index < _random_door_percents.size() and _random_door_percents[index] > 0:
		_random_door_percents[index] = 0


func to_data() -> Dictionary:
	return {"id": id, "chanceTenThousand": chance_ten_thousand, "battleMinimum": battle_minimum, "battleMaximum": battle_maximum, "randomDoorPercent": _random_door_percents.duplicate()}


static func from_data(data: Variant) -> RandomRegionState:
	if not data is Dictionary:
		return null
	for field: String in ["id", "chanceTenThousand", "battleMinimum", "battleMaximum", "randomDoorPercent"]:
		if not data.has(field):
			return null
	if not data["id"] is String or data["id"].is_empty():
		return null
	var chance := _signed_integer(data["chanceTenThousand"])
	var battle_min := _signed_integer(data["battleMinimum"])
	var battle_max := _signed_integer(data["battleMaximum"])
	if chance == -100_000 or battle_min == -100_000 or battle_max == -100_000 or not data["randomDoorPercent"] is Array or data["randomDoorPercent"].size() != 3:
		return null
	var door_percents: Array[int] = []
	for value: Variant in data["randomDoorPercent"]:
		var percent := _signed_integer(value)
		if percent == -100_000:
			return null
		door_percents.append(percent)
	return RandomRegionState.new(data["id"], chance, battle_min, battle_max, door_percents)


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
