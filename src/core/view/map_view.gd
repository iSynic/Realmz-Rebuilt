class_name MapView
extends RefCounted

var map_id: String
var map_name: String
var level_type: StringName
var width: int
var height: int
var party_coordinate: Vector2i
var dark: bool
var _cells: Array[MapCellView]
var _cells_by_coordinate: Dictionary = {}
var _visited_coordinates: Array[Vector2i] = []
var _movement_options: Dictionary = {}


func _init(view_map_id: String, view_map_name: String, view_level_type: StringName, map_width: int, map_height: int, party_position: Vector2i, cell_views: Array[MapCellView], is_dark: bool = false, visited_cells: Array[Vector2i] = [], movement_options: Dictionary = {}) -> void:
	map_id = view_map_id
	map_name = view_map_name
	level_type = view_level_type
	width = map_width
	height = map_height
	party_coordinate = party_position
	dark = is_dark
	_cells = cell_views.duplicate()
	_visited_coordinates = visited_cells.duplicate()
	_movement_options = movement_options.duplicate(true)
	for cell_view: MapCellView in _cells:
		_cells_by_coordinate[cell_view.coordinate] = cell_view


func cells() -> Array[MapCellView]:
	return _cells.duplicate()


func cell_at(coordinate: Vector2i) -> MapCellView:
	return _cells_by_coordinate.get(coordinate) as MapCellView


func visited_coordinates() -> Array[Vector2i]:
	return _visited_coordinates.duplicate()


func can_move(direction: Vector2i) -> bool:
	return bool(_movement_options.get(_direction_name(direction), {}).get("allowed", false))


func movement_block_reason(direction: Vector2i) -> StringName:
	return StringName(_movement_options.get(_direction_name(direction), {}).get("reason", "unknown"))


static func _direction_name(direction: Vector2i) -> StringName:
	return MapTopology.direction_name(direction)
