class_name SessionResponsesCoordinator
extends RefCounted

var _session_ref: WeakRef


func _init(session: RefCounted) -> void:
	_session_ref = weakref(session)


func _session() -> RefCounted:
	return _session_ref.get_ref() if _session_ref != null else null


static func _single_event(event: DomainEvent) -> Array[DomainEvent]:
	return [event]


static func _no_events() -> Array[DomainEvent]:
	return []

func _respond_session_interaction(response: InteractionResponse) -> SessionStep:
	match _session()._session_continuation.kind:
		&"pooled-wealth-departure":
			return _respond_pooled_wealth_departure(response)
		&"service-interaction":
			return _respond_runtime_service(response)
		&"drop-item-confirmation":
			return _respond_drop_item(response)
		&"item-use-target-selection":
			return _respond_item_use_target(response)
		&"field-spell-target-selection":
			return _respond_field_spell_target(response)
		&"scroll-target-selection":
			return _respond_scroll_target(response)
		&"character-spell-confirmation":
			return _respond_character_spell_confirmation(response)
		&"character-vault-publication":
			return _respond_character_vault_publication(response)
		&"age-updates":
			return _respond_session_age_update(response)
		&"combat-ally-selection":
			return _respond_session_ally_selection(response)
		&"combat-fumble-recovery":
			return _respond_session_fumble_recovery(response)
		&"combat-reward":
			return _respond_session_battle_reward(response)
		&"combat-retreat-confirmation":
			return _respond_session_retreat(response)
	var surprise_body = response.body as InteractionResponse.YesNoBody
	if response.kind != &"yes_no" or surprise_body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "The random encounter response must be a yes/no choice.")
	var exploration = _session()._session_continuation.exploration()
	if exploration == null or exploration.random_battle_stage != &"surprise-choice":
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The random encounter choice has no matching continuation.")
	var map = _session()._content.world.map_by_id(exploration.map_id)
	var region_id = exploration.active_random_region_id
	var region: RandomEncounterRegion = null if map == null else map.random_region_by_id(region_id)
	if region == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The random encounter choice references unavailable content.")
	_session()._session_interaction = null
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	var events: Array[DomainEvent] = [DomainEvent.new(&"random_surprise_chosen", {"regionId": region.id, "accepted": surprise_body.accepted})]
	if surprise_body.accepted:
		return _session()._start_random_battle(region, 1, events)
	exploration.random_region_index -= 1
	if region.only:
		if _session()._session_continuation.kind == &"post-clock":
			return _session()._complete_post_time(events)
		_session()._session_continuation.clear()
		return _session()._finish_completed(events)
	var next_step = _session()._continue_random_regions(map, events)
	if next_step != null:
		return next_step
	if _session()._session_continuation.kind == &"post-clock":
		return _session()._complete_post_time(events)
	_session()._session_continuation.clear()
	return _session()._finish_completed(events)


func _respond_pooled_wealth_departure(response: InteractionResponse) -> SessionStep:
	var service = _session()._session_continuation.service()
	if service == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The pooled-wealth departure continuation is unavailable.")
	var stage = service.stage
	var direction = service.direction
	if stage == &"warning":
		var warning_body = response.body as InteractionResponse.YesNoBody
		if response.kind != InteractionRequest.YES_NO or warning_body == null:
			return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Pooled-wealth departure requires a yes/no response.")
		if warning_body.accepted:
			service.stage = &"distribution"
			_session()._session_interaction = _pooled_wealth_departure_distribution_request("pooled-wealth-departure:%d" % (_session()._view_revision + 1))
			var opened_events: Array[DomainEvent] = [
				DomainEvent.new(&"pooled_wealth_distribution_opened", {"wealth": _session()._state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "source": "classic-pooled-wealth-departure"}),
			]
			return _session()._finish_waiting(_session()._session_interaction, opened_events)
		var discarded = _session()._state.party.pooled_wealth.to_data()
		_session()._state.party.pooled_wealth = WealthState.new()
		_session()._session_interaction = null
		_session()._session_continuation.clear()
		return _session()._move_after_pooled_wealth(direction, _single_event(DomainEvent.new(&"pooled_wealth_left_behind", {"wealth": discarded, "movementContinues": true})))
	var body = response.body as InteractionResponse.BankBody
	if stage != &"distribution" or response.kind != InteractionRequest.POOLED_WEALTH_DEPARTURE or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Pooled-wealth distribution requires a typed money action.")
	var action = String(body.action)
	var selected_character_id = body.character_id
	if not selected_character_id.is_empty() and _session()._state.party.character_by_id(selected_character_id) == null:
		return SessionStep.failed(_session()._view_revision, &"unknown_money_target", "The selected pooled-wealth character is unavailable.")
	var events: Array[DomainEvent] = []
	if action == "leave":
		var discarded = _session()._state.party.pooled_wealth.to_data()
		_session()._state.party.pooled_wealth = WealthState.new()
		_session()._session_interaction = null
		_session()._session_continuation.clear()
		var departure_events: Array[DomainEvent] = [
			DomainEvent.new(&"pooled_wealth_left_behind", {"wealth": discarded, "movementContinues": true}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-done"}),
		]
		return _session()._move_after_pooled_wealth(direction, departure_events)
	match action:
		"pool":
			var probe = _session()._rules.economy.pool_probe(_session()._state.party)
			if not probe.allowed:
				return SessionStep.failed(_session()._view_revision, &"money_action_unavailable", probe.reason)
			_session()._rules.economy.pool_party_wealth(_session()._state.party)
			_session()._recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-pooled-wealth-departure", "wealth": _session()._state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-pool"}))
		"share":
			var probe = _session()._rules.economy.share_probe(_session()._state.party)
			if not probe.allowed:
				return SessionStep.failed(_session()._view_revision, &"money_action_unavailable", probe.reason)
			_session()._rules.economy.share_pooled_wealth(_session()._state.party)
			_session()._recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-pooled-wealth-departure", "remaining": _session()._state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-share"}))
		"to-pool", "to-character":
			if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
				return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Pooled-wealth Swap requires character, denomination, and amount.")
			var character = _session()._state.party.character_by_id(body.character_id)
			var kind = _session()._money_kind(body.denomination)
			var amount = body.amount
			if character == null or kind < 0:
				return SessionStep.failed(_session()._view_revision, &"unknown_money_target", "The selected pooled-wealth transfer is unavailable.")
			if amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
				return SessionStep.failed(_session()._view_revision, &"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character = action == "to-character"
			var probe = _session()._rules.economy.transfer_probe(_session()._state.party, character, kind as WealthState.Kind, amount, to_character)
			if not probe.allowed:
				return SessionStep.failed(_session()._view_revision, &"money_action_unavailable", probe.reason)
			var transferred = _session()._rules.economy.transfer_pool_to_character(_session()._state.party, character, kind as WealthState.Kind, amount) if to_character else _session()._rules.economy.transfer_character_to_pool(_session()._state.party, character, kind as WealthState.Kind, amount)
			if not transferred:
				return SessionStep.failed(_session()._view_revision, &"money_action_unavailable", "The selected pooled-wealth transfer is no longer available.")
			_session()._recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-pooled-wealth-departure", "characterId": character.id, "direction": action, "kind": body.denomination, "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-swap"}))
		_:
			return SessionStep.failed(_session()._view_revision, &"unknown_money_action", "Pooled-wealth action '%s' is unavailable." % action)
	_session()._session_interaction = _pooled_wealth_departure_distribution_request("pooled-wealth-departure:%d" % (_session()._view_revision + 1), selected_character_id)
	return _session()._finish_waiting(_session()._session_interaction, events)


func _pooled_wealth_departure_distribution_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	return SessionInteractionFactory.pooled_wealth_departure_distribution(_session()._state, request_id, selected_character_id)


func _respond_item_use_target(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Item use requires an ordered characterIds array.")
	var target_ids = body.character_ids.duplicate()
	var targeting = _session()._session_continuation.targeting()
	var saved_continuation = _session()._session_continuation.copy()
	var saved_interaction = _session()._session_interaction
	_session()._session_continuation.clear()
	_session()._session_interaction = null
	var completed = _session()._finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_spell_item(_session()._workflow_context(), targeting, target_ids))
	if completed.state == SessionStep.State.FAILED:
		_session()._set_continuation(saved_continuation)
		_session()._session_interaction = saved_interaction
	return completed


func _respond_field_spell_target(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Field casting requires an ordered characterIds array.")
	var target_ids = body.character_ids.duplicate()
	var targeting = _session()._session_continuation.targeting()
	var saved_continuation = _session()._session_continuation.copy()
	var saved_interaction = _session()._session_interaction
	_session()._session_continuation.clear()
	_session()._session_interaction = null
	var completed = _session()._finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_spell(_session()._workflow_context(), targeting, target_ids))
	if completed.state == SessionStep.State.FAILED:
		_session()._set_continuation(saved_continuation)
		_session()._session_interaction = saved_interaction
	return completed


func _respond_scroll_target(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Scroll use requires an ordered characterIds array.")
	var target_ids = body.character_ids.duplicate()
	var targeting = _session()._session_continuation.targeting()
	var saved_continuation = _session()._session_continuation.copy()
	var saved_interaction = _session()._session_interaction
	_session()._session_continuation.clear()
	_session()._session_interaction = null
	var completed = _session()._finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_scroll(_session()._workflow_context(), targeting, target_ids))
	if completed.state == SessionStep.State.FAILED:
		_session()._set_continuation(saved_continuation)
		_session()._session_interaction = saved_interaction
	return completed


func _begin_runtime_service(service_id: String, operation: ScenarioRuntimeOperationResult) -> SessionStep:
	if operation == null:
		return _session()._finish_failed(&"service_failed", "The selected service returned no operation result.", _no_events())
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _session()._finish_failed(operation.error_code, operation.error_message, operation.events)
	if operation.state != ScenarioRuntimeOperationResult.State.WAITING or operation.interaction == null:
		return _session()._finish_failed(&"service_failed", "The selected service did not produce its required interaction.", operation.events)
	_session()._set_continuation(SessionContinuation.service_interaction(service_id, operation.continuation))
	_session()._session_interaction = operation.interaction
	return _session()._finish_waiting(_session()._session_interaction, operation.events)


func _respond_runtime_service(response: InteractionResponse) -> SessionStep:
	var service = _session()._session_continuation.service()
	if service == null or service.runtime_continuation == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The pending service has no runtime continuation.")
	var result = _session()._runtime_api.resume_classic(service.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _session()._finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		service.runtime_continuation = result.continuation.copy()
		_session()._session_interaction = result.interaction
		return _session()._finish_waiting(_session()._session_interaction, result.events)
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	return _session()._finish_completed(result.events)


func _respond_drop_item(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Dropping an item requires a yes/no response.")
	var targeting = _session()._session_continuation.targeting()
	if targeting == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The item awaiting drop confirmation is unavailable.")
	var character_id = targeting.character_id
	var instance_id = targeting.instance_id
	var character = _session()._state.party.character_by_id(character_id)
	var instance = _session()._item_instance(character, instance_id)
	var definition: ItemDefinition = null if instance == null else _session()._content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The item awaiting drop confirmation is unavailable.")
	var probe = _session()._rules.inventory.classic_drop_probe(character, instance)
	if not probe.allowed:
		return SessionStep.failed(_session()._view_revision, &"item_cannot_drop", probe.reason)
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	if not body.accepted:
		return _session()._finish_completed(_single_event(DomainEvent.new(&"item_drop_declined", {"characterId": character.id, "instanceId": instance.id})))
	var removed = _session()._rules.inventory.remove_item(character, instance.id, definition)
	if removed == null:
		return SessionStep.failed(_session()._view_revision, &"item_drop_failed", "The item could not be removed from inventory.")
	return _session()._finish_completed(_single_event(DomainEvent.new(&"item_dropped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})))


func _respond_character_spell_confirmation(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Starting-spell confirmation requires a yes/no response.")
	var application = _session()._session_continuation.application()
	if application == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	var character_id = application.character_id
	if _session()._state.character_draft == null or _session()._state.character_draft.generated_character == null or _session()._state.character_draft.generated_character.id != character_id:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	if not body.accepted:
		return _session()._finish_completed(_single_event(DomainEvent.new(&"character_spell_confirmation_declined", {"characterId": character_id})))
	return _session()._commit_character_draft(_single_event(DomainEvent.new(&"character_spell_confirmation_accepted", {"characterId": character_id})))


func _respond_character_vault_publication(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Character-vault publication requires a yes/no response.")
	var application = _session()._session_continuation.application()
	if application == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	var character_id = application.character_id
	var character = _session()._state.party.character_by_id(character_id)
	if _session()._state.party_setup_completed or character == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	if body.accepted:
		return _session()._finish_completed(_single_event(DomainEvent.new(&"character_publication_requested", {"characterId": character_id})))
	return _session()._finish_completed(_single_event(DomainEvent.new(&"character_publication_declined", {"characterId": character_id})))


func _respond_session_retreat(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	var continuation = _session()._session_continuation.combat()
	if continuation == null or _session()._state.combat == null or _session()._state.combat.completed or _session()._state.combat.battle_id != continuation.battle_id or _session()._state.combat.active_actor_id() != continuation.actor_id:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The character awaiting Escape confirmation is unavailable.")
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	if not body.accepted:
		return _session()._finish_completed(_single_event(DomainEvent.new(&"combat_retreat_declined", {"actorId": continuation.actor_id, "mode": String(continuation.mode), "source": "classic"})))
	var result = _session()._rules.combat_flow.retreat_character(_session()._state, _session()._content, continuation.actor_id, continuation.mode, continuation.destination, _session()._rng)
	return _session()._finish_combat_result(result)


func _finish_with_age_updates(events: Array[DomainEvent], resume_kind: StringName, resume_continuation: SessionContinuation = null) -> SessionStep:
	var updates = CharacterAgingResult.update_bodies(events)
	if updates.is_empty():
		if resume_kind == &"post-move":
			_session()._set_continuation(resume_continuation.copy())
			return _session()._continue_post_move(events)
		if resume_kind == &"post-clock":
			_session()._set_continuation(resume_continuation.copy())
			return _session()._continue_post_time(events)
		if resume_kind == &"combat-monster-turns":
			return _continue_after_session_combat_age_update(events)
		return _session()._finish_completed(events)
	var age = SessionContinuation.AgeBody.new()
	for update: InteractionRequest.AgeUpdateBody in updates:
		age.updates.append(InteractionRequest.age_update_body("session.age-copy", update).body as InteractionRequest.AgeUpdateBody)
	age.index = 1
	age.resume_kind = resume_kind
	age.resume_continuation = null if resume_continuation == null else resume_continuation.copy()
	_session()._set_continuation(SessionContinuation.age_updates(age))
	_session()._session_interaction = InteractionRequest.age_update_body(_session_age_update_request_id(updates[0], 0), updates[0])
	events.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return _session()._finish_waiting(_session()._session_interaction, events)


func _respond_session_age_update(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var age = _session()._session_continuation.age()
	if age == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The age-update queue is unavailable.")
	var updates = age.updates
	var index = age.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The age-update queue is unavailable.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		age.index = index + 1
		_session()._session_interaction = InteractionRequest.age_update_body(_session_age_update_request_id(next_payload, index), next_payload)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return _session()._finish_waiting(_session()._session_interaction, events)
	var resume_kind = age.resume_kind
	var resume_continuation = age.resume_continuation
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	if resume_kind == &"post-move":
		_session()._set_continuation(resume_continuation.copy())
		return _session()._continue_post_move(events)
	if resume_kind == &"post-clock":
		_session()._set_continuation(resume_continuation.copy())
		return _session()._continue_post_time(events)
	if resume_kind == &"combat-monster-turns":
		return _continue_after_session_combat_age_update(events)
	if resume_kind == &"completed":
		return _session()._finish_completed(events)
	return _session()._finish_failed(&"invalid_session_continuation", "The age-update queue has no valid completion path.", events)


func _continue_after_session_combat_age_update(events: Array[DomainEvent]) -> SessionStep:
	var continued = _session()._rules.combat_flow.continue_after_age_update(_session()._state, _session()._content, _session()._rng)
	if not continued.ok:
		return _session()._finish_failed(continued.error_code, continued.error_message, events)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _finish_with_age_updates(events, "combat-monster-turns")
	if not _session()._event_payload(continued.events, &"monster_death_macro_requested").is_empty():
		return _session()._start_session_death_macro(events)
	if continued.completed:
		return _session()._finish_direct_battle(events)
	return _session()._finish_completed(events)


func _session_age_update_request_id(update: InteractionRequest.AgeUpdateBody, index: int) -> String:
	return "session.age-update:%s:%d:%d" % [update.character_id, _session()._view_revision + 1, index]


func _respond_session_ally_selection(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.AllySelectionBody
	if response.kind != &"ally_selection" or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Ally selection requires selectedIds.")
	var continuation = _session()._session_continuation.combat()
	if continuation == null or _session()._state.combat == null or not _session()._state.combat.completed or _session()._state.combat.battle_id != continuation.battle_id:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The completed battle is unavailable for ally selection.")
	# Development saves from before the Castle body-count correction can retain an
	# impossible empty selection boundary. Re-evaluate the source-backed candidate
	# set and advance it exactly as a fresh terminal battle now does.
	if _session()._rules.combat_flow.ally_selection_payload(_session()._state, _session()._content).is_empty():
		_session()._session_interaction = null
		_session()._session_continuation.clear()
		return _session()._finish_direct_battle_recovery(_no_events())
	var result = _session()._rules.combat_flow.apply_ally_selection(_session()._state, _session()._content, body.selected_ids)
	if not result.ok:
		return SessionStep.failed(_session()._view_revision, result.error_code, result.error_message)
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _session()._finish_direct_battle_recovery(events)


func _respond_session_fumble_recovery(response: InteractionResponse) -> SessionStep:
	var body = response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	var continuation = _session()._session_continuation.combat()
	if continuation == null or _session()._state.combat == null or not _session()._state.combat.completed or _session()._state.combat.battle_id != continuation.battle_id:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var result = _session()._rules.combat_flow.apply_fumble_recovery(_session()._state, _session()._content, body.action, body.instance_id, body.character_id)
	if not result.ok:
		return SessionStep.failed(_session()._view_revision, result.error_code, result.error_message)
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _session()._finish_direct_battle_recovery(events)


func _respond_session_battle_reward(response: InteractionResponse) -> SessionStep:
	var continuation = _session()._session_continuation.reward()
	if continuation == null or _session()._state.combat == null or not _session()._state.combat.completed or _session()._state.combat.battle_id != continuation.battle_id:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The completed battle is unavailable for reward distribution.")
	if continuation.runtime_continuation == null:
		return SessionStep.failed(_session()._view_revision, &"invalid_session_continuation", "The battle reward continuation is unavailable.")
	var return_continuation = _session()._battle_return_continuation.copy()
	var battle_outcome = _session()._state.combat.outcome
	var result = _session()._runtime_api.resume_classic(continuation.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _session()._finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		continuation.runtime_continuation = result.continuation.copy()
		_session()._session_interaction = result.interaction
		return _session()._finish_waiting(_session()._session_interaction, result.events)
	_session()._session_interaction = null
	_session()._session_continuation.clear()
	return _session()._finish_after_direct_battle(result.events, return_continuation, battle_outcome)
