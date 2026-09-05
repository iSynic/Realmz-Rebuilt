## Owns Classic exploration heading, fatigue admission, boat choices, and movement commits.

class_name ExplorationMovementWorkflow
extends RefCounted


class MovementTransitionResult:
	extends RefCounted
	var ok: bool
	var error_code: StringName
	var error_message: String
	var events: Array[DomainEvent]
	var post_clock: bool
	var map: MapDefinition
	var resume_kind: StringName
	var direction: Vector2i
	var check_random: bool
	var timed_day: int
	var timed_coordinate: Vector2i = Vector2i(-1, -1)
	var choice_kind: StringName
	var choice_movement: WorldMovementResult

	static func failed(code: StringName, message: String, committed_events: Array[DomainEvent] = []) -> MovementTransitionResult:
		var result := MovementTransitionResult.new()
		result.error_code = code
		result.error_message = message
		result.events = committed_events
		return result

	static func completed(committed_events: Array[DomainEvent]) -> MovementTransitionResult:
		var result := MovementTransitionResult.new()
		result.ok = true
		result.events = committed_events
		return result

	static func after_clock(current_map: MapDefinition, committed_events: Array[DomainEvent], completion_kind: StringName, next_direction: Vector2i, should_check_random: bool, midnight_day: int, check_coordinate: Vector2i) -> MovementTransitionResult:
		var result := completed(committed_events)
		result.post_clock = true
		result.map = current_map
		result.resume_kind = completion_kind
		result.direction = next_direction
		result.check_random = should_check_random
		result.timed_day = midnight_day
		result.timed_coordinate = check_coordinate
		return result

	static func awaiting_choice(kind: StringName, movement: WorldMovementResult, next_direction: Vector2i, committed_events: Array[DomainEvent]) -> MovementTransitionResult:
		var result := completed(committed_events)
		result.choice_kind = kind
		result.choice_movement = movement
		result.direction = next_direction
		return result


static func turn_dungeon(context: SessionWorkflowContext, delta: int) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or map.level_type != &"dungeon":
		return SessionWorkflowResult.failed(&"dungeon_turn_unavailable", "First-person turning is available only on a dungeon map.")
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"dungeon_turn_during_battle", "The party cannot turn the exploration view during battle.")
	if delta not in [-1, 1]:
		return SessionWorkflowResult.failed(&"invalid_dungeon_turn", "Dungeon turning requires one quarter-turn.")
	context.state.dungeon_heading = posmod(context.state.dungeon_heading - 1 + delta, 4) + 1
	return SessionWorkflowResult.completed([DomainEvent.new(&"dungeon_heading_changed", {"heading": context.state.dungeon_heading, "delta": delta, "source": "classic"})])


static func fatigue_warning(context: SessionWorkflowContext) -> DomainEvent:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if context.state.party.fatigue <= 134 or map == null:
		return null
	# Castle permits exhausted land travel only when camping was disabled by the
	# scenario, preventing a party from becoming trapped without a way to rest.
	if map.level_type == &"land" and not context.state.camping_allowed:
		return null
	return DomainEvent.new(&"classic_notification_requested", {
		"text": "You are too tired to continue.  You need to rest.",
		"soundId": 6000,
		"source": "classic-movement-fatigue",
	})


static func align_dungeon_heading(context: SessionWorkflowContext, direction: Vector2i) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return SessionWorkflowResult.failed(&"unknown_map", "The current map is unavailable for dungeon movement.")
	if map.level_type != &"dungeon":
		return SessionWorkflowResult.completed()
	var heading := _dungeon_heading_for_direction(direction)
	if heading == 0:
		return SessionWorkflowResult.failed(&"invalid_direction", "Dungeon movement requires one cardinal direction.")
	if heading == context.state.dungeon_heading:
		return SessionWorkflowResult.completed()
	var previous := context.state.dungeon_heading
	context.state.dungeon_heading = heading
	return SessionWorkflowResult.completed([DomainEvent.new(&"dungeon_heading_changed", {"previous": previous, "current": heading, "direction": [direction.x, direction.y], "source": "classic-overhead-movement"})])


static func depart_camp(context: SessionWorkflowContext, direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> MovementTransitionResult:
	var movement := context.content.world.probe_movement(context.state.party.map_id, context.state.party.coordinate, direction, context.state.world, context.state.party_in_boat)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return MovementTransitionResult.failed(&"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return MovementTransitionResult.failed(&"unknown_map", "The current map is unavailable for camp departure.")
	context.state.party_camping = false
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"camp_mode_changed", {"camping": false, "source": "classic-movement"}))
	events.append(DomainEvent.new(&"camp_departed_for_movement", {"mapId": map.id, "x": context.state.party.coordinate.x, "y": context.state.party.coordinate.y, "direction": [direction.x, direction.y], "source": "classic"}))
	var previous_day := context.state.clock.day()
	var departure_clicks := 2 if map.level_type == &"dungeon" else 5
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, departure_clicks, ExplorationTimeWorkflow.classic_time_scale(map), true))
	return MovementTransitionResult.after_clock(map, events, &"move" if map.level_type == &"dungeon" else &"camp-departure-second", direction, map.level_type == &"dungeon", context.state.clock.day() if context.state.clock.day() != previous_day else 0, context.state.party.coordinate + direction)


static func complete_land_camp_departure(context: SessionWorkflowContext, direction: Vector2i, preceding_events: Array[DomainEvent]) -> MovementTransitionResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or map.level_type != &"land" or context.state.party_camping:
		return MovementTransitionResult.failed(&"invalid_camp_departure", "The second movement-departure time stage is unavailable.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 10, ExplorationTimeWorkflow.classic_time_scale(map), true))
	return MovementTransitionResult.after_clock(map, events, &"move", direction, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0, context.state.party.coordinate + direction)


static func commit(context: SessionWorkflowContext, direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> MovementTransitionResult:
	var movement := context.content.world.probe_movement(context.state.party.map_id, context.state.party.coordinate, direction, context.state.world, context.state.party_in_boat)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return MovementTransitionResult.failed(&"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	if not movement.allowed:
		if movement.reason == &"board_boat":
			context.state.boat_shore_attempts = 0
			return MovementTransitionResult.awaiting_choice(&"board", movement, direction, preceding_events)
		if movement.reason == &"boat_shore":
			context.state.boat_shore_attempts += 1
			if context.state.boat_shore_attempts > 2:
				context.state.boat_shore_attempts = 0
				return MovementTransitionResult.awaiting_choice(&"disembark", movement, direction, preceding_events)
		elif not (context.state.party_in_boat and movement.reason == &"boat_terrain_blocked"):
			context.state.boat_shore_attempts = 0
		return commit_blocked(context, movement, preceding_events)
	context.state.boat_shore_attempts = 0
	return commit_permitted(context, movement, direction, preceding_events)


static func commit_blocked(context: SessionWorkflowContext, movement: WorldMovementResult, preceding_events: Array[DomainEvent] = [], include_collision_sound: bool = true) -> MovementTransitionResult:
	var blocked_events: Array[DomainEvent] = []
	blocked_events.assign(preceding_events)
	blocked_events.append(DomainEvent.new(&"movement_blocked", {"reason": String(movement.reason)}))
	if include_collision_sound and context.state.party_in_boat and movement.reason in [&"boat_shore", &"boat_terrain_blocked"]:
		blocked_events.append(sound_event(-148, "classic-boat-collision"))
	_append_movement_sound(blocked_events, movement)
	var attempt_cost := _blocked_land_attempt_cost(movement)
	var searches_after_attempt := movement.source_map != null and movement.source_map.level_type == &"land"
	if attempt_cost <= 0:
		return MovementTransitionResult.after_clock(movement.source_map, blocked_events, &"attempt-search-completed", Vector2i.ZERO, false, 0, movement.target_coordinate) if searches_after_attempt else MovementTransitionResult.completed(blocked_events)
	var previous_day := context.state.clock.day()
	blocked_events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, attempt_cost, ExplorationTimeWorkflow.classic_time_scale(movement.source_map), true))
	return MovementTransitionResult.after_clock(movement.source_map, blocked_events, &"attempt-search-completed" if searches_after_attempt else &"completed", Vector2i.ZERO, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0, movement.target_coordinate)


static func commit_permitted(context: SessionWorkflowContext, movement: WorldMovementResult, direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> MovementTransitionResult:
	if movement == null or not movement.allowed:
		return MovementTransitionResult.failed(&"invalid_movement", "The permitted movement result is unavailable.", preceding_events)
	var target_map := movement.target_map
	var target_coordinate := movement.target_coordinate
	var transition := movement.transition
	var probe := movement.topology_result
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	if not probe.door_id.is_empty() and not context.state.world.topology.door_is_open(probe.door_id):
		context.state.world.topology.open_door(probe.door_id)
		events.append(DomainEvent.new(&"door_opened", {"doorId": probe.door_id}))
	if not probe.secret_id.is_empty() and not context.state.world.topology.secret_is_discovered(probe.secret_id):
		context.state.world.topology.discover_secret(probe.secret_id)
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": probe.secret_id, "byMovement": true}))
	var source_map_id := context.state.party.map_id
	var source_coordinate := context.state.party.coordinate
	var cleared_services := not context.state.location_services.active_shop_id.is_empty() or context.state.location_services.temple_available or context.state.location_services.bank_available
	if context.state.location_services.bank_available:
		context.rules.economy.pool_to_bank(context.state.party)
	context.state.location_services.clear()
	if cleared_services:
		events.append(DomainEvent.new(&"location_services_cleared", {"mapId": source_map_id, "x": source_coordinate.x, "y": source_coordinate.y}))
	context.state.party.map_id = target_map.id
	context.state.party.coordinate = target_coordinate
	context.state.last_move_direction = direction
	context.state.world.exploration.mark_visited(target_map.id, target_coordinate)
	events.append(DomainEvent.new(&"party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": target_coordinate.x, "y": target_coordinate.y}))
	_append_movement_sound(events, movement)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, probe.target_cell.movement_cost, ExplorationTimeWorkflow.classic_time_scale(target_map), true))
	if transition != null:
		events.append(DomainEvent.new(&"map_transitioned", {"transitionId": transition.id, "sourceMapId": source_map_id, "targetMapId": target_map.id}))
	var resume_kind := &"attempt-search-post-move" if target_map.level_type == &"land" else &"post-move"
	return MovementTransitionResult.after_clock(target_map, events, resume_kind, Vector2i.ZERO, false, context.state.clock.day() if context.state.clock.day() != previous_day else 0, target_coordinate)


static func sound_event(sound_id: int, source: String) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": source})


static func _dungeon_heading_for_direction(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return 1
	if direction == Vector2i.RIGHT:
		return 2
	if direction == Vector2i.DOWN:
		return 3
	if direction == Vector2i.LEFT:
		return 4
	return 0


static func _blocked_land_attempt_cost(movement: WorldMovementResult) -> int:
	if movement == null or movement.source_map == null or movement.source_map.level_type != &"land":
		return 0
	if movement.reason not in [&"terrain_blocked", &"secret_hidden", &"board_boat", &"water_requires_boat", &"boat_shore", &"boat_terrain_blocked"] or movement.topology_result == null or movement.topology_result.target_cell == null:
		return 0
	return maxi(0, movement.topology_result.target_cell.blocked_attempt_timeclicks)


static func _append_movement_sound(events: Array[DomainEvent], movement: WorldMovementResult) -> void:
	if movement == null or movement.topology_result == null or movement.topology_result.target_cell == null:
		return
	var sound_id := movement.topology_result.target_cell.movement_sound_id
	if sound_id != 0:
		events.append(sound_event(sound_id, "classic-map-movement"))
