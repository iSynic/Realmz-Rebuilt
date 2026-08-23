class_name BattlefieldRules
extends RefCounted

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]


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


func probe_path_step_toward_actors(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, target_ids: Array[String], movement_available: int) -> BattlefieldStepResult:
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
	var target_cells: Dictionary = {}
	for target_id: String in valid_targets:
		for coordinate: Vector2i in battlefield.actor_footprint(target_id):
			target_cells[coordinate] = true
	var goals := _route_goal_anchors(target_cells, actor_size)
	var origin_index := _route_index(origin)
	if goals[origin_index] != 0:
		return BattlefieldStepResult.blocked(&"already_adjacent", origin)
	var occupied_cells: Dictionary = {}
	for candidate_id: String in battlefield.actor_ids():
		if candidate_id == actor_id:
			continue
		for coordinate: Vector2i in battlefield.actor_footprint(candidate_id):
			occupied_cells[coordinate] = true
	var heuristics := _route_heuristics(goals)
	var distances := PackedInt32Array()
	distances.resize(BattlefieldState.CELL_COUNT)
	distances.fill(0x3fff_ffff)
	distances[origin_index] = 0
	var first_steps := PackedInt32Array()
	first_steps.resize(BattlefieldState.CELL_COUNT)
	first_steps.fill(-1)
	var closed := PackedByteArray()
	closed.resize(BattlefieldState.CELL_COUNT)
	var heap: Array[Vector4i] = []
	var sequence := 0
	_route_heap_push(heap, Vector4i(heuristics[origin_index], heuristics[origin_index], sequence, origin_index))
	while not heap.is_empty():
		var current := _route_heap_pop(heap)
		var current_index := current.w
		if closed[current_index] != 0:
			continue
		closed[current_index] = 1
		if goals[current_index] != 0:
			var first_step := _route_coordinate(first_steps[current_index])
			return _probe_step_with_cost_floor(battlefield, terrain_set, actor_id, first_step - origin, movement_available, 0)
		var anchor := _route_coordinate(current_index)
		for direction: Vector2i in DIRECTIONS:
			# Only the immediate step must respect current actors. Later route cells
			# are a wall-following forecast: mobile combatants may vacate them before
			# this actor reaches them, while terrain remains authoritative.
			var destination := anchor + direction
			if not BattlefieldState.contains(destination):
				continue
			var destination_index := _route_index(destination)
			if closed[destination_index] != 0:
				continue
			var footprint := BattlefieldState.footprint_cells(destination, actor_size)
			if not _route_footprint_is_passable(battlefield, terrain_set, actor_size, footprint, occupied_cells, anchor == origin):
				continue
			var next_distance := distances[current_index] + 1
			if next_distance >= distances[destination_index]:
				continue
			distances[destination_index] = next_distance
			first_steps[destination_index] = destination_index if current_index == origin_index else first_steps[current_index]
			sequence += 1
			_route_heap_push(heap, Vector4i(next_distance + heuristics[destination_index], heuristics[destination_index], sequence, destination_index))
	return BattlefieldStepResult.blocked(&"path_not_found", origin)


static func _route_footprint_is_passable(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_size: int, footprint: Array[Vector2i], occupied_cells: Dictionary, respect_occupants: bool) -> bool:
	for coordinate: Vector2i in footprint:
		if not BattlefieldState.contains(coordinate) or respect_occupants and occupied_cells.has(coordinate):
			return false
		var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
		if terrain == null or actor_size == 0 and terrain.solid != 0 or actor_size > 0 and terrain.solid > 1:
			return false
	return true


static func _route_goal_anchors(target_cells: Dictionary, actor_size: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(BattlefieldState.CELL_COUNT)
	var offsets := BattlefieldState.footprint_cells(Vector2i.ZERO, actor_size)
	for value: Variant in target_cells:
		var target_cell: Vector2i = value
		for direction: Vector2i in DIRECTIONS:
			for offset: Vector2i in offsets:
				var anchor := target_cell - direction - offset
				if BattlefieldState.contains(anchor):
					result[_route_index(anchor)] = 1
	return result


static func _route_heuristics(goals: PackedByteArray) -> PackedInt32Array:
	var result := PackedInt32Array()
	result.resize(BattlefieldState.CELL_COUNT)
	result.fill(0x3fff_ffff)
	var queue := PackedInt32Array()
	queue.resize(BattlefieldState.CELL_COUNT)
	var cursor := 0
	var count := 0
	for index: int in BattlefieldState.CELL_COUNT:
		if goals[index] != 0:
			result[index] = 0
			queue[count] = index
			count += 1
	while cursor < count:
		var index := queue[cursor]
		cursor += 1
		var coordinate := _route_coordinate(index)
		for direction: Vector2i in DIRECTIONS:
			var neighbor := coordinate + direction
			if not BattlefieldState.contains(neighbor):
				continue
			var neighbor_index := _route_index(neighbor)
			if result[neighbor_index] <= result[index] + 1:
				continue
			result[neighbor_index] = result[index] + 1
			queue[count] = neighbor_index
			count += 1
	return result


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
	var cost := maxi(0, floori(float(terrain.movement_time) / 2.0) - 1)
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
