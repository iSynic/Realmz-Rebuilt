## Owns persistent Search mode and the two Classic exploration secret-search sequences.

class_name ExplorationSearchWorkflow
extends RefCounted


static func search(context: SessionWorkflowContext) -> ExplorationTimeWorkflow.ClockTransitionResult:
	if context.state.party_camping:
		return ExplorationTimeWorkflow.ClockTransitionResult.failed(&"search_while_camped", "Search is replaced by scroll scribing while camped.")
	if context.state.party.fatigue > 134:
		return ExplorationTimeWorkflow.ClockTransitionResult.failed(&"area_search_exhausted", "The party is too fatigued to continue Area Search.")
	context.state.scenario_progress.mark_searched(context.state.party.map_id, context.state.party.coordinate)
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return ExplorationTimeWorkflow.ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Area Search.")
	var discovered: Array[String] = []
	var first_roll: int = 0
	for y: int in range(context.state.party.coordinate.y - 1, context.state.party.coordinate.y + 2):
		for x: int in range(context.state.party.coordinate.x - 1, context.state.party.coordinate.x + 2):
			var cell := current_map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			for feature: MapFeature in cell.features():
				if feature.kind != &"secret" or context.state.world.topology.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
					continue
				var roll := context.rng.draw(100, StringName("exploration.search.%s" % feature.id))
				if first_roll == 0:
					first_roll = roll
				if roll <= 100:
					context.state.world.topology.discover_secret(feature.id)
					discovered.append(feature.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"search_completed", {"mapId": context.state.party.map_id, "x": context.state.party.coordinate.x, "y": context.state.party.coordinate.y, "roll": first_roll, "discoveredSecrets": discovered})]
	for secret_id: String in discovered:
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": secret_id}))
	var previous_day := context.state.clock.day()
	# Castle's held Area Search first calls checkforsecret(TRUE), which advances
	# four field timeclicks. Its separate outer timeclick and random check resume
	# only after this phase's timed/random continuation has settled.
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 4, ExplorationTimeWorkflow.classic_time_scale(current_map), true))
	return ExplorationTimeWorkflow.ClockTransitionResult.completed(current_map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func search_after_land_movement_attempt(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> ExplorationTimeWorkflow.ClockTransitionResult:
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return ExplorationTimeWorkflow.ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for the post-movement secret check.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	if current_map.level_type != &"land":
		return ExplorationTimeWorkflow.ClockTransitionResult.completed(current_map, events, false, 0)
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
				if feature.kind != &"secret" or context.state.world.topology.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
					continue
				var roll := context.rng.draw(100, StringName("exploration.movement-search.%s" % feature.id))
				if first_roll == 0:
					first_roll = roll
				if roll <= chance:
					context.state.world.topology.discover_secret(feature.id)
					discovered.append(feature.id)
	events.append(DomainEvent.new(&"movement_secret_search_completed", {"mapId": current_map.id, "x": context.state.party.coordinate.x, "y": context.state.party.coordinate.y, "roll": first_roll, "chance": chance, "discoveredSecrets": discovered}))
	for secret_id: String in discovered:
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": secret_id, "byMovementAttempt": true}))
	var previous_day := context.state.clock.day()
	if searching:
		events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 4, ExplorationTimeWorkflow.classic_time_scale(current_map), true))
	return ExplorationTimeWorkflow.ClockTransitionResult.completed(current_map, events, searching, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func complete_area_search(context: SessionWorkflowContext, preceding_events: Array[DomainEvent]) -> ExplorationTimeWorkflow.ClockTransitionResult:
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return ExplorationTimeWorkflow.ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Area Search.", preceding_events)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 1, ExplorationTimeWorkflow.classic_time_scale(current_map), true))
	return ExplorationTimeWorkflow.ClockTransitionResult.completed(current_map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func toggle_search(context: SessionWorkflowContext) -> SessionWorkflowResult:
	if context.state.party_camping:
		return SessionWorkflowResult.failed(&"search_while_camped", "Search is replaced by scroll scribing while camped.")
	if context.state.combat != null and not context.state.combat.completed:
		return SessionWorkflowResult.failed(&"search_during_battle", "Search mode is unavailable during battle.")
	var searching := not context.state.party.conditions.is_active(ConditionRules.PARTY_SEARCHING)
	context.state.party.conditions.set_value(ConditionRules.PARTY_SEARCHING, -1 if searching else 0)
	return SessionWorkflowResult.completed([
		DomainEvent.new(&"search_mode_changed", {"searching": searching, "source": "classic"}),
		DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-search-mode"}),
	])
