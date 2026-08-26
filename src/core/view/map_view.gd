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
var wizard_eye_active: bool
var dark: bool
var _cells: Array[MapCellView]
var _cells_by_coordinate: Dictionary = {}
var _visited_coordinates: Array[Vector2i] = []
var _movement_options: Dictionary = {}


func _init(view_map_id: String, view_map_name: String, view_level_type: StringName, map_width: int, map_height: int, party_position: Vector2i, cell_views: Array[MapCellView], is_dark: bool = false, visited_cells: Array[Vector2i] = [], movement_options: Dictionary = {}, party_last_move_direction: Vector2i = Vector2i.ZERO, view_landlook: int = -1, party_dungeon_heading: int = 1, allows_dungeon_multiview: bool = true, has_wizard_eye: bool = false, view_base_scale: int = -1) -> void:
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
	wizard_eye_active = has_wizard_eye
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
