class_name CharacterState
extends RefCounted

var id: String
var name: String
var current_health: int
var maximum_health: int


func _init(character_id: String, character_name: String, health: int, max_health: int) -> void:
	id = character_id
	name = character_name
	current_health = health
	maximum_health = max_health


func to_data() -> Dictionary:
	return {"id": id, "name": name, "currentHealth": current_health, "maximumHealth": maximum_health}


static func from_data(data: Variant) -> CharacterState:
	if not data is Dictionary:
		return null
	for field: String in ["id", "name", "currentHealth", "maximumHealth"]:
		if not data.has(field):
			return null
	if not data["id"] is String or data["id"].is_empty() or not data["name"] is String:
		return null
	var health := _integer(data["currentHealth"])
	var maximum := _integer(data["maximumHealth"])
	if health < 0 or maximum < 1:
		return null
	if health > maximum:
		return null
	return CharacterState.new(data["id"], data["name"], health, maximum)


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1
