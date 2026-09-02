class_name ExplorationTimeWorkflow
extends RefCounted


class ClockTransitionResult:
	extends RefCounted
	var ok: bool
	var error_code: StringName
	var error_message: String
	var events: Array[DomainEvent]
	var map: MapDefinition
	var check_random: bool
	var timed_day: int

	static func failed(code: StringName, message: String, committed_events: Array[DomainEvent] = []) -> ClockTransitionResult:
		var result := ClockTransitionResult.new()
		result.error_code = code
		result.error_message = message
		result.events = committed_events
		return result

	static func completed(current_map: MapDefinition, committed_events: Array[DomainEvent], should_check_random: bool, midnight_day: int) -> ClockTransitionResult:
		var result := ClockTransitionResult.new()
		result.ok = true
		result.map = current_map
		result.events = committed_events
		result.check_random = should_check_random
		result.timed_day = midnight_day
		return result


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

static func toggle_camp(context: SessionWorkflowContext) -> ClockTransitionResult:
	if context.state.combat != null and not context.state.combat.completed:
		return ClockTransitionResult.failed(&"camp_during_battle", "The party cannot camp during battle.")
	if not context.state.camping_allowed and not context.state.party_camping:
		return ClockTransitionResult.failed(&"camping_disabled", "Camping is not allowed at this location.")
	context.state.party_camping = not context.state.party_camping
	var events: Array[DomainEvent] = [
		_sound_event(10001 if context.state.party_camping else 141, "classic-camp-enter" if context.state.party_camping else "classic-camp-exit"),
		DomainEvent.new(&"camp_mode_changed", {"camping": context.state.party_camping, "source": "classic"}),
	]
	if context.state.party_camping:
		context.state.clear_location_services()
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Camp.", events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 3 if context.state.party_camping else 2, classic_time_scale(map), true))
	var crossed_midnight := context.state.clock.day() != previous_day
	return ClockTransitionResult.completed(map, events, false, context.state.clock.day() if crossed_midnight else 0)


static func complete_camp_entry(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> ClockTransitionResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or not context.state.party_camping:
		return ClockTransitionResult.failed(&"invalid_camp_entry", "The second Camp time stage is unavailable.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 2, classic_time_scale(map), true))
	return ClockTransitionResult.completed(map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func rest(context: SessionWorkflowContext) -> ClockTransitionResult:
	if context.state.combat != null and not context.state.combat.completed:
		return ClockTransitionResult.failed(&"rest_during_battle", "The party cannot rest during battle.")
	if not context.state.party_camping:
		return ClockTransitionResult.failed(&"rest_outside_camp", "Make camp before resting.")
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Rest.")
	var previous_fatigue := context.state.party.fatigue
	context.rules.clock.change_fatigue(context.state.party, -2)
	var events: Array[DomainEvent] = [DomainEvent.new(&"fatigue_changed", {"previous": previous_fatigue, "current": context.state.party.fatigue, "reason": "rest", "source": "classic"})]
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 3, classic_time_scale(map), true))
	return ClockTransitionResult.completed(map, events, false, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func complete_rest(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> ClockTransitionResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or not context.state.party_camping:
		return ClockTransitionResult.failed(&"invalid_rest_stage", "The second Rest time stage is unavailable.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 2, classic_time_scale(map), true))
	events.append(DomainEvent.new(&"party_rested", {"timeclicks": 5, "mapId": map.id, "source": "classic"}))
	return ClockTransitionResult.completed(map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func heal(context: SessionWorkflowContext) -> ClockTransitionResult:
	if context.state.combat != null and not context.state.combat.completed:
		return ClockTransitionResult.failed(&"heal_during_battle", "The party cannot use field Heal during battle.")
	if context.state.party.fatigue > 134:
		return ClockTransitionResult.failed(&"heal_exhausted", "The party is too fatigued to continue Heal.")
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Heal.")
	var previous_day := context.state.clock.day()
	var events: Array[DomainEvent] = [_sound_event(10105, "classic-heal")]
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 5 if map.level_type == &"dungeon" else 1, classic_time_scale(map), true))
	return ClockTransitionResult.completed(map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func complete_heal(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> SessionWorkflowResult:
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	for healer: CharacterState in context.state.party.characters():
		if not _eligible_field_healer(context, healer):
			continue
		for target: CharacterState in context.state.party.characters():
			if target.current_health >= target.maximum_health or target.current_health <= -10 or target.conditions.is_active(ConditionRules.TURNED_TO_STONE) or healer.spell_points < 10:
				continue
			healer.spell_points -= 10
			var amount := mini(context.rng.draw(8, StringName("exploration.heal.%s.%s" % [healer.id, target.id])), target.maximum_health - target.current_health)
			target.current_health += amount
			events.append(DomainEvent.new(&"spell_points_spent", {"characterId": healer.id, "amount": 10, "source": "classic-heal"}))
			events.append(DomainEvent.new(&"health_recovered", {"characterId": target.id, "amount": amount, "source": "classic-heal"}))
	events.append(DomainEvent.new(&"party_heal_completed", {"mapId": context.state.party.map_id, "source": "classic"}))
	return SessionWorkflowResult.completed(events)


static func _eligible_field_healer(context: SessionWorkflowContext, character: CharacterState) -> bool:
	if character == null or character.spellcaster_type not in [1, 2] or character.current_health < 1 or character.spell_points < 10 or context.state.character_spellcasting_blocked:
		return false
	for condition_index: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if character.conditions.is_active(condition_index):
			return false
	for spell_id: String in character.known_spells():
		var spell := context.content.spell_by_id(spell_id)
		if spell != null and absi(spell.special) == 57:
			return true
	return false


static func search(context: SessionWorkflowContext) -> ClockTransitionResult:
	if context.state.party_camping:
		return ClockTransitionResult.failed(&"search_while_camped", "Search is replaced by scroll scribing while camped.")
	if context.state.party.fatigue > 134:
		return ClockTransitionResult.failed(&"area_search_exhausted", "The party is too fatigued to continue Area Search.")
	context.state.mark_searched(context.state.party.map_id, context.state.party.coordinate)
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Area Search.")
	var discovered: Array[String] = []
	var first_roll: int = 0
	for y: int in range(context.state.party.coordinate.y - 1, context.state.party.coordinate.y + 2):
		for x: int in range(context.state.party.coordinate.x - 1, context.state.party.coordinate.x + 2):
			var cell := current_map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			for feature: MapFeature in cell.features():
				if feature.kind != &"secret" or context.state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
					continue
				var roll := context.rng.draw(100, StringName("exploration.search.%s" % feature.id))
				if first_roll == 0:
					first_roll = roll
				if roll <= 100:
					context.state.world.discover_secret(feature.id)
					discovered.append(feature.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"search_completed", {"mapId": context.state.party.map_id, "x": context.state.party.coordinate.x, "y": context.state.party.coordinate.y, "roll": first_roll, "discoveredSecrets": discovered})]
	for secret_id: String in discovered:
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": secret_id}))
	var previous_day := context.state.clock.day()
	# Castle's held Area Search first calls checkforsecret(TRUE), which advances
	# four field timeclicks. Its separate outer timeclick and random check resume
	# only after this phase's timed/random continuation has settled.
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 4, classic_time_scale(current_map), true))
	return ClockTransitionResult.completed(current_map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func search_after_land_movement_attempt(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> ClockTransitionResult:
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for the post-movement secret check.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	if current_map.level_type != &"land":
		return ClockTransitionResult.completed(current_map, events, false, 0)
	var chance := 0
	var characters := context.state.party.characters()
	for character: CharacterState in characters:
		chance += character.special_value(4)
	if not characters.is_empty():
		chance /= characters.size()
	var searching := context.state.party.conditions.is_active(ConditionRules.PARTY_SEARCHING)
	if searching or context.state.party.conditions.is_active(ConditionRules.PARTY_DISCOVER_SECRET):
		chance = 100
	var discovered: Array[String] = []
	var first_roll := 0
	for y: int in range(context.state.party.coordinate.y - 1, context.state.party.coordinate.y + 2):
		for x: int in range(context.state.party.coordinate.x - 1, context.state.party.coordinate.x + 2):
			var cell := current_map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			for feature: MapFeature in cell.features():
				if feature.kind != &"secret" or context.state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
					continue
				var roll := context.rng.draw(100, StringName("exploration.movement-search.%s" % feature.id))
				if first_roll == 0:
					first_roll = roll
				if roll <= chance:
					context.state.world.discover_secret(feature.id)
					discovered.append(feature.id)
	events.append(DomainEvent.new(&"movement_secret_search_completed", {"mapId": current_map.id, "x": context.state.party.coordinate.x, "y": context.state.party.coordinate.y, "roll": first_roll, "chance": chance, "discoveredSecrets": discovered}))
	for secret_id: String in discovered:
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": secret_id, "byMovementAttempt": true}))
	var previous_day := context.state.clock.day()
	if searching:
		events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 4, classic_time_scale(current_map), true))
	return ClockTransitionResult.completed(current_map, events, searching, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func complete_area_search(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> ClockTransitionResult:
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Area Search.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 1, classic_time_scale(current_map), true))
	return ClockTransitionResult.completed(current_map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func toggle_search(context: SessionWorkflowContext) -> SessionWorkflowResult:
	if context.state.party_camping:
		return SessionWorkflowResult.failed(&"search_while_camped", "Search is replaced by scroll scribing while camped.")
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"search_during_battle", "Search mode is unavailable during battle.")
	var searching := not context.state.party.conditions.is_active(ConditionRules.PARTY_SEARCHING)
	context.state.party.conditions.set_value(ConditionRules.PARTY_SEARCHING, -1 if searching else 0)
	return SessionWorkflowResult.completed([
		DomainEvent.new(&"search_mode_changed", {"searching": searching, "source": "classic"}),
		_sound_event(141, "classic-search-mode"),
	])


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


static func align_dungeon_heading_for_overhead_move(context: SessionWorkflowContext, direction: Vector2i) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return SessionWorkflowResult.failed(&"unknown_map", "The current map is unavailable for dungeon movement.")
	if map.level_type != &"dungeon":
		return SessionWorkflowResult.completed()
	var heading := dungeon_heading_for_direction(direction)
	if heading == 0:
		return SessionWorkflowResult.failed(&"invalid_direction", "Dungeon movement requires one cardinal direction.")
	if heading == context.state.dungeon_heading:
		return SessionWorkflowResult.completed()
	var previous := context.state.dungeon_heading
	context.state.dungeon_heading = heading
	return SessionWorkflowResult.completed([DomainEvent.new(&"dungeon_heading_changed", {"previous": previous, "current": heading, "direction": [direction.x, direction.y], "source": "classic-overhead-movement"})])


static func dungeon_heading_for_direction(direction: Vector2i) -> int:
	if direction == Vector2i.UP:
		return 1
	if direction == Vector2i.RIGHT:
		return 2
	if direction == Vector2i.DOWN:
		return 3
	if direction == Vector2i.LEFT:
		return 4
	return 0


static func depart_camp_for_movement(context: SessionWorkflowContext, direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> MovementTransitionResult:
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
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, departure_clicks, classic_time_scale(map), true))
	return MovementTransitionResult.after_clock(map, events, &"move" if map.level_type == &"dungeon" else &"camp-departure-second", direction, map.level_type == &"dungeon", context.state.clock.day() if context.state.clock.day() != previous_day else 0, context.state.party.coordinate + direction)


static func complete_land_camp_departure(context: SessionWorkflowContext, direction: Vector2i, preceding_events: Array[DomainEvent]) -> MovementTransitionResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or map.level_type != &"land" or context.state.party_camping:
		return MovementTransitionResult.failed(&"invalid_camp_departure", "The second movement-departure time stage is unavailable.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 10, classic_time_scale(map), true))
	return MovementTransitionResult.after_clock(map, events, &"move", direction, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0, context.state.party.coordinate + direction)


static func commit_move(context: SessionWorkflowContext, direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> MovementTransitionResult:
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
		return commit_blocked_attempt(context, movement, preceding_events)
	context.state.boat_shore_attempts = 0
	return commit_permitted_move(context, movement, direction, preceding_events)


static func commit_blocked_attempt(context: SessionWorkflowContext, movement: WorldMovementResult, preceding_events: Array[DomainEvent] = [], include_collision_sound: bool = true) -> MovementTransitionResult:
	var blocked_events: Array[DomainEvent] = []
	blocked_events.assign(preceding_events)
	blocked_events.append(DomainEvent.new(&"movement_blocked", {"reason": String(movement.reason)}))
	if include_collision_sound and context.state.party_in_boat and movement.reason in [&"boat_shore", &"boat_terrain_blocked"]:
		blocked_events.append(_sound_event(-148, "classic-boat-collision"))
	append_movement_sound(blocked_events, movement)
	var attempt_cost := blocked_land_attempt_cost(movement)
	var searches_after_attempt := movement.source_map != null and movement.source_map.level_type == &"land"
	if attempt_cost <= 0:
		return MovementTransitionResult.after_clock(movement.source_map, blocked_events, &"attempt-search-completed", Vector2i.ZERO, false, 0, movement.target_coordinate) if searches_after_attempt else MovementTransitionResult.completed(blocked_events)
	var previous_day := context.state.clock.day()
	blocked_events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, attempt_cost, classic_time_scale(movement.source_map), true))
	return MovementTransitionResult.after_clock(movement.source_map, blocked_events, &"attempt-search-completed" if searches_after_attempt else &"completed", Vector2i.ZERO, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0, movement.target_coordinate)


static func commit_permitted_move(context: SessionWorkflowContext, movement: WorldMovementResult, direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> MovementTransitionResult:
	if movement == null or not movement.allowed:
		return MovementTransitionResult.failed(&"invalid_movement", "The permitted movement result is unavailable.", preceding_events)
	var target_map := movement.target_map
	var target_coordinate := movement.target_coordinate
	var transition := movement.transition
	var probe := movement.topology_result
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	if not probe.door_id.is_empty() and not context.state.world.door_is_open(probe.door_id):
		context.state.world.open_door(probe.door_id)
		events.append(DomainEvent.new(&"door_opened", {"doorId": probe.door_id}))
	if not probe.secret_id.is_empty() and not context.state.world.secret_is_discovered(probe.secret_id):
		context.state.world.discover_secret(probe.secret_id)
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": probe.secret_id, "byMovement": true}))
	var source_map_id := context.state.party.map_id
	var source_coordinate := context.state.party.coordinate
	var cleared_services := not context.state.active_shop_id.is_empty() or context.state.temple_available or context.state.bank_available
	if context.state.bank_available:
		context.rules.economy.pool_to_bank(context.state.party)
	context.state.clear_location_services()
	if cleared_services:
		events.append(DomainEvent.new(&"location_services_cleared", {"mapId": source_map_id, "x": source_coordinate.x, "y": source_coordinate.y}))
	context.state.party.map_id = target_map.id
	context.state.party.coordinate = target_coordinate
	context.state.last_move_direction = direction
	context.state.world.mark_visited(target_map.id, target_coordinate)
	events.append(DomainEvent.new(&"party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": target_coordinate.x, "y": target_coordinate.y}))
	append_movement_sound(events, movement)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, probe.target_cell.movement_cost, classic_time_scale(target_map), true))
	if transition != null:
		events.append(DomainEvent.new(&"map_transitioned", {"transitionId": transition.id, "sourceMapId": source_map_id, "targetMapId": target_map.id}))
	var resume_kind := &"attempt-search-post-move" if target_map.level_type == &"land" else &"post-move"
	return MovementTransitionResult.after_clock(target_map, events, resume_kind, Vector2i.ZERO, false, context.state.clock.day() if context.state.clock.day() != previous_day else 0, target_coordinate)


static func blocked_land_attempt_cost(movement: WorldMovementResult) -> int:
	if movement == null or movement.source_map == null or movement.source_map.level_type != &"land":
		return 0
	if movement.reason not in [&"terrain_blocked", &"secret_hidden", &"board_boat", &"water_requires_boat", &"boat_shore", &"boat_terrain_blocked"] or movement.topology_result == null or movement.topology_result.target_cell == null:
		return 0
	return maxi(0, movement.topology_result.target_cell.blocked_attempt_timeclicks)


static func append_movement_sound(events: Array[DomainEvent], movement: WorldMovementResult) -> void:
	if movement == null or movement.topology_result == null or movement.topology_result.target_cell == null:
		return
	var sound_id := movement.topology_result.target_cell.movement_sound_id
	if sound_id != 0:
		events.append(_sound_event(sound_id, "classic-map-movement"))


static func _sound_event(sound_id: int, source: String) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": source})


static func post_time_continuation(context: SessionWorkflowContext, map: MapDefinition, resume_kind: StringName, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> SessionContinuation:
	var cell := map.topology.cell_at(context.state.party.coordinate)
	var exploration := SessionContinuation.ExplorationBody.new()
	exploration.map_id = map.id
	exploration.coordinate = context.state.party.coordinate
	exploration.timed_day = timed_day
	exploration.timed_encounter_index = 0
	exploration.active_timed_program_id = ""
	exploration.midnight_recovery_pending = timed_day > 0
	exploration.timed_check_coordinate = timed_coordinate
	exploration.check_random = check_random
	var region_ids: Array[String] = [] if cell == null else context.state.world.random_region_ids_at(map, context.state.party.coordinate)
	exploration.random_region_ids.assign(region_ids)
	exploration.random_region_index = region_ids.size() - 1
	exploration.active_random_program_id = ""
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	exploration.resume_kind = resume_kind
	exploration.direction = direction
	return SessionContinuation.post_clock(exploration)


static func post_move_continuation(context: SessionWorkflowContext, map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> SessionContinuation:
	var cell := map.topology.cell_at(coordinate)
	var exploration := SessionContinuation.ExplorationBody.new()
	exploration.map_id = map.id
	exploration.coordinate = coordinate
	exploration.trigger_ids.assign(selected_placed_trigger_ids(context.content, cell, context.state.world))
	exploration.trigger_index = 0
	exploration.active_trigger_id = ""
	var region_ids := context.state.world.random_region_ids_at(map, coordinate)
	exploration.random_region_ids.assign(region_ids)
	exploration.random_region_index = region_ids.size() - 1
	exploration.active_random_program_id = ""
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	exploration.action_point_destination_depth = destination_depth
	return SessionContinuation.post_move(exploration)


static func rebase_post_time_location(context: SessionWorkflowContext, continuation: SessionContinuation) -> bool:
	var exploration := continuation.exploration()
	if continuation.kind != &"post-clock" or exploration == null:
		return false
	var map := context.content.world.map_by_id(context.state.party.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(context.state.party.coordinate)
	if cell == null:
		return false
	exploration.map_id = map.id
	exploration.coordinate = context.state.party.coordinate
	exploration.timed_check_coordinate = context.state.party.coordinate
	var region_ids := context.state.world.random_region_ids_at(map, context.state.party.coordinate)
	exploration.random_region_ids.assign(region_ids)
	exploration.random_region_index = region_ids.size() - 1
	return true


static func apply_pending_midnight_recovery(context: SessionWorkflowContext, exploration: SessionContinuation.ExplorationBody, events: Array[DomainEvent]) -> void:
	if exploration == null or not exploration.midnight_recovery_pending:
		return
	exploration.midnight_recovery_pending = false
	events.append_array(context.rules.clock.restore_half_day_health(context.state.party, context.content))


static func timed_encounter_requirements_met(context: SessionWorkflowContext, encounter: TimedEncounterDefinition, map: MapDefinition, exploration: SessionContinuation.ExplorationBody) -> bool:
	if encounter.required_item_id > 0 and not party_has_classic_item(context, encounter.required_item_id):
		return false
	if encounter.required_quest_id > -1 and not context.state.quest_is_set(encounter.required_quest_id):
		return false
	if encounter.location_kind == TimedEncounterDefinition.LocationKind.ANY:
		return true
	if encounter.location_kind == TimedEncounterDefinition.LocationKind.LAND and map.level_type != &"land" or encounter.location_kind == TimedEncounterDefinition.LocationKind.DUNGEON and map.level_type != &"dungeon":
		return false
	if map.level_index != encounter.required_level or exploration == null:
		return false
	var coordinate := exploration.timed_check_coordinate
	if encounter.required_random_rectangle > -1:
		var region := map.random_region_by_index(encounter.required_random_rectangle)
		if region == null or not context.state.world.random_region(region).contains(region.bounds, coordinate):
			return false
	if encounter.required_x > -1 and coordinate.x != encounter.required_x:
		return false
	if encounter.required_y > -1 and coordinate.y != encounter.required_y:
		return false
	return true


static func party_has_classic_item(context: SessionWorkflowContext, classic_item_id: int) -> bool:
	var definition := context.content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in context.state.party.characters():
		for item: ItemInstance in character.inventory():
			if item.definition_id == definition.id:
				return true
	return false


static func classic_time_scale(map: MapDefinition) -> int:
	return 1 if map != null and map.level_type == &"dungeon" else 5


static func selected_placed_trigger_ids(content: RealmzContent, cell: MapCell, world_state: WorldState) -> Array[String]:
	for feature: MapFeature in cell.features():
		if cell.is_land and feature.kind == &"secret" and feature.orientation.is_empty() and not world_state.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			return []
	var selected_id := ""
	var selected_record_index := 2_147_483_647
	for trigger_id: String in cell.trigger_ids():
		var trigger := content.trigger_by_id(trigger_id)
		if trigger != null and trigger.classic_record_index < selected_record_index:
			selected_id = trigger.id
			selected_record_index = trigger.classic_record_index
	var selected_ids: Array[String] = []
	if not selected_id.is_empty():
		selected_ids.append(selected_id)
	return selected_ids


static func set_location_note(context: SessionWorkflowContext, text: String) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null or map.topology.cell_at(context.state.party.coordinate) == null:
		return SessionWorkflowResult.failed(&"location_note_unavailable", "The current map location is unavailable.")
	if not LocationNoteState.text_is_valid(text):
		return SessionWorkflowResult.failed(&"location_note_too_long", "Classic location notes are limited to 255 encoded bytes.")
	var existing := context.state.world.location_note_at(map.id, context.state.party.coordinate)
	var darkness_value := _current_location_note_darkness(context, map)
	if existing == null and not text.is_empty() and context.state.world.next_location_note_ordinal(map.level_type) < 0:
		return SessionWorkflowResult.failed(&"location_note_capacity", "The Classic location-note file for this map type is full.")
	if existing != null and existing.text == text and existing.darkness_value == darkness_value or existing == null and text.is_empty():
		return SessionWorkflowResult.failed(&"location_note_unchanged", "Change or clear the current location note before saving.")
	var committed := false
	if text.is_empty():
		committed = context.state.world.remove_location_note(map.id, context.state.party.coordinate)
	else:
		var ordinal := existing.record_ordinal if existing != null else context.state.world.next_location_note_ordinal(map.level_type)
		committed = context.state.world.upsert_location_note(LocationNoteState.new(map.id, map.level_type, map.level_index, context.state.party.coordinate, text, darkness_value, ordinal))
	if not committed:
		return SessionWorkflowResult.failed(&"invalid_location_note", "The location note could not be committed.")
	var event_kind: StringName = &"location_note_removed" if text.is_empty() else &"location_note_updated"
	return SessionWorkflowResult.completed([DomainEvent.new(event_kind, {
		"mapId": map.id,
		"x": context.state.party.coordinate.x,
		"y": context.state.party.coordinate.y,
		"textBytes": text.to_utf8_buffer().size(),
		"source": "classic",
	})])


static func _current_location_note_darkness(context: SessionWorkflowContext, map: MapDefinition) -> int:
	if map == null or map.level_type == &"dungeon" or not context.state.world.map_is_dark(map):
		return 0
	return clampi(int(context.state.party.conditions.value(0) / 30) + 1, 1, 255)
