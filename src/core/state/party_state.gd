class_name PartyState
extends RefCounted

var map_id: String
var coordinate: Vector2i
var _characters: Array[CharacterState]


func _init(location_map_id: String, location: Vector2i, party_characters: Array[CharacterState]) -> void:
	map_id = location_map_id
	coordinate = location
	_characters = party_characters.duplicate()


func characters() -> Array[CharacterState]:
	return _characters.duplicate()


func to_data() -> Dictionary:
	var character_data: Array[Dictionary] = []
	for character: CharacterState in _characters:
		character_data.append(character.to_data())
	return {"mapId": map_id, "x": coordinate.x, "y": coordinate.y, "characters": character_data}


static func from_data(data: Variant) -> PartyState:
	if not data is Dictionary:
		return null
	for field: String in ["mapId", "x", "y", "characters"]:
		if not data.has(field):
			return null
	if not data["mapId"] is String or data["mapId"].is_empty():
		return null
	var x := _integer(data["x"])
	var y := _integer(data["y"])
	if x < 0 or y < 0 or not data["characters"] is Array:
		return null
	var loaded_characters: Array[CharacterState] = []
	for character_data: Variant in data["characters"]:
		var character := CharacterState.from_data(character_data)
		if character == null:
			return null
		loaded_characters.append(character)
	if loaded_characters.is_empty():
		return null
	return PartyState.new(data["mapId"], Vector2i(x, y), loaded_characters)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
