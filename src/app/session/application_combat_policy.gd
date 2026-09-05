## Translates combat UI responses and playback state without owning the session.
class_name ApplicationCombatPolicy
extends RefCounted


static func body_with_preferences(body: InteractionResponse.CombatBody, settings: PresentationSettings) -> InteractionResponse.CombatBody:
	var result := body.duplicate_body()
	if result.action == &"move":
		result.auto_switch_to_melee = settings != null and settings.auto_switch_to_melee
	return result


static func direct_intent(body: InteractionResponse.CombatBody) -> PlayerIntent:
	if body == null or not body.is_valid(): return null
	match body.action:
		&"set_auto":
			return CombatIntents.set_auto(body.actor_id, body.enabled)
		&"move", &"retreat_edge":
			if not body.has_destination: return null
			return CombatIntents.move(body.actor_id, body.destination, body.auto_switch_to_melee)
		&"cast_spell":
			if body.spell_id.is_empty(): return null
			if not body.target_coordinates.is_empty():
				return MagicIntents.cast_at_coordinates(body.spell_id, body.actor_id, body.target_coordinates, body.power)
			if body.has_target_coordinate:
				return MagicIntents.cast_at(body.spell_id, body.actor_id, body.target_coordinate, body.power, body.rotation)
			if not body.target_ids.is_empty():
				return MagicIntents.cast_at_targets(body.spell_id, body.actor_id, body.target_ids, body.power)
			return MagicIntents.cast(body.spell_id, body.actor_id, body.target_id, body.power)
		&"use_item":
			if body.item_instance_id.is_empty(): return null
			return InventoryIntents.use_on_target(body.item_instance_id, body.actor_id, body.target_id, body.target_ids, body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE, body.rotation, body.target_coordinates)
		&"use_scroll":
			if body.scroll_slot < 0: return null
			if not body.target_coordinates.is_empty():
				return MagicIntents.use_scroll_at_coordinates(body.actor_id, body.scroll_slot, body.target_coordinates)
			return MagicIntents.use_scroll_on_target(body.actor_id, body.scroll_slot, body.target_id, body.target_ids, body.target_coordinate if body.has_target_coordinate else CombatFlow.INVALID_COORDINATE, body.rotation)
	return CombatIntents.choose_action(body.action, body.actor_id, body.target_id)


static func auto_change_to_queue(intent: PlayerIntent, playback_active: bool) -> Dictionary:
	if not playback_active or intent == null or intent.kind != PlayerIntent.Kind.SET_COMBAT_AUTO or not intent.payload is CombatIntentPayloads.Auto: return {}
	var payload := intent.payload as CombatIntentPayloads.Auto
	return {"characterId": payload.character_id, "enabled": payload.enabled}


static func auto_abort_ids(view: GameView, queued_changes: Dictionary = {}) -> Array[String]:
	var result: Array[String] = []
	if view != null and view.combat_view != null: result.assign(view.combat_view.auto_character_ids)
	for character_id: Variant in queued_changes:
		if bool(queued_changes[character_id]) and not result.has(String(character_id)): result.append(String(character_id))
	result.sort()
	return result


static func persistent_auto_response(view: GameView) -> InteractionResponse:
	if view == null or view.combat_view == null or view.combat_view.outcome != &"active": return null
	var actor_id := view.combat_view.active_actor_id
	if actor_id.is_empty() or not view.combat_view.auto_character_ids.has(actor_id): return null
	var request := view.active_interaction_request()
	if request == null or request.kind != InteractionRequest.COMBAT: return null
	return InteractionResponse.new(request.request_id, request.kind, InteractionResponse.CombatBody.new(&"auto", actor_id))


static func should_defer_session_close(step: SessionStep, playback_active: bool) -> bool:
	return playback_active and step_ends_session(step)


static func step_ends_session(step: SessionStep) -> bool:
	if step == null: return false
	return step.events.any(func(event: DomainEvent) -> bool: return event.kind == &"session_ended")
