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


static func toggle_camp(context: SessionWorkflowContext) -> ClockTransitionResult:
	if context.state.combat != null and not context.state.combat.completed:
		return ClockTransitionResult.failed(&"camp_during_battle", "The party cannot camp during battle.")
	if not context.state.camping_allowed and not context.state.party_camping:
		return ClockTransitionResult.failed(&"camping_disabled", "Camping is not allowed at this location.")
	context.state.party_camping = not context.state.party_camping
	var events: Array[DomainEvent] = [DomainEvent.new(&"camp_mode_changed", {"camping": context.state.party_camping, "source": "classic"})]
	if context.state.party_camping:
		context.state.clear_location_services()
	var map := context.content.world.map_by_id(context.state.party.map_id)
	if map == null:
		return ClockTransitionResult.failed(&"unknown_map", "The current map is unavailable for Camp.", events)
	var previous_day := context.state.clock.day()
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 5 if context.state.party_camping else 2, classic_time_scale(map), true))
	var crossed_midnight := context.state.clock.day() != previous_day
	return ClockTransitionResult.completed(map, events, context.state.party_camping, context.state.clock.day() if crossed_midnight else 0)


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
	events.append_array(context.rules.clock.advance_classic_field_time(context.state, context.content, 5, classic_time_scale(map), true))
	events.append(DomainEvent.new(&"party_rested", {"timeclicks": 5, "mapId": map.id, "source": "classic"}))
	return ClockTransitionResult.completed(map, events, true, context.state.clock.day() if context.state.clock.day() != previous_day else 0)


static func search(context: SessionWorkflowContext) -> SessionWorkflowResult:
	if context.state.party_camping:
		return SessionWorkflowResult.failed(&"search_while_camped", "Search is replaced by scroll scribing while camped.")
	context.state.mark_searched(context.state.party.map_id, context.state.party.coordinate)
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return SessionWorkflowResult.failed(&"unknown_map", "The current map is unavailable for Search.")
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
	events.append_array(context.rules.clock.advance_minutes(context.state, context.content, 1))
	for secret_id: String in discovered:
		events.append(DomainEvent.new(&"secret_discovered", {"secretId": secret_id}))
	return SessionWorkflowResult.completed(events)


static func classic_time_scale(map: MapDefinition) -> int:
	return 1 if map != null and map.level_type == &"dungeon" else 5


static func selected_placed_trigger_ids(content: RealmzContent, cell: MapCell) -> Array[String]:
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
