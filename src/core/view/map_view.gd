class_name MapView
extends RefCounted

var map_id: String
var map_name: String
var level_type: StringName
var width: int
var height: int
var party_coordinate: Vector2i
var _cells: Array[MapCellView]
var _cells_by_coordinate: Dictionary = {}


func _init(view_map_id: String, view_map_name: String, view_level_type: StringName, map_width: int, map_height: int, party_position: Vector2i, cell_views: Array[MapCellView]) -> void:
	map_id = view_map_id
	map_name = view_map_name
	level_type = view_level_type
	width = map_width
	height = map_height
	party_coordinate = party_position
	_cells = cell_views.duplicate()
	for cell_view: MapCellView in _cells:
		_cells_by_coordinate[cell_view.coordinate] = cell_view


func cells() -> Array[MapCellView]:
	return _cells.duplicate()


func cell_at(coordinate: Vector2i) -> MapCellView:
	return _cells_by_coordinate.get(coordinate) as MapCellView
