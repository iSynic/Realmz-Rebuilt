class_name MapTopology
extends RefCounted

var width: int
var height: int
var _cells: Array[MapCell]
var _cells_by_coordinate: Dictionary = {}


func _init(map_width: int, map_height: int, map_cells: Array[MapCell]) -> void:
	width = map_width
	height = map_height
	_cells = map_cells.duplicate()
	for cell: MapCell in _cells:
		_cells_by_coordinate[cell.coordinate] = cell


func contains(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < width and coordinate.y < height


func cell_at(coordinate: Vector2i) -> MapCell:
	return _cells_by_coordinate.get(coordinate) as MapCell


func cells() -> Array[MapCell]:
	return _cells.duplicate()
