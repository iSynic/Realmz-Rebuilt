class_name BattlefieldRules
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const ROUTE_GENERATION_LIMIT: int = 2_000_000_000


class NavigationProfile extends RefCounted:
	var passable := PackedByteArray()
	var destination_movement_base := PackedInt32Array()

	func _init() -> void:
		passable.resize(BattlefieldState.CELL_COUNT)
		destination_movement_base.resize(BattlefieldState.CELL_COUNT)


class RouteWorkspace extends RefCounted:
	var generation: int = 0
	var distances := PackedInt32Array()
	var distance_generations := PackedInt32Array()
	var first_steps := PackedInt32Array()
	var closed_generations := PackedInt32Array()
	var goal_generations := PackedInt32Array()
	var heuristics := PackedInt32Array()
	var heuristic_generations := PackedInt32Array()
	var queue := PackedInt32Array()
	var heap: Array[Vector4i] = []
	var occupied_cells: Dictionary = {}
	var swappable_cells: Dictionary = {}

	func _init() -> void:
		for storage: PackedInt32Array in [distances, distance_generations, first_steps, closed_generations, goal_generations, heuristics, heuristic_generations, queue]:
			storage.resize(BattlefieldState.CELL_COUNT)

	func begin_search() -> int:
		generation += 1
		if generation >= ROUTE_GENERATION_LIMIT:
			distance_generations.fill(0)
			closed_generations.fill(0)
			goal_generations.fill(0)
			heuristic_generations.fill(0)
			generation = 1
		heap.clear()
		occupied_cells.clear()
		swappable_cells.clear()
		return generation


var _navigation_battlefield_id: int = 0
var _navigation_terrain_set_id: int = 0
var _navigation_terrain_revision: int = -1
var _navigation_profiles: Array[NavigationProfile] = []
var _navigation_profile_build_count: int = 0
var _route_workspace := RouteWorkspace.new()


func adjacent_actor_ids(battlefield: BattlefieldState, actor_id: String, anchor_override: Vector2i = Vector2i(-1, -1)) -> Array[String]:
	var result: Array[String] = []
	if battlefield == null or not battlefield.has_actor(actor_id):
		return result
	var anchor := battlefield.actor_position(actor_id) if anchor_override.x < 0 else anchor_override
	var actor_cells := battlefield.actor_footprint_at(actor_id, anchor)
	for candidate_id: String in battlefield.actor_ids():
		if candidate_id == actor_id:
			continue
		if _footprints_are_adjacent(actor_cells, battlefield.actor_footprint(candidate_id)):
			result.append(candidate_id)
	return result


func are_adjacent(battlefield: BattlefieldState, first_actor_id: String, second_actor_id: String) -> bool:
	if battlefield == null or first_actor_id == second_actor_id:
		return false
	return _footprints_are_adjacent(battlefield.actor_footprint(first_actor_id), battlefield.actor_footprint(second_actor_id))


func classic_range(battlefield: BattlefieldState, first_actor_id: String, second_actor_id: String) -> int:
	if battlefield == null or first_actor_id == second_actor_id or not battlefield.has_actor(first_actor_id) or not battlefield.has_actor(second_actor_id):
		return -1
	# getrange.c measures actor anchors and stores sqrt() in a short, truncating
	# the Euclidean distance before comparing it with the spell range.
	return floori(Vector2(battlefield.actor_position(second_actor_id) - battlefield.actor_position(first_actor_id)).length())


func classic_coordinate_range(battlefield: BattlefieldState, actor_id: String, destination: Vector2i) -> int:
	if battlefield == null or not battlefield.has_actor(actor_id) or not BattlefieldState.contains(destination):
		return -1
	return floori(Vector2(destination - battlefield.actor_position(actor_id)).length())


func projectile_target_is_valid(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, first_actor_id: String, second_actor_id: String, maximum_range: int, require_line_of_sight: bool = true) -> bool:
	var distance := classic_range(battlefield, first_actor_id, second_actor_id)
	return distance >= 0 and distance <= maximum_range and (not require_line_of_sight or has_line_of_sight(battlefield, terrain_set, first_actor_id, second_actor_id))


func coordinate_target_is_valid(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, destination: Vector2i, maximum_range: int, require_line_of_sight: bool = true) -> bool:
	var distance := classic_coordinate_range(battlefield, actor_id, destination)
	return distance >= 0 and distance <= maximum_range and (not require_line_of_sight or has_line_of_sight_to_coordinate(battlefield, terrain_set, actor_id, destination))


func monster_footprint_is_open(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, anchor: Vector2i, size: int, additionally_occupied: Dictionary = {}) -> bool:
	if battlefield == null or terrain_set == null or size < 0 or size > 3:
		return false
	var occupied_cells := additionally_occupied.duplicate()
	for actor_id: String in battlefield.actor_ids():
		for coordinate: Vector2i in battlefield.actor_footprint(actor_id):
			occupied_cells[coordinate] = true
	return _route_footprint_is_passable(battlefield, terrain_set, size, BattlefieldState.footprint_cells(anchor, size), occupied_cells, true)


func has_line_of_sight(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, from_actor_id: String, to_actor_id: String) -> bool:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(from_actor_id) or not battlefield.has_actor(to_actor_id):
		return false
	return has_line_of_sight_to_coordinate(battlefield, terrain_set, from_actor_id, battlefield.actor_position(to_actor_id))


func has_line_of_sight_to_coordinate(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, from_actor_id: String, destination: Vector2i) -> bool:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(from_actor_id) or not BattlefieldState.contains(destination):
		return false
	var occupied_cells: Dictionary = {}
	for actor_id: String in battlefield.actor_ids():
		for coordinate: Vector2i in battlefield.actor_footprint(actor_id):
			occupied_cells[coordinate] = true
	var origin := battlefield.actor_position(from_actor_id)
	var part := Vector2(origin * 32)
	var step := Vector2(destination - origin) * 32.0 / 128.0
	# FD-COMBAT-008 retains Castle's 128 center-offset samples but removes the
	# animation-delay term from the divisor. Presentation speed cannot alter AI.
	for _sample: int in 128:
		var coordinate := Vector2i(floori((part.x + 16.0) / 32.0), floori((part.y + 16.0) / 32.0))
		if not BattlefieldState.contains(coordinate):
			return false
		# Castle's field contains actor IDs, so occupied cells do not expose their
		# underlying terrain to cansee(). Preserve that observable distinction.
		if not occupied_cells.has(coordinate):
			var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
			if terrain == null or terrain.blocks_los:
				return false
		part += step
	return true


func ray_actor_ids(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, from_actor_id: String, destination: Vector2i, stop_at_los_blocker: bool = true) -> Array[String]:
	var result: Array[String] = []
	if battlefield == null or terrain_set == null or not battlefield.has_actor(from_actor_id) or not BattlefieldState.contains(destination):
		return result
	var encountered: Dictionary = {from_actor_id: true}
	var origin := battlefield.actor_position(from_actor_id)
	var part := Vector2(origin * 32)
	var step := Vector2(destination - origin) * 32.0 / 128.0
	for _sample: int in 128:
		var coordinate := Vector2i(floori((part.x + 16.0) / 32.0), floori((part.y + 16.0) / 32.0))
		if not BattlefieldState.contains(coordinate):
			break
		var actor_id := battlefield.actor_at(coordinate)
		if not actor_id.is_empty():
			if not encountered.has(actor_id):
				encountered[actor_id] = true
				result.append(actor_id)
		elif stop_at_los_blocker:
			var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
			if terrain == null or terrain.blocks_los:
				break
		part += step
	return result


func probe_monster_step_toward(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, target: Vector2i, movement_available: int, rng: RealmzRng) -> BattlefieldStepResult:
	if battlefield == null or terrain_set == null or rng == null or not battlefield.has_actor(actor_id):
		return BattlefieldStepResult.blocked(&"invalid_actor")
	var origin := battlefield.actor_position(actor_id)
	var direction := Vector2i(signi(target.x - origin.x), signi(target.y - origin.y))
	var maximum_cost := 0
	for attempt: int in 21:
		var probe := _probe_step_with_cost_floor(battlefield, terrain_set, actor_id, direction, movement_available, maximum_cost)
		maximum_cost = maxi(maximum_cost, probe.movement_cost)
		if probe.allowed:
			return probe
		direction = _shift_monster_direction(origin, target, direction, rng, actor_id, attempt)
	var blocked := BattlefieldStepResult.blocked(&"monster_path_blocked", origin)
	blocked.movement_cost = maximum_cost
	return blocked


func probe_monster_step_away(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, target: Vector2i, movement_available: int, rng: RealmzRng) -> BattlefieldStepResult:
	if battlefield == null or not battlefield.has_actor(actor_id):
		return BattlefieldStepResult.blocked(&"invalid_actor")
	var origin := battlefield.actor_position(actor_id)
	return probe_monster_step_toward(battlefield, terrain_set, actor_id, origin * 2 - target, movement_available, rng)


func probe_step(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, direction: Vector2i, movement_available: int) -> BattlefieldStepResult:
	return _probe_step_with_cost_floor(battlefield, terrain_set, actor_id, direction, movement_available, 0)


func probe_path_step_toward_actors(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, target_ids: Array[String], movement_available: int, swappable_actor_ids: Array[String] = [], forbidden_anchors: Array[Vector2i] = []) -> BattlefieldStepResult:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(actor_id):
		return BattlefieldStepResult.blocked(&"invalid_actor")
	var valid_targets: Array[String] = []
	for target_id: String in target_ids:
		if target_id != actor_id and battlefield.has_actor(target_id) and not valid_targets.has(target_id):
			valid_targets.append(target_id)
	if valid_targets.is_empty():
		return BattlefieldStepResult.blocked(&"invalid_actor")
	var origin := battlefield.actor_position(actor_id)
	var actor_size := battlefield.actor_size(actor_id)
	var profile := _navigation_profile(battlefield, terrain_set, actor_size)
	if profile == null:
		return BattlefieldStepResult.blocked(&"invalid_actor", origin)
	var generation := _route_workspace.begin_search()
	var target_cells: Dictionary = {}
	for target_id: String in valid_targets:
		for coordinate: Vector2i in battlefield.actor_footprint(target_id):
			target_cells[coordinate] = true
	var goal_count := _mark_route_goal_anchors(target_cells, actor_size, profile, generation)
	if goal_count == 0:
		return BattlefieldStepResult.blocked(&"path_not_found", origin)
	var origin_index := _route_index(origin)
	if _route_workspace.goal_generations[origin_index] == generation:
		return BattlefieldStepResult.blocked(&"already_adjacent", origin)
	for candidate_id: String in battlefield.actor_ids():
		if candidate_id == actor_id:
			continue
		for coordinate: Vector2i in battlefield.actor_footprint(candidate_id):
			_route_workspace.occupied_cells[coordinate] = true
			if swappable_actor_ids.has(candidate_id):
				_route_workspace.swappable_cells[coordinate] = true
	_route_workspace.distances[origin_index] = 0
	_route_workspace.distance_generations[origin_index] = generation
	_route_workspace.first_steps[origin_index] = -1
	var sequence := 0
	var origin_heuristic := _route_heuristic(origin_index, generation, goal_count)
	_route_heap_push(_route_workspace.heap, Vector4i(origin_heuristic, origin_heuristic, sequence, origin_index))
	while not _route_workspace.heap.is_empty():
		var current := _route_heap_pop(_route_workspace.heap)
		var current_index := current.w
		if _route_workspace.closed_generations[current_index] == generation:
			continue
		_route_workspace.closed_generations[current_index] = generation
		if _route_workspace.goal_generations[current_index] == generation:
			var first_step := _route_coordinate(_route_workspace.first_steps[current_index])
			var probe := _probe_step_with_cost_floor(battlefield, terrain_set, actor_id, first_step - origin, movement_available, 0)
			if not probe.allowed and probe.reason == &"occupied" and swappable_actor_ids.has(probe.occupant_id):
				return BattlefieldStepResult.permitted(first_step, 5) if movement_available >= 5 else _blocked_with_cost(&"insufficient_movement", first_step, 5, probe.occupant_id)
			return probe
		var anchor := _route_coordinate(current_index)
		for direction: Vector2i in DIRECTIONS:
			# Only the immediate step must respect current actors. Later route cells
			# are a wall-following forecast: mobile combatants may vacate them before
			# this actor reaches them, while terrain remains authoritative.
			var destination := anchor + direction
			if not BattlefieldState.contains(destination) or destination != origin and forbidden_anchors.has(destination):
				continue
			var destination_index := _route_index(destination)
			if _route_workspace.closed_generations[destination_index] == generation or profile.passable[destination_index] == 0:
				continue
			var planned_swap := actor_size == 0 and _route_workspace.swappable_cells.has(destination)
			if anchor == origin and not planned_swap and not _route_footprint_is_unoccupied(destination, actor_size, _route_workspace.occupied_cells):
				continue
			var step_cost := 5 if planned_swap else profile.destination_movement_base[destination_index] + _direction_cost(direction)
			if anchor == origin and step_cost > movement_available:
				continue
			var next_distance := _route_workspace.distances[current_index] + step_cost
			if _route_workspace.distance_generations[destination_index] == generation and next_distance >= _route_workspace.distances[destination_index]:
				continue
			_route_workspace.distances[destination_index] = next_distance
			_route_workspace.distance_generations[destination_index] = generation
			_route_workspace.first_steps[destination_index] = destination_index if current_index == origin_index else _route_workspace.first_steps[current_index]
			sequence += 1
			var heuristic := _route_heuristic(destination_index, generation, goal_count)
			_route_heap_push(_route_workspace.heap, Vector4i(next_distance + heuristic, heuristic, sequence, destination_index))
	return BattlefieldStepResult.blocked(&"path_not_found", origin)


static func _route_footprint_is_passable(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_size: int, footprint: Array[Vector2i], occupied_cells: Dictionary, respect_occupants: bool) -> bool:
	for coordinate: Vector2i in footprint:
		if not BattlefieldState.contains(coordinate) or respect_occupants and occupied_cells.has(coordinate):
			return false
		var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
		if terrain == null or actor_size == 0 and terrain.solid != 0 or actor_size > 0 and terrain.solid > 1:
			return false
	return true


func _mark_route_goal_anchors(target_cells: Dictionary, actor_size: int, profile: NavigationProfile, generation: int) -> int:
	var goal_count := 0
	var offsets := BattlefieldState.footprint_cells(Vector2i.ZERO, actor_size)
	for value: Variant in target_cells:
		var target_cell: Vector2i = value
		for direction: Vector2i in DIRECTIONS:
			for offset: Vector2i in offsets:
				var anchor := target_cell - direction - offset
				if not BattlefieldState.contains(anchor):
					continue
				var index := _route_index(anchor)
				if profile.passable[index] != 0 and _route_workspace.goal_generations[index] != generation and _route_contact_anchor_is_legal(anchor, actor_size, target_cells):
					_route_workspace.goal_generations[index] = generation
					_route_workspace.queue[goal_count] = index
					goal_count += 1
	return goal_count


func _route_heuristic(index: int, generation: int, goal_count: int) -> int:
	if _route_workspace.heuristic_generations[index] == generation:
		return _route_workspace.heuristics[index]
	var coordinate := _route_coordinate(index)
	var result := BattlefieldState.SIZE
	for goal_cursor: int in goal_count:
		var goal := _route_coordinate(_route_workspace.queue[goal_cursor])
		result = mini(result, maxi(absi(goal.x - coordinate.x), absi(goal.y - coordinate.y)))
	_route_workspace.heuristics[index] = result
	_route_workspace.heuristic_generations[index] = generation
	return result


static func _route_contact_anchor_is_legal(anchor: Vector2i, actor_size: int, target_cells: Dictionary) -> bool:
	var actor_cells := BattlefieldState.footprint_cells(anchor, actor_size)
	for actor_cell: Vector2i in actor_cells:
		if target_cells.has(actor_cell):
			return false
	for actor_cell: Vector2i in actor_cells:
		for direction: Vector2i in DIRECTIONS:
			if target_cells.has(actor_cell + direction):
				return true
	return false


static func _route_footprint_is_unoccupied(anchor: Vector2i, actor_size: int, occupied_cells: Dictionary) -> bool:
	for coordinate: Vector2i in BattlefieldState.footprint_cells(anchor, actor_size):
		if occupied_cells.has(coordinate):
			return false
	return true


func _navigation_profile(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_size: int) -> NavigationProfile:
	if actor_size < 0 or actor_size > 3:
		return null
	var battlefield_id := battlefield.get_instance_id()
	var terrain_set_id := terrain_set.get_instance_id()
	if _navigation_battlefield_id != battlefield_id or _navigation_terrain_set_id != terrain_set_id or _navigation_terrain_revision != battlefield.terrain_revision():
		_rebuild_navigation_profiles(battlefield, terrain_set)
	return _navigation_profiles[actor_size]


func _rebuild_navigation_profiles(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition) -> void:
	_navigation_profiles.clear()
	for _actor_size: int in 4:
		_navigation_profiles.append(NavigationProfile.new())
	var terrain_tiles := battlefield.terrain_tiles()
	var small_passable := PackedByteArray()
	var large_passable := PackedByteArray()
	var movement_bases := PackedInt32Array()
	small_passable.resize(BattlefieldState.CELL_COUNT)
	large_passable.resize(BattlefieldState.CELL_COUNT)
	movement_bases.resize(BattlefieldState.CELL_COUNT)
	for index: int in BattlefieldState.CELL_COUNT:
		var terrain := terrain_set.tile_by_id(terrain_tiles[index])
		if terrain == null:
			continue
		small_passable[index] = 1 if terrain.solid == 0 else 0
		large_passable[index] = 1 if terrain.solid <= 1 else 0
		movement_bases[index] = _movement_base(terrain)
	for index: int in BattlefieldState.CELL_COUNT:
		var x := index % BattlefieldState.SIZE
		var y := index / BattlefieldState.SIZE
		if small_passable[index] != 0:
			_navigation_profiles[0].passable[index] = 1
			_navigation_profiles[0].destination_movement_base[index] = movement_bases[index]
		if y > 0:
			var upper_index := index - BattlefieldState.SIZE
			if large_passable[index] != 0 and large_passable[upper_index] != 0:
				_navigation_profiles[1].passable[index] = 1
				_navigation_profiles[1].destination_movement_base[index] = maxi(movement_bases[index], movement_bases[upper_index])
		if x > 0:
			var left_index := index - 1
			if large_passable[index] != 0 and large_passable[left_index] != 0:
				_navigation_profiles[2].passable[index] = 1
				_navigation_profiles[2].destination_movement_base[index] = maxi(movement_bases[index], movement_bases[left_index])
			if y > 0:
				var upper_left_index := index - BattlefieldState.SIZE - 1
				if large_passable[index] != 0 and large_passable[left_index] != 0 and large_passable[index - BattlefieldState.SIZE] != 0 and large_passable[upper_left_index] != 0:
					_navigation_profiles[3].passable[index] = 1
					_navigation_profiles[3].destination_movement_base[index] = maxi(maxi(movement_bases[index], movement_bases[left_index]), maxi(movement_bases[index - BattlefieldState.SIZE], movement_bases[upper_left_index]))
	_navigation_battlefield_id = battlefield.get_instance_id()
	_navigation_terrain_set_id = terrain_set.get_instance_id()
	_navigation_terrain_revision = battlefield.terrain_revision()
	_navigation_profile_build_count += 1


func debug_navigation_profile_build_count() -> int:
	return _navigation_profile_build_count


func debug_route_workspace_generation() -> int:
	return _route_workspace.generation


static func _route_heap_push(heap: Array[Vector4i], value: Vector4i) -> void:
	heap.append(value)
	var index := heap.size() - 1
	while index > 0:
		var parent := (index - 1) / 2
		if not _route_heap_less(heap[index], heap[parent]):
			break
		var swap := heap[parent]
		heap[parent] = heap[index]
		heap[index] = swap
		index = parent


static func _route_heap_pop(heap: Array[Vector4i]) -> Vector4i:
	var result := heap[0]
	var tail: Vector4i = heap.pop_back()
	if heap.is_empty():
		return result
	heap[0] = tail
	var index := 0
	while true:
		var left := index * 2 + 1
		if left >= heap.size():
			break
		var right := left + 1
		var child := right if right < heap.size() and _route_heap_less(heap[right], heap[left]) else left
		if not _route_heap_less(heap[child], heap[index]):
			break
		var swap := heap[index]
		heap[index] = heap[child]
		heap[child] = swap
		index = child
	return result


static func _route_heap_less(left: Vector4i, right: Vector4i) -> bool:
	return left.x < right.x or (left.x == right.x and (left.y < right.y or (left.y == right.y and left.z < right.z)))


static func _route_index(coordinate: Vector2i) -> int:
	return coordinate.y * BattlefieldState.SIZE + coordinate.x


static func _route_coordinate(index: int) -> Vector2i:
	return Vector2i(index % BattlefieldState.SIZE, index / BattlefieldState.SIZE)


func _probe_step_with_cost_floor(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, direction: Vector2i, movement_available: int, cost_floor: int, anchor_override: Vector2i = Vector2i(-1, -1), ignore_occupants: bool = false) -> BattlefieldStepResult:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(actor_id):
		return BattlefieldStepResult.blocked(&"invalid_actor")
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		return BattlefieldStepResult.blocked(&"invalid_direction")
	var destination := (battlefield.actor_position(actor_id) if anchor_override.x < 0 else anchor_override) + direction
	var footprint := battlefield.actor_footprint_at(actor_id, destination)
	if footprint.is_empty():
		return BattlefieldStepResult.blocked(&"invalid_actor", destination)
	var maximum_cost := maxi(0, cost_floor)
	for coordinate: Vector2i in footprint:
		if not BattlefieldState.contains(coordinate):
			return _blocked_with_cost(&"outside_battlefield", destination, maximum_cost)
		var occupant := battlefield.actor_at(coordinate, actor_id)
		if not ignore_occupants and not occupant.is_empty():
			return _blocked_with_cost(&"occupied", destination, maximum_cost, occupant)
		var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
		if terrain == null:
			return _blocked_with_cost(&"missing_terrain", destination, maximum_cost)
		var size := battlefield.actor_size(actor_id)
		if size == 0 and terrain.solid != 0 or size > 0 and terrain.solid > 1:
			return _blocked_with_cost(&"solid_terrain", destination, maximum_cost)
		maximum_cost = maxi(maximum_cost, _movement_cost(terrain, direction))
	if maximum_cost > movement_available:
		var result := BattlefieldStepResult.blocked(&"insufficient_movement", destination)
		result.movement_cost = maximum_cost
		return result
	return BattlefieldStepResult.permitted(destination, maximum_cost)


static func _blocked_with_cost(reason: StringName, destination: Vector2i, movement_cost: int, occupant_id: String = "") -> BattlefieldStepResult:
	var result := BattlefieldStepResult.blocked(reason, destination, occupant_id)
	result.movement_cost = movement_cost
	return result


static func _movement_cost(terrain: BattleTerrainTileDefinition, direction: Vector2i) -> int:
	return _movement_base(terrain) + _direction_cost(direction)


static func _movement_base(terrain: BattleTerrainTileDefinition) -> int:
	return maxi(0, floori(float(terrain.movement_time) / 2.0) - 1)


static func _direction_cost(direction: Vector2i) -> int:
	var cost := 0
	if direction.x != 0:
		cost += 1
	if direction.y != 0:
		cost += 1
	return cost


static func _shift_monster_direction(origin: Vector2i, target: Vector2i, direction: Vector2i, rng: RealmzRng, actor_id: String, attempt: int) -> Vector2i:
	var result := direction
	var net_x := absi(target.x - origin.x)
	var net_y := absi(target.y - origin.y)
	var tag_prefix := "combat.monster-shift.%s.%d" % [actor_id, attempt]
	if net_x > net_y:
		if result.y != 0 and rng.draw(2, StringName(tag_prefix + ".drop-y")) == 1:
			result.y = 0
		else:
			result.y = -1
			var y_roll := rng.draw(3, StringName(tag_prefix + ".y"))
			if y_roll == 1:
				result.y = 1
			elif y_roll == 2:
				result.y = 0
			var x_roll := rng.draw(3, StringName(tag_prefix + ".x"))
			if x_roll == 1:
				result.x = -1
			elif x_roll == 2:
				result.x = 1
			if x_roll == 3 and result.y != 0:
				result.x = 0
			else:
				result.x = -1 if rng.draw(2, StringName(tag_prefix + ".x-sign")) == 1 else 1
	else:
		if result.x != 0:
			result.x = 0
		else:
			result.x = -1
			var x_roll := rng.draw(3, StringName(tag_prefix + ".x"))
			if x_roll == 1:
				result.x = 1
			elif x_roll == 2:
				result.x = 0
			result.y = -1
			var y_roll := rng.draw(3, StringName(tag_prefix + ".y"))
			if y_roll == 1:
				result.y = -1
			elif y_roll == 2:
				result.y = 1
			elif y_roll == 3:
				result.y = 0
	return result


static func _footprints_are_adjacent(first: Array[Vector2i], second: Array[Vector2i]) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	for first_cell: Vector2i in first:
		for second_cell: Vector2i in second:
			var delta := second_cell - first_cell
			if delta != Vector2i.ZERO and absi(delta.x) <= 1 and absi(delta.y) <= 1:
				return true
	return false
