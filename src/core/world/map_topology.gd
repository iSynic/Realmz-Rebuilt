class_name MapTopology
extends RefCounted

const EXPLORATION_VISIBILITY_RADIUS: int = 8
const WIZARDS_EYE_VISIBILITY_RADIUS: int = 16

var width: int
var height: int
var _cells: Array[MapCell]
var _cells_by_coordinate: Dictionary = {}
var _compact_map_id: String = ""
var _compact_rows: Array = []
var _compact_cells_by_index: Dictionary = {}
var _boat_removed_profile: LandTileProfile
var _boat_placed_profile: LandTileProfile
var _authored_landlook: int = -1
var _land_terrain_sets_by_landlook: Dictionary = {}
var _visibility_cache: Dictionary = {}


func _init(map_width: int, map_height: int, map_cells: Array[MapCell]) -> void:
	width = map_width
	height = map_height
	_cells = map_cells.duplicate()
	for cell: MapCell in _cells:
		_cells_by_coordinate[cell.coordinate] = cell


static func from_compact_rows(map_id: String, map_width: int, map_height: int, rows: Array, boat_removed_profile: LandTileProfile = null, boat_placed_profile: LandTileProfile = null, authored_landlook: int = -1, land_terrain_sets_by_landlook: Dictionary = {}) -> MapTopology:
	var topology := MapTopology.new(map_width, map_height, [])
	topology._compact_map_id = map_id
	topology._compact_rows = rows
	topology._boat_removed_profile = boat_removed_profile
	topology._boat_placed_profile = boat_placed_profile
	topology._authored_landlook = authored_landlook
	topology._land_terrain_sets_by_landlook = land_terrain_sets_by_landlook.duplicate()
	return topology


func contains(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < width and coordinate.y < height


func cell_at(coordinate: Vector2i) -> MapCell:
	if not contains(coordinate):
		return null
	if not _compact_rows.is_empty():
		var index := coordinate.y * width + coordinate.x
		var cached := _compact_cells_by_index.get(index) as MapCell
		if cached != null:
			return cached
		var decoded := _decode_compact_cell(index, coordinate)
		if decoded != null:
			_compact_cells_by_index[index] = decoded
		return decoded
	return _cells_by_coordinate.get(coordinate) as MapCell


func effective_cell_at(coordinate: Vector2i, world_state: WorldState) -> MapCell:
	var cell := cell_at(coordinate)
	if cell == null or world_state == null or _compact_map_id.is_empty():
		return cell
	cell = _terrain_replacement_cell(cell, world_state)
	match world_state.boat_presence_state(_compact_map_id, coordinate):
		0:
			return cell if _boat_removed_profile == null else _boat_removed_profile.apply_to(cell)
		1:
			return cell if _boat_placed_profile == null else _boat_placed_profile.apply_to(cell)
		_:
			return cell


func _terrain_replacement_cell(cell: MapCell, world_state: WorldState) -> MapCell:
	if not world_state.has_terrain_override(_compact_map_id, cell.coordinate):
		return cell
	var raw_tile := world_state.classic_tile_for(_compact_map_id, cell)
	if raw_tile < 0:
		return cell
	var tile_id := WorldState.normalized_classic_land_tile(raw_tile)
	if tile_id < 0 or tile_id > 200:
		return cell
	var landlook := world_state.map_landlook_for(_compact_map_id, _authored_landlook)
	var terrain_set := _land_terrain_sets_by_landlook.get(landlook) as BattleTerrainSetDefinition
	if terrain_set == null:
		return cell
	var tile_definition := terrain_set.tile_by_id(tile_id)
	if tile_definition == null:
		return cell
	var profile := tile_definition.land_profile()
	return cell if profile == null else profile.apply_to(cell)


func cells() -> Array[MapCell]:
	if not _compact_rows.is_empty():
		var result: Array[MapCell] = []
		result.resize(_compact_rows.size())
		for index: int in _compact_rows.size():
			result[index] = cell_at(Vector2i(index % width, index / width))
		return result
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


func probe_land_entry(coordinate: Vector2i, world_state: WorldState, party_in_boat: bool = false) -> TopologyMoveResult:
	var cell := effective_cell_at(coordinate, world_state)
	if cell == null:
		return TopologyMoveResult.blocked(&"outside_map")
	var secret := cell.feature_by_kind(&"secret")
	var concealed_land_secret := secret != null and secret.orientation.is_empty()
	if concealed_land_secret:
		if world_state.secret_is_discovered(secret.id, secret.initial_state == &"revealed"):
			return TopologyMoveResult.permitted(cell)
	# Castle overlays placed Data DD records into the land field as door-band
	# values and enters that branch before ordinary boat/terrain collision. An
	# undiscovered 3000-band secret is first reduced to its underlying terrain,
	# so its colocated AP cannot bypass that terrain's collision.
	if not concealed_land_secret and not cell.trigger_ids().is_empty():
		return TopologyMoveResult.permitted(cell)
	var boat_requirement := cell.boat_requirement
	if party_in_boat:
		if cell.is_shore:
			return TopologyMoveResult.blocked(&"boat_shore", cell)
		if boat_requirement == 2:
			return TopologyMoveResult.permitted(cell)
		return TopologyMoveResult.blocked(&"boat_terrain_blocked", cell)
	if boat_requirement == 1:
		return TopologyMoveResult.blocked(&"board_boat", cell)
	if boat_requirement == 2:
		return TopologyMoveResult.blocked(&"water_requires_boat", cell)
	if not cell.passable:
		return TopologyMoveResult.blocked(&"terrain_blocked", cell)
	return TopologyMoveResult.permitted(cell)


func probe_movement(coordinate: Vector2i, move_direction: Vector2i, world_state: WorldState, level_type: StringName, party_in_boat: bool = false) -> TopologyMoveResult:
	if level_type == &"land":
		if not is_cardinal_direction(move_direction) and not is_diagonal_direction(move_direction):
			return TopologyMoveResult.blocked(&"invalid_direction")
		return probe_land_entry(coordinate, world_state, party_in_boat)
	if not is_cardinal_direction(move_direction):
		return TopologyMoveResult.blocked(&"invalid_direction")
	return probe_entry(coordinate, move_direction, world_state)


func has_line_of_sight(from: Vector2i, to: Vector2i, world_state: WorldState) -> bool:
	if not contains(from) or not contains(to):
		return false
	if from == to:
		return true
	var previous := from
	var coordinate := from
	var delta := to - from
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var width_steps := absi(delta.x)
	var height_steps := absi(delta.y)
	var x_steps := 0
	var y_steps := 0
	while x_steps < width_steps or y_steps < height_steps:
		var decision := (1 + 2 * x_steps) * height_steps - (1 + 2 * y_steps) * width_steps
		if decision == 0:
			coordinate += step
			x_steps += 1
			y_steps += 1
		elif decision < 0:
			coordinate.x += step.x
			x_steps += 1
		else:
			coordinate.y += step.y
			y_steps += 1
		var cell := effective_cell_at(coordinate, world_state)
		if cell == null:
			return false
		if _transition_blocks_los(previous, coordinate, cell, world_state):
			return coordinate == to and _cell_blocks_los(cell, world_state)
		if coordinate != to and _cell_blocks_los(cell, world_state):
			return false
		previous = coordinate
	return true


func visible_cells(origin: Vector2i, radius: int, world_state: WorldState, use_los: bool, ignore_blockers: bool = false) -> Array[Vector2i]:
	var cache_key := ""
	if use_los and world_state != null:
		cache_key = "%d:%d:%d,%d:%d:%d" % [world_state.get_instance_id(), world_state.topology_revision(), origin.x, origin.y, radius, int(ignore_blockers)]
		if _visibility_cache.has(cache_key):
			var cached: Array[Vector2i] = _visibility_cache[cache_key]
			return cached
	var result: Array[Vector2i] = []
	var first_x := 0 if not use_los else maxi(0, origin.x - radius)
	var first_y := 0 if not use_los else maxi(0, origin.y - radius)
	var last_x := width if not use_los else mini(width, origin.x + radius + 1)
	var last_y := height if not use_los else mini(height, origin.y + radius + 1)
	for y: int in range(first_y, last_y):
		for x: int in range(first_x, last_x):
			var coordinate := Vector2i(x, y)
			if not use_los or origin.distance_squared_to(coordinate) <= radius * radius and (ignore_blockers or has_line_of_sight(origin, coordinate, world_state)):
				result.append(coordinate)
	if not cache_key.is_empty():
		if _visibility_cache.size() >= 512:
			_visibility_cache.clear()
		_visibility_cache[cache_key] = result
	return result


func exploration_visible_cells(origin: Vector2i, world_state: WorldState, use_los: bool, wizard_eye_active: bool = false) -> Array[Vector2i]:
	var radius := WIZARDS_EYE_VISIBILITY_RADIUS if wizard_eye_active else EXPLORATION_VISIBILITY_RADIUS
	return visible_cells(origin, radius, world_state, use_los, wizard_eye_active)


func _transition_blocks_los(from: Vector2i, to: Vector2i, destination_cell: MapCell, world_state: WorldState) -> bool:
	var delta := to - from
	if is_cardinal_direction(delta):
		return destination_cell == null or _edge_blocks_los(destination_cell.edge(direction_name(delta)), world_state)
	if not is_diagonal_direction(delta):
		return false
	var horizontal := from + Vector2i(delta.x, 0)
	var vertical := from + Vector2i(0, delta.y)
	var horizontal_cell := effective_cell_at(horizontal, world_state)
	var vertical_cell := effective_cell_at(vertical, world_state)
	return horizontal_cell == null or vertical_cell == null \
		or _edge_blocks_los(horizontal_cell.edge(direction_name(horizontal - from)), world_state) \
		or _edge_blocks_los(vertical_cell.edge(direction_name(vertical - from)), world_state) \
		or _cell_blocks_los(horizontal_cell, world_state) or _cell_blocks_los(vertical_cell, world_state)


static func _supercover_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var coordinate := from
	var delta := to - from
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var width_steps := absi(delta.x)
	var height_steps := absi(delta.y)
	var x_steps := 0
	var y_steps := 0
	while x_steps < width_steps or y_steps < height_steps:
		var decision := (1 + 2 * x_steps) * height_steps - (1 + 2 * y_steps) * width_steps
		if decision == 0:
			coordinate += step
			x_steps += 1
			y_steps += 1
		elif decision < 0:
			coordinate.x += step.x
			x_steps += 1
		else:
			coordinate.y += step.y
			y_steps += 1
		result.append(coordinate)
	return result


func _decode_compact_cell(index: int, coordinate: Vector2i) -> MapCell:
	if index < 0 or index >= _compact_rows.size():
		return null
	var row: Array = _compact_rows[index]
	var flags := int(row[2])
	var trigger_ids: Array[String] = []
	trigger_ids.assign(row[4])
	var random_rect_ids: Array[String] = []
	random_rect_ids.assign(row[5])
	var edges: Dictionary = {}
	var edge_rows: Array = row[6]
	var directions: Array[StringName] = [&"north", &"east", &"south", &"west"]
	for direction_index: int in directions.size():
		var edge_row: Array = edge_rows[direction_index]
		var edge_flags := int(edge_row[1])
		edges[directions[direction_index]] = MapEdge.new(
			StringName(edge_row[0]),
			bool(edge_flags & 1),
			bool(edge_flags & 2),
			"" if edge_row[2] == null else String(edge_row[2]),
			"" if edge_row[3] == null else String(edge_row[3]),
			bool(edge_flags & 4)
		)
	var features: Array[MapFeature] = []
	for feature_value: Variant in row[7]:
		var feature_row: Array = feature_value
		features.append(MapFeature.new(
			String(feature_row[0]),
			StringName(feature_row[1]),
			&"" if feature_row[2] == null else StringName(feature_row[2]),
			&"" if feature_row[3] == null else StringName(feature_row[3])
		))
	return MapCell.new(
		"%s:cell:%d,%d" % [_compact_map_id, coordinate.x, coordinate.y],
		coordinate,
		String(row[0]),
		bool(flags & 1),
		int(row[1]),
		bool(flags & 2),
		bool(flags & 4),
		bool(flags & 8),
		bool(flags & 16),
		bool(flags & 32),
		bool(flags & 64),
		bool(flags & 128),
		-1 if row[3] == null else int(row[3]),
		int(row[8]),
		String(row[9]),
		trigger_ids,
		random_rect_ids,
		edges,
		features,
		"" if row[10] == null else String(row[10]),
		int(row[11]),
		int(row[12]),
		bool(flags & 256)
	)


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
	if cell == null:
		return true
	if not cell.blocks_los:
		return false
	for feature: MapFeature in cell.features():
		if feature.kind == &"door" and world_state.door_is_open(feature.id, feature.initial_state == &"open"):
			return false
		if feature.kind == &"secret" and world_state.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			return false
	return true


static func _edge_blocks_los(edge: MapEdge, world_state: WorldState) -> bool:
	if edge == null or not edge.blocks_los:
		return false
	if not edge.door_id.is_empty() and world_state.door_is_open(edge.door_id):
		return false
	if not edge.secret_id.is_empty() and world_state.secret_is_discovered(edge.secret_id, edge.initially_discovered):
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
