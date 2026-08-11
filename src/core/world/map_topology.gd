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


func probe_entry(coordinate: Vector2i, move_direction: Vector2i, world_state: WorldState) -> TopologyMoveResult:
	var cell_probe := probe_land_entry(coordinate, world_state)
	if not cell_probe.allowed:
		return cell_probe
	var cell := cell_probe.target_cell
	var entry_direction_name := direction_name(move_direction)
	if not is_cardinal_direction(move_direction):
		return TopologyMoveResult.blocked(&"invalid_direction")
	var edge := cell.edge(entry_direction_name)
	if edge == null or not edge.passable:
		return TopologyMoveResult.blocked(&"edge_blocked")
	return TopologyMoveResult.permitted(cell, edge.door_id, edge.secret_id)


func probe_land_entry(coordinate: Vector2i, world_state: WorldState) -> TopologyMoveResult:
	var cell := cell_at(coordinate)
	if cell == null:
		return TopologyMoveResult.blocked(&"outside_map")
	if not cell.passable:
		return TopologyMoveResult.blocked(&"terrain_blocked", cell)
	var cell_secret := cell.feature_by_kind(&"secret")
	if cell_secret != null and cell_secret.orientation.is_empty() and not world_state.secret_is_discovered(cell_secret.id, cell_secret.initial_state == &"revealed"):
		return TopologyMoveResult.blocked(&"secret_hidden", cell)
	return TopologyMoveResult.permitted(cell)


func probe_movement(coordinate: Vector2i, move_direction: Vector2i, world_state: WorldState, level_type: StringName) -> TopologyMoveResult:
	if level_type == &"land":
		if not is_cardinal_direction(move_direction) and not is_diagonal_direction(move_direction):
			return TopologyMoveResult.blocked(&"invalid_direction")
		return probe_land_entry(coordinate, world_state)
	if not is_cardinal_direction(move_direction):
		return TopologyMoveResult.blocked(&"invalid_direction")
	return probe_entry(coordinate, move_direction, world_state)


func has_line_of_sight(from: Vector2i, to: Vector2i, world_state: WorldState) -> bool:
	if not contains(from) or not contains(to):
		return false
	var x := from.x
	var y := from.y
	var dx := absi(to.x - from.x)
	var dy := -absi(to.y - from.y)
	var step_x := 1 if from.x < to.x else -1
	var step_y := 1 if from.y < to.y else -1
	var error := dx + dy
	while x != to.x or y != to.y:
		var twice_error := 2 * error
		if twice_error >= dy:
			error += dy
			x += step_x
		if twice_error <= dx:
			error += dx
			y += step_y
		var cell := cell_at(Vector2i(x, y))
		if cell == null:
			return false
		if Vector2i(x, y) != to and _cell_blocks_los(cell, world_state):
			return false
	return true


func visible_cells(origin: Vector2i, radius: int, world_state: WorldState, use_los: bool) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: MapCell in _cells:
		if not use_los or origin.distance_squared_to(cell.coordinate) <= radius * radius and has_line_of_sight(origin, cell.coordinate, world_state):
			result.append(cell.coordinate)
	return result


func find_path(origin: Vector2i, destination: Vector2i, world_state: WorldState, level_type: StringName) -> Array[Vector2i]:
	if not contains(origin) or not contains(destination):
		return []
	if origin == destination:
		return []
	var frontier: Array[Vector2i] = [origin]
	var frontier_index := 0
	var previous: Dictionary = {origin: origin}
	var directions := land_directions() if level_type == &"land" else cardinal_directions()
	while frontier_index < frontier.size():
		var current := frontier[frontier_index]
		frontier_index += 1
		for move_direction: Vector2i in directions:
			var neighbor := current + move_direction
			if not contains(neighbor) or previous.has(neighbor):
				continue
			if not probe_movement(neighbor, move_direction, world_state, level_type).allowed:
				continue
			previous[neighbor] = current
			if neighbor == destination:
				return _reconstruct_path(origin, destination, previous)
			frontier.append(neighbor)
	return []


static func direction_name(direction: Vector2i) -> StringName:
	match direction:
		Vector2i.UP:
			return &"north"
		Vector2i.RIGHT:
			return &"east"
		Vector2i.DOWN:
			return &"south"
		Vector2i.LEFT:
			return &"west"
		Vector2i(-1, -1):
			return &"northwest"
		Vector2i(1, -1):
			return &"northeast"
		Vector2i(-1, 1):
			return &"southwest"
		Vector2i(1, 1):
			return &"southeast"
		_:
			return &""


static func is_cardinal_direction(direction: Vector2i) -> bool:
	return direction in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func is_diagonal_direction(direction: Vector2i) -> bool:
	return absi(direction.x) == 1 and absi(direction.y) == 1


static func cardinal_directions() -> Array[Vector2i]:
	return [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]


static func land_directions() -> Array[Vector2i]:
	return [Vector2i.UP, Vector2i(1, -1), Vector2i.RIGHT, Vector2i(1, 1), Vector2i.DOWN, Vector2i(-1, 1), Vector2i.LEFT, Vector2i(-1, -1)]


static func _cell_blocks_los(cell: MapCell, world_state: WorldState) -> bool:
	if not cell.blocks_los:
		return false
	for feature: MapFeature in cell.features():
		if feature.kind == &"door" and world_state.door_is_open(feature.id, feature.initial_state == &"open"):
			return false
		if feature.kind == &"secret" and world_state.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			return false
	return true


static func _reconstruct_path(origin: Vector2i, destination: Vector2i, previous: Dictionary) -> Array[Vector2i]:
	var path: Array[Vector2i] = []
	var cursor := destination
	while cursor != origin:
		path.append(cursor)
		cursor = previous[cursor]
	path.reverse()
	return path
