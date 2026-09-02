extends SceneTree

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const CASES: Array[StringName] = [&"open", &"u_obstruction", &"expensive", &"choke", &"congestion", &"unreachable"]


class ExactMovementGrid extends AStarGrid2D:
	var destination_movement_base := PackedInt32Array()

	func _compute_cost(from_id: Vector2i, to_id: Vector2i) -> float:
		var direction := to_id - from_id
		return float(destination_movement_base[to_id.y * BattlefieldState.SIZE + to_id.x] + int(direction.x != 0) + int(direction.y != 0))

	func _estimate_cost(from_id: Vector2i, end_id: Vector2i) -> float:
		var delta := end_id - from_id
		return float(maxi(absi(delta.x), absi(delta.y)))


func _initialize() -> void:
	var arguments := OS.get_cmdline_user_args()
	var iterations := clampi(int(arguments[0]) if not arguments.is_empty() else 50, 1, 500)
	var terrain := _terrain_set()
	var rows: Array[Dictionary] = []
	var custom_total := 0
	var engine_total := 0
	for case_name: StringName in CASES:
		for actor_size: int in 4:
			var field := _fixture(case_name, actor_size)
			var rules := BattlefieldRules.new()
			var engine_started := Time.get_ticks_usec()
			var grid := _engine_grid(field, terrain, actor_size)
			var goals := _contact_goals(field, actor_size, "target", grid)
			var engine_build_us := Time.get_ticks_usec() - engine_started
			var custom_first := rules.probe_path_step_toward_actors(field, terrain, "mover", ["target"], 999)
			var engine_first := _engine_first_step(grid, field, actor_size, goals)
			var custom_started := Time.get_ticks_usec()
			for ignored: int in iterations:
				rules.probe_path_step_toward_actors(field, terrain, "mover", ["target"], 999)
			var custom_us := Time.get_ticks_usec() - custom_started
			var engine_query_started := Time.get_ticks_usec()
			for ignored: int in iterations:
				_engine_first_step(grid, field, actor_size, goals)
			var engine_us := Time.get_ticks_usec() - engine_query_started
			custom_total += custom_us
			engine_total += engine_us
			rows.append({
				"case": String(case_name), "footprint": _footprint_name(actor_size), "iterations": iterations,
				"customTotalUs": custom_us, "customMeanUs": snappedf(float(custom_us) / iterations, 0.001),
				"astarGridBuildUs": engine_build_us, "astarGridTotalUs": engine_us, "astarGridMeanUs": snappedf(float(engine_us) / iterations, 0.001),
				"customAllowed": custom_first.allowed, "astarGridAllowed": engine_first.x >= 0,
				"sameFirstStep": custom_first.allowed and custom_first.destination == engine_first,
			})
	print(CanonicalJson.encode({
		"toolOnly": true,
		"grid": [BattlefieldState.SIZE, BattlefieldState.SIZE],
		"routePolicy": "custom multi-goal exact-cost planner versus one exact-cost AStarGrid2D query per legal contact goal",
		"iterationsPerCaseAndFootprint": iterations,
		"customTotalUs": custom_total,
		"astarGridTotalUs": engine_total,
		"rows": rows,
	}))
	quit(0)


func _engine_grid(field: BattlefieldState, terrain: BattleTerrainSetDefinition, actor_size: int) -> ExactMovementGrid:
	var grid := ExactMovementGrid.new()
	grid.region = Rect2i(0, 0, BattlefieldState.SIZE, BattlefieldState.SIZE)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ALWAYS
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_CHEBYSHEV
	grid.destination_movement_base.resize(BattlefieldState.CELL_COUNT)
	grid.update()
	for y: int in BattlefieldState.SIZE:
		for x: int in BattlefieldState.SIZE:
			var anchor := Vector2i(x, y)
			var passable := true
			var maximum_base := 0
			for coordinate: Vector2i in BattlefieldState.footprint_cells(anchor, actor_size):
				if not BattlefieldState.contains(coordinate):
					passable = false
					break
				var tile := terrain.tile_by_id(field.terrain_at(coordinate))
				if tile == null or actor_size == 0 and tile.solid != 0 or actor_size > 0 and tile.solid > 1:
					passable = false
					break
				maximum_base = maxi(maximum_base, maxi(0, floori(float(tile.movement_time) / 2.0) - 1))
			var index := y * BattlefieldState.SIZE + x
			grid.destination_movement_base[index] = maximum_base
			if not passable:
				grid.set_point_solid(anchor, true)
	return grid


func _engine_first_step(grid: ExactMovementGrid, field: BattlefieldState, actor_size: int, goals: Array[Vector2i]) -> Vector2i:
	var origin := field.actor_position("mover")
	var temporarily_solid: Array[Vector2i] = []
	for direction: Vector2i in DIRECTIONS:
		var neighbor := origin + direction
		if BattlefieldState.contains(neighbor) and not _footprint_is_unoccupied(field, neighbor, actor_size, "mover") and not grid.is_point_solid(neighbor):
			grid.set_point_solid(neighbor, true)
			temporarily_solid.append(neighbor)
	var best_path := PackedVector2Array()
	var best_cost := 1.0e30
	for goal: Vector2i in goals:
		var path := grid.get_id_path(origin, goal)
		if path.size() < 2:
			continue
		var cost := 0.0
		for index: int in range(1, path.size()):
			cost += grid._compute_cost(path[index - 1], path[index])
		if cost < best_cost:
			best_cost = cost
			best_path = path
	for coordinate: Vector2i in temporarily_solid:
		grid.set_point_solid(coordinate, false)
	return Vector2i(-1, -1) if best_path.size() < 2 else Vector2i(best_path[1])


func _contact_goals(field: BattlefieldState, actor_size: int, target_id: String, grid: ExactMovementGrid) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var target_cells: Dictionary = {}
	for coordinate: Vector2i in field.actor_footprint(target_id):
		target_cells[coordinate] = true
	for target_cell: Variant in target_cells:
		for direction: Vector2i in DIRECTIONS:
			for offset: Vector2i in BattlefieldState.footprint_cells(Vector2i.ZERO, actor_size):
				var anchor: Vector2i = target_cell - direction - offset
				if BattlefieldState.contains(anchor) and not grid.is_point_solid(anchor) and _legal_contact(anchor, actor_size, target_cells) and not result.has(anchor):
					result.append(anchor)
	result.sort_custom(func(left: Vector2i, right: Vector2i) -> bool: return left.y < right.y or left.y == right.y and left.x < right.x)
	return result


func _fixture(case_name: StringName, actor_size: int) -> BattlefieldState:
	var tiles: Array[int] = []
	tiles.resize(BattlefieldState.CELL_COUNT)
	tiles.fill(1)
	var field := BattlefieldState.new("benchmark.%s.%d" % [case_name, actor_size], tiles)
	field.place_monster("mover", Vector2i(20, 45), actor_size)
	field.place_character("target", Vector2i(70, 45))
	if case_name == &"u_obstruction":
		for x: int in range(40, 61):
			field.set_terrain(Vector2i(x, 35), 2)
			field.set_terrain(Vector2i(x, 55), 2)
		for y: int in range(35, 56):
			field.set_terrain(Vector2i(40, y), 2)
	elif case_name == &"expensive":
		for x: int in range(30, 61):
			for y: int in range(42, 49):
				field.set_terrain(Vector2i(x, y), 3)
	elif case_name == &"choke":
		for y: int in BattlefieldState.SIZE:
			if y not in [44, 45, 46]:
				field.set_terrain(Vector2i(45, y), 2)
	elif case_name == &"congestion":
		field.place_character("traffic.1", Vector2i(21, 45))
		field.place_character("traffic.2", Vector2i(28, 45))
		field.place_character("traffic.3", Vector2i(29, 44))
	elif case_name == &"unreachable":
		for y: int in BattlefieldState.SIZE:
			field.set_terrain(Vector2i(45, y), 2)
	return field


func _footprint_is_unoccupied(field: BattlefieldState, anchor: Vector2i, actor_size: int, actor_id: String) -> bool:
	for coordinate: Vector2i in BattlefieldState.footprint_cells(anchor, actor_size):
		if not field.actor_at(coordinate, actor_id).is_empty():
			return false
	return true


func _legal_contact(anchor: Vector2i, actor_size: int, target_cells: Dictionary) -> bool:
	var actor_cells := BattlefieldState.footprint_cells(anchor, actor_size)
	for coordinate: Vector2i in actor_cells:
		if target_cells.has(coordinate):
			return false
	for coordinate: Vector2i in actor_cells:
		for direction: Vector2i in DIRECTIONS:
			if target_cells.has(coordinate + direction):
				return true
	return false


func _terrain_set() -> BattleTerrainSetDefinition:
	var tiles: Array[BattleTerrainTileDefinition] = [
		BattleTerrainTileDefinition.new(1, 0, 0, 0, false, 0, false, false, false, 0, []),
		BattleTerrainTileDefinition.new(2, 0, 0, 2, false, 0, false, false, false, 0, []),
		BattleTerrainTileDefinition.new(3, 0, 20, 0, false, 0, false, false, false, 0, []),
	]
	return BattleTerrainSetDefinition.new("benchmark.terrain", 1, 1, tiles)


func _footprint_name(actor_size: int) -> String:
	return ["1x1", "1x2", "2x1", "2x2"][actor_size]
