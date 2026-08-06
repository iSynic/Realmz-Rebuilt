class_name DungeonGeometryProjection
extends RefCounted

const DIRECTIONS: Array[StringName] = [&"north", &"east", &"south", &"west"]


class CellProjection:
	extends RefCounted

	var coordinate: Vector2i
	var terrain_id: String
	var passable: bool
	var blocks_los: bool
	var features: Array[StringName]


	func _init(source: MapCellView) -> void:
		coordinate = source.coordinate
		terrain_id = source.terrain_id
		passable = source.passable
		blocks_los = source.blocks_los
		features = source.features()


class EdgeProjection:
	extends RefCounted

	var coordinate: Vector2i
	var direction: StringName
	var kind: StringName
	var passable: bool
	var canonical_key: String


	func _init(source_coordinate: Vector2i, source_direction: StringName, source_kind: StringName, source_passable: bool) -> void:
		coordinate = source_coordinate
		direction = source_direction
		kind = source_kind
		passable = source_passable
		canonical_key = DungeonGeometryProjection.canonical_edge_key(source_coordinate, source_direction)


var map_id: String
var map_name: String
var party_coordinate: Vector2i
var _cells: Array[CellProjection] = []
var _edges: Array[EdgeProjection] = []
var _cells_by_coordinate: Dictionary = {}
var _edges_by_direction: Dictionary = {}


static func from_map_view(map_view: MapView) -> DungeonGeometryProjection:
	if map_view == null or map_view.level_type != &"dungeon":
		return null
	var projection := DungeonGeometryProjection.new()
	projection.map_id = map_view.map_id
	projection.map_name = map_view.map_name
	projection.party_coordinate = map_view.party_coordinate
	for cell: MapCellView in map_view.cells():
		if not cell.visible:
			continue
		var cell_projection := CellProjection.new(cell)
		projection._cells.append(cell_projection)
		projection._cells_by_coordinate[cell.coordinate] = cell_projection
		for direction: StringName in DIRECTIONS:
			var edge := EdgeProjection.new(cell.coordinate, direction, cell.edge_kind(direction), cell.edge_is_passable(direction))
			projection._edges.append(edge)
			projection._edges_by_direction[_directed_edge_key(cell.coordinate, direction)] = edge
	return projection


func cells() -> Array[CellProjection]:
	return _cells.duplicate()


func edges() -> Array[EdgeProjection]:
	return _edges.duplicate()


func cell_at(coordinate: Vector2i) -> CellProjection:
	return _cells_by_coordinate.get(coordinate) as CellProjection


func edge_at(coordinate: Vector2i, direction: StringName) -> EdgeProjection:
	return _edges_by_direction.get(_directed_edge_key(coordinate, direction)) as EdgeProjection


static func canonical_edge_key(coordinate: Vector2i, direction: StringName) -> String:
	var first := coordinate
	var second := coordinate
	match direction:
		&"north":
			second += Vector2i.RIGHT
		&"east":
			first += Vector2i.RIGHT
			second += Vector2i.ONE
		&"south":
			first += Vector2i.DOWN
			second += Vector2i.ONE
		&"west":
			second += Vector2i.DOWN
		_:
			return "invalid"
	if _point_key(second) < _point_key(first):
		var swap := first
		first = second
		second = swap
	return "%s:%s" % [_point_key(first), _point_key(second)]


static func _directed_edge_key(coordinate: Vector2i, direction: StringName) -> String:
	return "%s:%s" % [_point_key(coordinate), String(direction)]


static func _point_key(point: Vector2i) -> String:
	return "%08d,%08d" % [point.x, point.y]
