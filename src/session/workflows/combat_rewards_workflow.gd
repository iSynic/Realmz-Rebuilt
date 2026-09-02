class_name CombatRewardsWorkflow
extends RefCounted


static func submit_action(context: SessionWorkflowContext, payload: PlayerIntent.CombatActionPayload) -> CombatFlowResult:
	return context.rules.combat_flow.submit_action(
		context.state,
		context.content,
		payload.actor_id,
		payload.action,
		payload.target_id,
		context.rng,
	)


static func set_persistent_auto(context: SessionWorkflowContext, payload: PlayerIntent.CombatAutoPayload) -> CombatFlowResult:
	if context.state == null or context.state.combat == null or context.state.combat.completed:
		return CombatFlowResult.failed(&"combat_auto_unavailable", "Persistent Auto can be changed only during an active battle.")
	var character := context.state.party.character_by_id(payload.character_id)
	if character == null or character.current_health <= 0:
		return CombatFlowResult.failed(&"invalid_combat_auto_character", "Persistent Auto requires a living party character.")
	var state_checkpoint := context.state.to_data()
	var rng_checkpoint := context.rng.checkpoint()
	if not context.state.set_combat_auto(payload.character_id, payload.enabled):
		return CombatFlowResult.failed(&"invalid_combat_auto_character", "Persistent Auto could not be changed for this character.")
	var toggle_sound := 147 if payload.enabled else 139
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"sound_requested", {"soundId": toggle_sound, "waitForCompletion": false, "source": "classic-combat-auto-toggle"}),
		DomainEvent.new(&"combat_auto_changed", {"characterId": payload.character_id, "enabled": payload.enabled, "source": "classic"}),
	]
	if payload.enabled and context.state.combat.active_actor_id() == payload.character_id:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
		var automatic := context.rules.combat_flow.run_persistent_auto_characters(context.state, context.content, context.rng)
		if not automatic.ok:
			if not context.state.restore_from_data(state_checkpoint) or not context.rng.rollback(rng_checkpoint):
				return CombatFlowResult.failed(&"combat_auto_rollback_failed", "Persistent Auto failed and could not restore its toggle transaction.")
			return CombatFlowResult.failed(automatic.error_code, automatic.error_message)
		events.append_array(automatic.events)
		return CombatFlowResult.succeeded(events, automatic.completed)
	return CombatFlowResult.succeeded(events)


static func move_character(context: SessionWorkflowContext, payload: PlayerIntent.CombatMovePayload, forced_retreat: bool) -> CombatFlowResult:
	if forced_retreat:
		return context.rules.combat_flow.retreat_character(
			context.state,
			context.content,
			payload.actor_id,
			&"edge",
			payload.destination,
			context.rng,
		)
	return context.rules.combat_flow.move_character(
		context.state,
		context.content,
		payload.actor_id,
		payload.destination,
		context.rng,
		payload.auto_switch_to_melee,
	)
