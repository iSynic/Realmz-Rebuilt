class_name MapPresentationDelta
extends RefCounted

var map_id: String
var from_coordinate: Vector2i
var to_coordinate: Vector2i
var viewport_shift: Vector2i
var newly_visited: Array[Vector2i]
var newly_seen: Array[Vector2i]
var visibility_changed: Array[Vector2i]
var entered: Array[Vector2i]
var exited: Array[Vector2i]
var changed: Array[Vector2i]
var complete_window_rebuild: bool = false


func _init(delta_map_id: String, origin: Vector2i, destination: Vector2i, visited: Array[Vector2i] = [], seen: Array[Vector2i] = [], changed_visibility: Array[Vector2i] = []) -> void:
	map_id = delta_map_id
	from_coordinate = origin
	to_coordinate = destination
	viewport_shift = destination - origin
	newly_visited = visited.duplicate()
	newly_seen = seen.duplicate()
	visibility_changed = changed_visibility.duplicate()
	changed = changed_visibility.duplicate()
	if not changed.has(destination):
		changed.append(destination)


func matches(previous_map_id: String, previous_coordinate: Vector2i, current_coordinate: Vector2i) -> bool:
	return map_id == previous_map_id and from_coordinate == previous_coordinate and to_coordinate == current_coordinate and viewport_shift != Vector2i.ZERO
