## Exposes detached, read-only navigation queries for one live session.

class_name SessionNavigationQueries
extends RefCounted

var _context: SessionContext


func _init(context: SessionContext) -> void:
	_context = context


func exploration_route(destination: Vector2i) -> Array[Vector2i]:
	var empty_route: Array[Vector2i] = []
	if not _exploration_context_is_available():
		return empty_route
	var state := _context.state
	var map := _context.content.world.map_by_id(state.party.map_id)
	if map == null or not map.topology.contains(state.party.coordinate) or not map.topology.contains(destination):
		return empty_route
	var revealed := state.world.exploration.seen_coordinates(map.id)
	if not map.uses_los:
		var known: Dictionary = {}
		for coordinate: Vector2i in revealed: known[coordinate] = true
		var visited := state.world.exploration.visited_coordinates(map.id)
		visited.append(state.party.coordinate)
		for coordinate: Vector2i in visited:
			var window := MapTopology.classic_exploration_window(coordinate, Vector2i(map.topology.width, map.topology.height)) if map.level_type == &"land" else Rect2i(coordinate - Vector2i.ONE, Vector2i(3, 3))
			for y: int in range(window.position.y, window.end.y):
				for x: int in range(window.position.x, window.end.x): known[Vector2i(x, y)] = true
		revealed.assign(known.keys())
	return map.topology.find_revealed_path(state.party.coordinate, destination, state.world, map.level_type, state.party_in_boat, revealed)


func combat_reachability() -> BattlefieldReachability:
	var unavailable := BattlefieldReachability.new()
	if not _combat_context_is_available():
		return unavailable
	var state := _context.state
	var combat := state.combat
	var actor_id := combat.turns.active_actor_id()
	var character := state.party.character_by_id(actor_id)
	if character == null or character.current_health <= 0 or combat.battlefield == null or not combat.battlefield.actors.has_actor(actor_id):
		return unavailable
	var active_turn := combat.turns.active_turn
	if active_turn != null and active_turn.actor_id != actor_id:
		return unavailable
	var map := _context.content.world.map_by_id(combat.battlefield.map_id)
	var terrain_set := _context.content.world.battle_terrain_set_for_map(map, state.world) if map != null else null
	if terrain_set == null:
		return unavailable
	var movement_available := character.maximum_movement if active_turn == null else character.movement
	return _context.rules.battlefield.reachable_destinations(combat.battlefield, terrain_set, actor_id, movement_available)


func _exploration_context_is_available() -> bool:
	if _context == null or _context.content == null or _context.state == null or _context.state.world == null or _context.state.party == null or _context.runtime_fault != null:
		return false
	if not _context.state.party_setup_completed or _context.state.combat != null and not _context.state.combat.completed:
		return false
	if _context.session_interaction != null or _context.scenario_vm == null:
		return false
	return _context.scenario_vm.pending_request() == null and not _context.scenario_vm.is_active()


func _combat_context_is_available() -> bool:
	if _context == null or _context.content == null or _context.state == null or _context.state.world == null or _context.state.party == null or _context.rules == null or _context.rules.battlefield == null or _context.runtime_fault != null:
		return false
	var state := _context.state
	var combat := state.combat
	if not state.party_setup_completed or combat == null or combat.completed or combat.outcome != &"active" or combat.turns == null or combat.battlefield == null or combat.pending_reaction != null or combat.turns.active_actor_id().is_empty():
		return false
	if _context.session_interaction != null or _context.scenario_vm == null:
		return false
	var pending := _context.scenario_vm.pending_request()
	if pending == null:
		return not _context.scenario_vm.is_active()
	if pending.kind != InteractionRequest.COMBAT:
		return false
	var body := pending.body as CombatRequestBody
	return body != null and body.battle_id == combat.battle_id and body.round_number == combat.turns.round_number and body.actor_id == combat.turns.active_actor_id()
