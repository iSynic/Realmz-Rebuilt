class_name DungeonGeometryProjection
extends RefCounted

const DIRECTIONS: Array[StringName] = [&"north", &"east", &"south", &"west"]
const HEADING_NORTH := 1
const HEADING_EAST := 2
const HEADING_SOUTH := 3
const HEADING_WEST := 4


class CellProjection:
	extends RefCounted

	var coordinate: Vector2i
	var terrain_id: String
	var passable: bool
	var blocks_los: bool
	var features: Array[StringName]
	var feature_orientations: Dictionary = {}


	func _init(source: MapCellView) -> void:
		coordinate = source.coordinate
		terrain_id = source.terrain_id
		passable = source.passable
		blocks_los = source.blocks_los
		features = source.features()
		for feature: StringName in features:
			feature_orientations[feature] = source.feature_orientation(feature)


	func feature_orientation(feature: StringName) -> StringName:
		return StringName(feature_orientations.get(feature, ""))


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
var heading: int = HEADING_NORTH
var facing_direction: Vector2i = Vector2i.UP
var dark: bool = false
var geometry_source_id: int = 0
var geometry_source: RefCounted
var _source_cells: Array[MapCellView] = []
var _source_cells_by_coordinate: Dictionary = {}


static func from_map_view(map_view: MapView, reusable_geometry: DungeonGeometryProjection = null) -> DungeonGeometryProjection:
	if map_view == null or map_view.level_type != &"dungeon":
		return null
	var projection := DungeonGeometryProjection.new()
	projection.map_id = map_view.map_id
	projection.map_name = map_view.map_name
	projection.party_coordinate = map_view.party_coordinate
	projection.heading = normalize_heading(map_view.dungeon_heading)
	projection.facing_direction = heading_vector(projection.heading)
	projection.dark = map_view.dark
	projection.geometry_source = map_view.map_window if map_view.map_window != null else map_view
	projection.geometry_source_id = geometry_source_id_for(map_view)
	if reusable_geometry != null and reusable_geometry.map_id == projection.map_id and reusable_geometry.geometry_source_id == projection.geometry_source_id:
		projection._source_cells = reusable_geometry._source_cells
		projection._source_cells_by_coordinate = reusable_geometry._source_cells_by_coordinate
		return projection
	for cell: MapCellView in map_view.cells():
		if not cell.visible:
			continue
		projection._source_cells.append(cell)
		projection._source_cells_by_coordinate[cell.coordinate] = cell
	return projection


static func geometry_source_id_for(map_view: MapView) -> int:
	return map_view.map_window.get_instance_id() if map_view != null and map_view.map_window != null else map_view.get_instance_id() if map_view != null else 0


static func cardinal_facing(direction: Vector2i) -> Vector2i:
	if direction == Vector2i.ZERO:
		return Vector2i.UP
	if absi(direction.x) > absi(direction.y):
		return Vector2i(signi(direction.x), 0)
	return Vector2i(0, signi(direction.y))


static func normalize_heading(value: int) -> int:
	return value if value >= HEADING_NORTH and value <= HEADING_WEST else HEADING_NORTH


static func rotated_heading(value: int, delta: int) -> int:
	return posmod(normalize_heading(value) - 1 + delta, 4) + 1


static func heading_vector(value: int) -> Vector2i:
	match normalize_heading(value):
		HEADING_EAST: return Vector2i.RIGHT
		HEADING_SOUTH: return Vector2i.DOWN
		HEADING_WEST: return Vector2i.LEFT
	return Vector2i.UP


static func direction_vector(direction: StringName) -> Vector2i:
	match direction:
		&"north": return Vector2i.UP
		&"east": return Vector2i.RIGHT
		&"south": return Vector2i.DOWN
		&"west": return Vector2i.LEFT
	return Vector2i.ZERO


func cells() -> Array[CellProjection]:
	var result: Array[CellProjection] = []
	for source: MapCellView in _source_cells:
		result.append(CellProjection.new(source))
	return result


func edges() -> Array[EdgeProjection]:
	var result: Array[EdgeProjection] = []
	for source: MapCellView in _source_cells:
		for direction: StringName in DIRECTIONS:
			result.append(EdgeProjection.new(source.coordinate, direction, source.edge_kind(direction), source.edge_is_passable(direction)))
	return result


func cell_at(coordinate: Vector2i) -> CellProjection:
	var source := source_cell_at(coordinate)
	return CellProjection.new(source) if source != null else null


func edge_at(coordinate: Vector2i, direction: StringName) -> EdgeProjection:
	var source := source_cell_at(coordinate)
	return EdgeProjection.new(coordinate, direction, source.edge_kind(direction), source.edge_is_passable(direction)) if source != null else null


func source_cells() -> Array[MapCellView]:
	return _source_cells.duplicate()


func source_cell_at(coordinate: Vector2i) -> MapCellView:
	return _source_cells_by_coordinate.get(coordinate) as MapCellView


func edge_kind_at(coordinate: Vector2i, direction: StringName) -> StringName:
	var source := source_cell_at(coordinate)
	return source.edge_kind(direction) if source != null else &"map-boundary"


func edge_passable_at(coordinate: Vector2i, direction: StringName) -> bool:
	var source := source_cell_at(coordinate)
	return source != null and source.edge_is_passable(direction)


func geometry_cache_key() -> String:
	return "%s:%d:%d,%d" % [map_id, geometry_source_id, party_coordinate.x, party_coordinate.y]


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
