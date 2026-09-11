## Owns the Classic time-advancing Camp, Rest, and field Heal workflows.

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
	var events: Array[DomainEvent] = [
		_sound_event(10001 if context.state.party_camping else 141, "classic-camp-enter" if context.state.party_camping else "classic-camp-exit"),
		DomainEvent.new(&"camp_mode_changed", {"camping": context.state.party_camping, "source": "classic"}),
	]
	if context.state.party_camping:
		context.state.location_services.clear()
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


static func classic_time_scale(map: MapDefinition) -> int:
	if map != null and map.base_scale >= 0:
		return 1 if map.base_scale != 0 else 5
	return 1 if map != null and map.level_type == &"dungeon" else 5


static func _eligible_field_healer(context: SessionWorkflowContext, character: CharacterState) -> bool:
	if character == null or character.spellcaster_type not in [1, 2] or character.current_health < 1 or character.spell_points < 10 or context.state.character_spellcasting_blocked:
		return false
	for condition_index: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if character.conditions.is_active(condition_index):
			return false
	for spell_id: String in character.known_spells():
		var spell := context.content.magic.spell_by_id(spell_id)
		if spell != null and absi(spell.special) == 57:
			return true
	return false


static func _sound_event(sound_id: int, source: String) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": false, "source": source})
