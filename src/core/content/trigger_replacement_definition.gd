class_name TriggerReplacementDefinition
extends RefCounted

var door_id: int
var terrain_id: int
var target_coordinate: Vector2i


func _init(replacement_door_id: int, replacement_terrain_id: int, replacement_target: Vector2i) -> void:
	door_id = replacement_door_id
	terrain_id = replacement_terrain_id
	target_coordinate = replacement_target


func changes_terrain() -> bool:
	return terrain_id > 0
