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


func has_line_of_sight(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, from_actor_id: String, to_actor_id: String) -> bool:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(from_actor_id) or not battlefield.has_actor(to_actor_id):
		return false
	return has_line_of_sight_to_coordinate(battlefield, terrain_set, from_actor_id, battlefield.actor_position(to_actor_id))


func has_line_of_sight_to_coordinate(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, from_actor_id: String, destination: Vector2i) -> bool:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(from_actor_id) or not BattlefieldState.contains(destination):
		return false
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
		if battlefield.actor_at(coordinate).is_empty():
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


func _probe_step_with_cost_floor(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, direction: Vector2i, movement_available: int, cost_floor: int) -> BattlefieldStepResult:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(actor_id):
		return BattlefieldStepResult.blocked(&"invalid_actor")
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		return BattlefieldStepResult.blocked(&"invalid_direction")
	var destination := battlefield.actor_position(actor_id) + direction
	var footprint := battlefield.actor_footprint_at(actor_id, destination)
	if footprint.is_empty():
		return BattlefieldStepResult.blocked(&"invalid_actor", destination)
	var maximum_cost := maxi(0, cost_floor)
	for coordinate: Vector2i in footprint:
		if not BattlefieldState.contains(coordinate):
			return _blocked_with_cost(&"outside_battlefield", destination, maximum_cost)
		var occupant := battlefield.actor_at(coordinate, actor_id)
		if not occupant.is_empty():
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
