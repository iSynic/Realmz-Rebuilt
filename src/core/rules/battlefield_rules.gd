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


func probe_step(battlefield: BattlefieldState, terrain_set: BattleTerrainSetDefinition, actor_id: String, direction: Vector2i, movement_available: int) -> BattlefieldStepResult:
	if battlefield == null or terrain_set == null or not battlefield.has_actor(actor_id):
		return BattlefieldStepResult.blocked(&"invalid_actor")
	if direction == Vector2i.ZERO or absi(direction.x) > 1 or absi(direction.y) > 1:
		return BattlefieldStepResult.blocked(&"invalid_direction")
	var destination := battlefield.actor_position(actor_id) + direction
	var footprint := battlefield.actor_footprint_at(actor_id, destination)
	if footprint.is_empty():
		return BattlefieldStepResult.blocked(&"invalid_actor", destination)
	var maximum_cost := 0
	for coordinate: Vector2i in footprint:
		if not BattlefieldState.contains(coordinate):
			return BattlefieldStepResult.blocked(&"outside_battlefield", destination)
		var occupant := battlefield.actor_at(coordinate, actor_id)
		if not occupant.is_empty():
			return BattlefieldStepResult.blocked(&"occupied", destination, occupant)
		var terrain := terrain_set.tile_by_id(battlefield.terrain_at(coordinate))
		if terrain == null:
			return BattlefieldStepResult.blocked(&"missing_terrain", destination)
		var size := battlefield.actor_size(actor_id)
		if size == 0 and terrain.solid != 0 or size > 0 and terrain.solid > 1:
			return BattlefieldStepResult.blocked(&"solid_terrain", destination)
		maximum_cost = maxi(maximum_cost, _movement_cost(terrain, direction))
	if maximum_cost > movement_available:
		var result := BattlefieldStepResult.blocked(&"insufficient_movement", destination)
		result.movement_cost = maximum_cost
		return result
	return BattlefieldStepResult.permitted(destination, maximum_cost)


static func _movement_cost(terrain: BattleTerrainTileDefinition, direction: Vector2i) -> int:
	var cost := maxi(0, floori(float(terrain.movement_time) / 2.0) - 1)
	if direction.x != 0:
		cost += 1
	if direction.y != 0:
		cost += 1
	return cost


static func _footprints_are_adjacent(first: Array[Vector2i], second: Array[Vector2i]) -> bool:
	if first.is_empty() or second.is_empty():
		return false
	for first_cell: Vector2i in first:
		for second_cell: Vector2i in second:
			var delta := second_cell - first_cell
			if delta != Vector2i.ZERO and absi(delta.x) <= 1 and absi(delta.y) <= 1:
				return true
	return false
