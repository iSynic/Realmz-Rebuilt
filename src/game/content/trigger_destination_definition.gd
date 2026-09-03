class_name TriggerDestinationDefinition
extends RefCounted

var map_id: String
var coordinate: Vector2i


func _init(destination_map_id: String, destination_coordinate: Vector2i) -> void:
	map_id = destination_map_id
	coordinate = destination_coordinate
