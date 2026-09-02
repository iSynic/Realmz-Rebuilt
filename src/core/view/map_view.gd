class_name MapView
extends RefCounted

var map_id: String
var map_name: String
var level_type: StringName
var landlook: int
var base_scale: int
var width: int
var height: int
var party_coordinate: Vector2i
var last_move_direction: Vector2i
var dungeon_heading: int
var dungeon_multiview: bool
var coordinates_hidden: bool
var compass_enabled: bool
var wizard_eye_active: bool
var dark: bool
var darkness_level: int
var uses_los: bool
var presentation_delta: RefCounted
var map_window: RefCounted
var _cells: Array[MapCellView]
var _cells_by_coordinate: Dictionary = {}
var _visited_coordinates: Array[Vector2i] = []
var _seen_coordinates: Array[Vector2i] = []
var _visited_coordinate_set: Dictionary = {}
var _seen_coordinate_set: Dictionary = {}
var _visibility_parent: MapView
var _movement_options: Dictionary = {}


func _init(view_map_id: String, view_map_name: String, view_level_type: StringName, map_width: int, map_height: int, party_position: Vector2i, cell_views: Array[MapCellView], is_dark: bool = false, visited_cells: Array[Vector2i] = [], movement_options: Dictionary = {}, party_last_move_direction: Vector2i = Vector2i.ZERO, view_landlook: int = -1, party_dungeon_heading: int = 1, allows_dungeon_multiview: bool = true, has_wizard_eye: bool = false, view_base_scale: int = -1, hides_coordinates: bool = false, shows_compass: bool = true, saved_darkness_level: int = -1, line_of_sight_enabled: bool = false, seen_cells: Array[Vector2i] = [], delta: RefCounted = null, window: RefCounted = null) -> void:
	map_id = view_map_id
	map_name = view_map_name
	level_type = view_level_type
	landlook = view_landlook
	base_scale = view_base_scale
	width = map_width
	height = map_height
	party_coordinate = party_position
	last_move_direction = party_last_move_direction
	dungeon_heading = party_dungeon_heading
	dungeon_multiview = allows_dungeon_multiview
	coordinates_hidden = hides_coordinates
	compass_enabled = shows_compass
	wizard_eye_active = has_wizard_eye
	dark = is_dark
	darkness_level = saved_darkness_level
	uses_los = line_of_sight_enabled
	presentation_delta = delta
	map_window = window
	_cells = cell_views.duplicate()
	_visited_coordinates = visited_cells.duplicate()
	_seen_coordinates = seen_cells.duplicate()
	_movement_options = movement_options.duplicate(true)
	if map_window == null:
		for cell_view: MapCellView in _cells:
			_cells_by_coordinate[cell_view.coordinate] = cell_view
	for coordinate: Vector2i in _visited_coordinates:
		_visited_coordinate_set[coordinate] = true
	for coordinate: Vector2i in _seen_coordinates:
		_seen_coordinate_set[coordinate] = true


func cells() -> Array[MapCellView]:
	return map_window.cells() if map_window != null else _cells.duplicate()


func cell_at(coordinate: Vector2i) -> MapCellView:
	return map_window.cell_at(coordinate) if map_window != null else _cells_by_coordinate.get(coordinate) as MapCellView


func visited_coordinates() -> Array[Vector2i]:
	return _materialize_coordinates(true)


func seen_coordinates() -> Array[Vector2i]:
	return _materialize_coordinates(false)


func was_visited(coordinate: Vector2i) -> bool:
	return _contains_coordinate(coordinate, true)


func was_seen(coordinate: Vector2i) -> bool:
	return _contains_coordinate(coordinate, false)


func inherit_visibility(previous: MapView) -> void:
	if previous == null or presentation_delta == null or previous.map_id != map_id:
		return
	_visibility_parent = previous
	_visited_coordinates = presentation_delta.newly_visited.duplicate()
	_seen_coordinates = presentation_delta.newly_seen.duplicate()
	_visited_coordinate_set.clear()
	_seen_coordinate_set.clear()
	for coordinate: Vector2i in _visited_coordinates:
		_visited_coordinate_set[coordinate] = true
	for coordinate: Vector2i in _seen_coordinates:
		_seen_coordinate_set[coordinate] = true
	if _visibility_depth() >= 64:
		_flatten_visibility()


func _contains_coordinate(coordinate: Vector2i, visited: bool) -> bool:
	var cursor: MapView = self
	while cursor != null:
		if (cursor._visited_coordinate_set if visited else cursor._seen_coordinate_set).has(coordinate):
			return true
		cursor = cursor._visibility_parent
	return false


func _materialize_coordinates(visited: bool) -> Array[Vector2i]:
	var segments: Array[MapView] = []
	var cursor: MapView = self
	while cursor != null:
		segments.append(cursor)
		cursor = cursor._visibility_parent
	segments.reverse()
	var result: Array[Vector2i] = []
	var membership: Dictionary = {}
	for segment: MapView in segments:
		var coordinates := segment._visited_coordinates if visited else segment._seen_coordinates
		for coordinate: Vector2i in coordinates:
			if not membership.has(coordinate):
				membership[coordinate] = true
				result.append(coordinate)
	return result


func _visibility_depth() -> int:
	var depth := 0
	var cursor := _visibility_parent
	while cursor != null:
		depth += 1
		cursor = cursor._visibility_parent
	return depth


func _flatten_visibility() -> void:
	_visited_coordinates = _materialize_coordinates(true)
	_seen_coordinates = _materialize_coordinates(false)
	_visibility_parent = null
	_visited_coordinate_set.clear(); _seen_coordinate_set.clear()
	for coordinate: Vector2i in _visited_coordinates: _visited_coordinate_set[coordinate] = true
	for coordinate: Vector2i in _seen_coordinates: _seen_coordinate_set[coordinate] = true


func can_move(direction: Vector2i) -> bool:
	return bool(_movement_options.get(_direction_name(direction), {}).get("allowed", false))


func movement_block_reason(direction: Vector2i) -> StringName:
	return StringName(_movement_options.get(_direction_name(direction), {}).get("reason", "unknown"))


static func _direction_name(direction: Vector2i) -> StringName:
	return MapTopology.direction_name(direction)
