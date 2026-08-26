class_name RandomRegionState
extends RefCounted

var id: String
var chance_ten_thousand: int
var battle_minimum: int
var battle_maximum: int
var _random_door_percents: Array[int]
var bounds_left: int
var bounds_right: int
var bounds_top: int
var bounds_bottom: int
var bounds_overridden: bool


func _init(region_id: String, chance: int, battle_min: int, battle_max: int, door_percents: Array[int] = [], region_bounds: Rect2i = Rect2i(), overridden_bounds: bool = false) -> void:
	id = region_id
	chance_ten_thousand = chance
	battle_minimum = battle_min
	battle_maximum = battle_max
	_random_door_percents = door_percents.duplicate()
	bounds_left = region_bounds.position.x
	bounds_right = region_bounds.end.x - 1
	bounds_top = region_bounds.position.y
	bounds_bottom = region_bounds.end.y - 1
	bounds_overridden = overridden_bounds


func random_door_percents() -> Array[int]:
	return _random_door_percents.duplicate()


func consume_random_door(index: int) -> void:
	if index >= 0 and index < _random_door_percents.size() and _random_door_percents[index] > 0:
		_random_door_percents[index] = 0


func bounds_edges() -> Array[int]:
	return [bounds_left, bounds_right, bounds_top, bounds_bottom]


func set_bounds_edges(edges: Array[int]) -> bool:
	if edges.size() != 4:
		return false
	bounds_left = edges[0]
	bounds_right = edges[1]
	bounds_top = edges[2]
	bounds_bottom = edges[3]
	bounds_overridden = true
	return true


func contains(authored_bounds: Rect2i, coordinate: Vector2i) -> bool:
	if not bounds_overridden:
		return authored_bounds.has_point(coordinate)
	return coordinate.x >= bounds_left and coordinate.x <= bounds_right and coordinate.y >= bounds_top and coordinate.y <= bounds_bottom


func to_data() -> Dictionary:
	return {"id": id, "chanceTenThousand": chance_ten_thousand, "battleMinimum": battle_minimum, "battleMaximum": battle_maximum, "randomDoorPercent": _random_door_percents.duplicate(), "bounds": bounds_edges(), "boundsOverridden": bounds_overridden}


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
	var bounds := Rect2i()
	var overridden := false
	if data.has("bounds") or data.has("boundsOverridden"):
		if not data.get("bounds") is Array or data["bounds"].size() != 4 or not data.get("boundsOverridden") is bool:
			return null
		var edges: Array[int] = []
		for value: Variant in data["bounds"]:
			var edge := _signed_integer(value)
			if edge == -100_000:
				return null
			edges.append(edge)
		bounds = Rect2i(edges[0], edges[2], edges[1] - edges[0] + 1, edges[3] - edges[2] + 1)
		overridden = data["boundsOverridden"]
	var result := RandomRegionState.new(data["id"], chance, battle_min, battle_max, door_percents, bounds, overridden)
	if data.has("bounds"):
		result.bounds_left = int(data["bounds"][0])
		result.bounds_right = int(data["bounds"][1])
		result.bounds_top = int(data["bounds"][2])
		result.bounds_bottom = int(data["bounds"][3])
	return result


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000
