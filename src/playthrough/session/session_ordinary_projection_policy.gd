## Recognizes the exact event sequences eligible for incremental detached projection.
class_name SessionOrdinaryProjectionPolicy
extends RefCounted

enum EventKind {
	INVALID,
	PASSIVE,
	MOVEMENT,
	HEADING,
	STATIONARY,
}


static func can_reuse(previous: GameView, context: SessionWorkflowContext, pending_interaction: InteractionRequest, events: Array[DomainEvent]) -> bool:
	if previous == null or pending_interaction != null or previous.pending_interaction != null or previous.combat_view != null or events.is_empty():
		return false
	if previous.party_map_id != context.state.party.map_id:
		return false
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return false
	var moved_count := 0
	var heading_change_count := 0
	var stationary_count := 0
	for event: DomainEvent in events:
		match _event_kind(previous, context, current_map, event):
			EventKind.MOVEMENT:
				moved_count += 1
			EventKind.HEADING:
				heading_change_count += 1
				if heading_change_count > 1:
					return false
			EventKind.INVALID:
				return false
			EventKind.STATIONARY:
				stationary_count += 1
	return moved_count == 1 or moved_count == 0 and (heading_change_count == 1 or stationary_count == 1) and previous.party_coordinate == context.state.party.coordinate


static func _event_kind(previous: GameView, context: SessionWorkflowContext, current_map: MapDefinition, event: DomainEvent) -> EventKind:
	match event.kind:
		&"party_moved", &"debug_party_noclip_moved":
			return EventKind.MOVEMENT if _movement_event_is_valid(previous, context, event) else EventKind.INVALID
		&"dungeon_heading_changed":
			return EventKind.HEADING if _heading_event_is_valid(context, current_map, event) else EventKind.INVALID
		&"time_advanced":
			return EventKind.PASSIVE
		&"movement_blocked":
			return EventKind.STATIONARY
		&"search_mode_changed":
			return EventKind.STATIONARY if _text(event.payload, "source") == "classic" and _flag(event.payload, "searching", false) == context.state.party.conditions.is_active(ConditionRules.PARTY_SEARCHING) else EventKind.INVALID
		&"sound_requested":
			return EventKind.PASSIVE if _text(event.payload, "source") in ["classic-map-movement", "classic-search-mode", "classic-boat-collision"] and not _flag(event.payload, "waitForCompletion", true) and not event.payload.has("stopExisting") else EventKind.INVALID
		&"fatigue_changed":
			return EventKind.PASSIVE if _text(event.payload, "source") == "classic" and _text(event.payload, "reason") == "hour-boundary" and _number(event.payload, "current", -1) == context.state.party.fatigue else EventKind.INVALID
		&"spell_points_recovered", &"health_recovered":
			return _character_recovery_event_kind(context, event)
		&"ally_spell_points_recovered", &"ally_health_recovered":
			return _ally_recovery_event_kind(context, event)
		&"condition_expired", &"condition_healed", &"condition_damaged":
			return _character_condition_event_kind(context, event)
		&"party_condition_expired":
			var condition := _number(event.payload, "condition", -1)
			return EventKind.PASSIVE if condition >= 0 and condition < ConditionSet.PARTY_COUNT and context.state.party.conditions.value(condition) == 0 else EventKind.INVALID
		&"ally_condition_expired":
			var ally := _ally_by_id(context.state.party, _text(event.payload, "allyId"))
			var condition := _number(event.payload, "condition", -1)
			return EventKind.PASSIVE if ally != null and condition >= 0 and condition < ConditionSet.CHARACTER_COUNT and ally.conditions.value(condition) == 0 else EventKind.INVALID
		&"rest_ration_consumed":
			var valid := _text(event.payload, "source") == "classic-half-day" and not _text(event.payload, "characterId").is_empty() and not _text(event.payload, "instanceId").is_empty()
			return EventKind.PASSIVE if valid else EventKind.INVALID
		&"random_encounter_checked", &"random_region_triggered":
			# These checks publish no mutation; a fired door or battle rejects reuse separately.
			return EventKind.PASSIVE
		&"random_door_checked":
			return EventKind.PASSIVE if not _flag(event.payload, "triggered", false) else EventKind.INVALID
		&"timed_encounter_advanced":
			return EventKind.PASSIVE if _text(event.payload, "source") == "classic-midnight" else EventKind.INVALID
		&"timed_encounter_checked":
			return EventKind.PASSIVE if not _flag(event.payload, "eligible", true) else EventKind.INVALID
		&"movement_secret_search_completed", &"search_completed":
			var coordinate := Vector2i(_number(event.payload, "x", -100000), _number(event.payload, "y", -100000))
			var valid := _text(event.payload, "mapId") == context.state.party.map_id and coordinate == context.state.party.coordinate and _array_is_empty(event.payload.get("discoveredSecrets", []))
			return (EventKind.STATIONARY if event.kind == &"search_completed" else EventKind.PASSIVE) if valid else EventKind.INVALID
		_:
			return EventKind.INVALID


static func _movement_event_is_valid(previous: GameView, context: SessionWorkflowContext, event: DomainEvent) -> bool:
	if event.payload.has("source") or _text(event.payload, "fromMapId") != previous.party_map_id or _text(event.payload, "mapId") != context.state.party.map_id:
		return false
	var origin := Vector2i(_number(event.payload, "fromX", -100000), _number(event.payload, "fromY", -100000))
	var destination := Vector2i(_number(event.payload, "x", -100000), _number(event.payload, "y", -100000))
	var delta := destination - origin
	return origin == previous.party_coordinate and destination == context.state.party.coordinate and delta != Vector2i.ZERO and absi(delta.x) <= 1 and absi(delta.y) <= 1


static func _heading_event_is_valid(context: SessionWorkflowContext, current_map: MapDefinition, event: DomainEvent) -> bool:
	if current_map.level_type != &"dungeon":
		return false
	var source := _text(event.payload, "source")
	if source == "classic":
		return _number(event.payload, "heading", 0) == context.state.dungeon_heading and _number(event.payload, "delta", 0) in [-1, 1]
	if source == "classic-overhead-movement":
		return _number(event.payload, "current", 0) == context.state.dungeon_heading
	return false


static func _character_recovery_event_kind(context: SessionWorkflowContext, event: DomainEvent) -> EventKind:
	var character := context.state.party.character_by_id(_text(event.payload, "characterId"))
	var expected_source := "classic-hour" if event.kind == &"spell_points_recovered" else "classic-half-day"
	var valid := _text(event.payload, "source") == expected_source and character != null and _number(event.payload, "amount", 0) > 0
	return EventKind.PASSIVE if valid else EventKind.INVALID


static func _ally_recovery_event_kind(context: SessionWorkflowContext, event: DomainEvent) -> EventKind:
	var ally := _ally_by_id(context.state.party, _text(event.payload, "allyId"))
	var expected_source := "classic-hour" if event.kind == &"ally_spell_points_recovered" else "classic-half-day"
	var valid := _text(event.payload, "source") == expected_source and ally != null and _number(event.payload, "amount", 0) > 0
	return EventKind.PASSIVE if valid else EventKind.INVALID


static func _character_condition_event_kind(context: SessionWorkflowContext, event: DomainEvent) -> EventKind:
	var character := context.state.party.character_by_id(_text(event.payload, "characterId"))
	var condition := _number(event.payload, "condition", -1)
	var valid := character != null and condition >= 0 and condition < ConditionSet.CHARACTER_COUNT
	if valid and event.kind == &"condition_expired":
		valid = character.conditions.value(condition) == 0
	elif valid:
		valid = _number(event.payload, "amount", 0) > 0
	return EventKind.PASSIVE if valid else EventKind.INVALID


static func _ally_by_id(party: PartyState, ally_id: String) -> MonsterState:
	for ally: MonsterState in party.allies():
		if ally.id == ally_id:
			return ally
	return null


static func _text(payload: Dictionary, key: String) -> String:
	return str(payload.get(key, ""))


static func _number(payload: Dictionary, key: String, fallback: int) -> int:
	var value: int = payload.get(key, fallback)
	return value


static func _flag(payload: Dictionary, key: String, fallback: bool) -> bool:
	var value: bool = payload.get(key, fallback)
	return value


static func _array_is_empty(value: Variant) -> bool:
	var values: Array = value
	return values.is_empty()
