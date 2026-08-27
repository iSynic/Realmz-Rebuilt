class_name SessionResponsesCoordinator
extends RefCounted

var _context: SessionCoordinatorContext


func _init(context: SessionCoordinatorContext) -> void:
	_context = context


static func _single_event(event: DomainEvent) -> Array[DomainEvent]:
	return [event]


static func _no_events() -> Array[DomainEvent]:
	return []

func _respond_session_interaction(response: InteractionResponse) -> SessionCoordinatorResult:
	match _context.session_continuation.kind:
		&"boat-choice":
			return _respond_boat_choice(response)
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
		&"scroll-discard-confirmation":
			return _respond_scroll_discard(response)
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
		&"combat-friendly-collision":
			return _respond_session_friendly_collision(response)
	var surprise_body = response.body as InteractionResponse.YesNoBody
	if response.kind != &"yes_no" or surprise_body == null:
		return _context.failed(&"invalid_interaction_response", "The random encounter response must be a yes/no choice.")
	var exploration = _context.session_continuation.exploration()
	if exploration == null or exploration.random_battle_stage != &"surprise-choice":
		return _context.failed(&"invalid_session_continuation", "The random encounter choice has no matching continuation.")
	var map = _context.content.world.map_by_id(exploration.map_id)
	var region_id = exploration.active_random_region_id
	var region: RandomEncounterRegion = null if map == null else map.random_region_by_id(region_id)
	if region == null:
		return _context.failed(&"invalid_session_continuation", "The random encounter choice references unavailable content.")
	_context.session_interaction = null
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	var events: Array[DomainEvent] = [DomainEvent.new(&"random_surprise_chosen", {"regionId": region.id, "accepted": surprise_body.accepted})]
	if surprise_body.accepted:
		return _context.exploration()._start_random_battle(region, 1, events)
	exploration.random_region_index -= 1
	if region.only:
		if _context.session_continuation.kind == &"post-clock":
			return _context.exploration()._complete_post_time(events)
		_context.session_continuation.clear()
		return _context.completed(events)
	var next_step = _context.exploration()._continue_random_regions(map, events)
	if next_step != null:
		return next_step
	if _context.session_continuation.kind == &"post-clock":
		return _context.exploration()._complete_post_time(events)
	_context.session_continuation.clear()
	return _context.completed(events)


func _respond_boat_choice(response: InteractionResponse) -> SessionCoordinatorResult:
	var choice := _context.session_continuation.boat()
	var answer := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or answer == null or choice == null:
		return _context.failed(&"invalid_interaction_response", "The Classic boat movement choice requires a yes/no response.")
	if _context.state.party.map_id != choice.source_map_id or _context.state.party.coordinate != choice.source_coordinate:
		return _context.failed(&"invalid_session_continuation", "The party moved before the Classic boat choice resumed.")
	var movement := _context.content.world.probe_movement(choice.source_map_id, choice.source_coordinate, choice.direction, _context.state.world, _context.state.party_in_boat)
	if movement.target_map == null or movement.target_map.id != choice.target_map_id or movement.target_coordinate != choice.target_coordinate:
		return _context.failed(&"invalid_session_continuation", "The Classic boat choice destination is no longer available.")
	if choice.action == &"board" and (_context.state.party_in_boat or movement.reason != &"board_boat"):
		return _context.failed(&"invalid_session_continuation", "The boardable boat is no longer available.")
	if choice.action == &"disembark" and (not _context.state.party_in_boat or movement.reason != &"boat_shore"):
		return _context.failed(&"invalid_session_continuation", "The shore is no longer available for disembarking.")
	_context.session_interaction = null
	_context.session_continuation.clear()
	var events: Array[DomainEvent] = [DomainEvent.new(&"boat_choice_resolved", {"action": String(choice.action), "accepted": answer.accepted})]
	if choice.action == &"board" and answer.accepted:
		var boarded_movement := WorldMovementResult.permitted(movement.source_map, movement.target_map, movement.target_coordinate, movement.transition, TopologyMoveResult.permitted(movement.topology_result.target_cell))
		_context.state.world.set_boat_present(choice.target_map_id, choice.target_coordinate, false)
		_context.state.party_in_boat = true
		events.append(DomainEvent.new(&"boat_boarded", {"mapId": choice.target_map_id, "x": choice.target_coordinate.x, "y": choice.target_coordinate.y}))
		return _context.exploration()._finish_exploration_movement(ExplorationTimeWorkflow.commit_permitted_move(_context.workflow_context(), boarded_movement, choice.direction, events))
	if choice.action == &"disembark" and answer.accepted:
		_context.state.world.set_boat_present(choice.source_map_id, choice.source_coordinate, true)
		_context.state.party_in_boat = false
		events.append(DomainEvent.new(&"boat_disembarked", {"mapId": choice.source_map_id, "x": choice.source_coordinate.x, "y": choice.source_coordinate.y}))
	return _context.exploration()._finish_exploration_movement(ExplorationTimeWorkflow.commit_blocked_attempt(_context.workflow_context(), movement, events, false))


func _respond_pooled_wealth_departure(response: InteractionResponse) -> SessionCoordinatorResult:
	var service = _context.session_continuation.service()
	if service == null:
		return _context.failed(&"invalid_session_continuation", "The pooled-wealth departure continuation is unavailable.")
	var stage = service.stage
	var direction = service.direction
	if stage == &"warning":
		var warning_body = response.body as InteractionResponse.YesNoBody
		if response.kind != InteractionRequest.YES_NO or warning_body == null:
			return _context.failed(&"invalid_interaction_response", "Pooled-wealth departure requires a yes/no response.")
		if warning_body.accepted:
			service.stage = &"distribution"
			_context.session_interaction = _pooled_wealth_departure_distribution_request("pooled-wealth-departure:%d" % _context.next_revision())
			var opened_events: Array[DomainEvent] = [
				DomainEvent.new(&"pooled_wealth_distribution_opened", {"wealth": _context.state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "reducedSoundEligible": true, "source": "classic-pooled-wealth-departure"}),
			]
			return _context.waiting(_context.session_interaction, opened_events)
		var discarded = _context.state.party.pooled_wealth.to_data()
		_context.state.party.pooled_wealth = WealthState.new()
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.exploration()._move_after_pooled_wealth(direction, _single_event(DomainEvent.new(&"pooled_wealth_left_behind", {"wealth": discarded, "movementContinues": true})))
	var body = response.body as InteractionResponse.BankBody
	if stage != &"distribution" or response.kind != InteractionRequest.POOLED_WEALTH_DEPARTURE or body == null:
		return _context.failed(&"invalid_interaction_response", "Pooled-wealth distribution requires a typed money action.")
	var action = String(body.action)
	var selected_character_id = body.character_id
	if not selected_character_id.is_empty() and _context.state.party.character_by_id(selected_character_id) == null:
		return _context.failed(&"unknown_money_target", "The selected pooled-wealth character is unavailable.")
	var events: Array[DomainEvent] = []
	if action == "leave":
		var discarded = _context.state.party.pooled_wealth.to_data()
		_context.state.party.pooled_wealth = WealthState.new()
		_context.session_interaction = null
		_context.session_continuation.clear()
		var departure_events: Array[DomainEvent] = [
			DomainEvent.new(&"pooled_wealth_left_behind", {"wealth": discarded, "movementContinues": true}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-done"}),
		]
		return _context.exploration()._move_after_pooled_wealth(direction, departure_events)
	match action:
		"pool":
			var probe = _context.rules.economy.pool_probe(_context.state.party)
			if not probe.allowed:
				return _context.failed(&"money_action_unavailable", probe.reason)
			_context.rules.economy.pool_party_wealth(_context.state.party)
			_context.recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-pooled-wealth-departure", "wealth": _context.state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-pool"}))
		"share":
			var probe = _context.rules.economy.share_probe(_context.state.party)
			if not probe.allowed:
				return _context.failed(&"money_action_unavailable", probe.reason)
			_context.rules.economy.share_pooled_wealth(_context.state.party)
			_context.recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-pooled-wealth-departure", "remaining": _context.state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-share"}))
		"to-pool", "to-character":
			if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
				return _context.failed(&"invalid_interaction_response", "Pooled-wealth Swap requires character, denomination, and amount.")
			var character = _context.state.party.character_by_id(body.character_id)
			var kind = _context.money_kind(body.denomination)
			var amount = body.amount
			if character == null or kind < 0:
				return _context.failed(&"unknown_money_target", "The selected pooled-wealth transfer is unavailable.")
			if amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
				return _context.failed(&"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character = action == "to-character"
			var probe = _context.rules.economy.transfer_probe(_context.state.party, character, kind as WealthState.Kind, amount, to_character)
			if not probe.allowed:
				return _context.failed(&"money_action_unavailable", probe.reason)
			var transferred = _context.rules.economy.transfer_pool_to_character(_context.state.party, character, kind as WealthState.Kind, amount) if to_character else _context.rules.economy.transfer_character_to_pool(_context.state.party, character, kind as WealthState.Kind, amount)
			if not transferred:
				return _context.failed(&"money_action_unavailable", "The selected pooled-wealth transfer is no longer available.")
			_context.recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-pooled-wealth-departure", "characterId": character.id, "direction": action, "kind": body.denomination, "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-swap"}))
		_:
			return _context.failed(&"unknown_money_action", "Pooled-wealth action '%s' is unavailable." % action)
	_context.session_interaction = _pooled_wealth_departure_distribution_request("pooled-wealth-departure:%d" % _context.next_revision(), selected_character_id)
	return _context.waiting(_context.session_interaction, events)


func _pooled_wealth_departure_distribution_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	return SessionInteractionFactory.pooled_wealth_departure_distribution(_context.state, request_id, selected_character_id)


func _respond_item_use_target(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return _context.failed(&"invalid_interaction_response", "Item use requires an ordered characterIds array.")
	var target_ids = body.character_ids.duplicate()
	var targeting = _context.session_continuation.targeting()
	var saved_continuation = _context.session_continuation.copy()
	var saved_interaction = _context.session_interaction
	_context.session_continuation.clear()
	_context.session_interaction = null
	var completed = _finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_spell_item(_context.workflow_context(), targeting, target_ids))
	if completed.state == SessionCoordinatorResult.State.FAILED:
		_context.set_continuation(saved_continuation)
		_context.session_interaction = saved_interaction
	return completed


func _respond_field_spell_target(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return _context.failed(&"invalid_interaction_response", "Field casting requires an ordered characterIds array.")
	var target_ids = body.character_ids.duplicate()
	var targeting = _context.session_continuation.targeting()
	var saved_continuation = _context.session_continuation.copy()
	var saved_interaction = _context.session_interaction
	_context.session_continuation.clear()
	_context.session_interaction = null
	var completed = _finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_spell(_context.workflow_context(), targeting, target_ids))
	if completed.state == SessionCoordinatorResult.State.FAILED:
		_context.set_continuation(saved_continuation)
		_context.session_interaction = saved_interaction
	return completed


func _respond_scroll_target(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return _context.failed(&"invalid_interaction_response", "Scroll use requires an ordered characterIds array.")
	var target_ids = body.character_ids.duplicate()
	var targeting = _context.session_continuation.targeting()
	var saved_continuation = _context.session_continuation.copy()
	var saved_interaction = _context.session_interaction
	_context.session_continuation.clear()
	_context.session_interaction = null
	var completed = _finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_scroll(_context.workflow_context(), targeting, target_ids))
	if completed.state == SessionCoordinatorResult.State.FAILED:
		_context.set_continuation(saved_continuation)
		_context.session_interaction = saved_interaction
	return completed


func _respond_scroll_discard(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return _context.failed(&"invalid_interaction_response", "Discarding a scroll requires a yes/no response.")
	var targeting = _context.session_continuation.targeting()
	var result := InventoryMagicServicesWorkflow.discard_field_scroll(_context.workflow_context(), targeting, body.accepted)
	if not result.ok:
		return _context.failed(result.error_code, result.error_message, result.events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	return _context.completed(result.events)


func _begin_runtime_service(service_id: String, operation: ScenarioRuntimeOperationResult) -> SessionCoordinatorResult:
	if operation == null:
		return _context.failed(&"service_failed", "The selected service returned no operation result.", _no_events())
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _context.failed(operation.error_code, operation.error_message, operation.events)
	if operation.state != ScenarioRuntimeOperationResult.State.WAITING or operation.interaction == null:
		return _context.failed(&"service_failed", "The selected service did not produce its required interaction.", operation.events)
	_context.set_continuation(SessionContinuation.service_interaction(service_id, operation.continuation))
	_context.session_interaction = operation.interaction
	return _context.waiting(_context.session_interaction, operation.events)


func _respond_runtime_service(response: InteractionResponse) -> SessionCoordinatorResult:
	var service = _context.session_continuation.service()
	if service == null or service.runtime_continuation == null:
		return _context.failed(&"invalid_session_continuation", "The pending service has no runtime continuation.")
	var result = _context.runtime_api.resume_classic(service.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _context.failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		service.runtime_continuation = result.continuation.copy()
		_context.session_interaction = result.interaction
		return _context.waiting(_context.session_interaction, result.events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	return _context.completed(result.events)


func _respond_drop_item(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return _context.failed(&"invalid_interaction_response", "Dropping an item requires a yes/no response.")
	var targeting = _context.session_continuation.targeting()
	if targeting == null:
		return _context.failed(&"invalid_session_continuation", "The item awaiting drop confirmation is unavailable.")
	var character_id = targeting.character_id
	var instance_id = targeting.instance_id
	var character = _context.state.party.character_by_id(character_id)
	var instance = _context.item_instance(character, instance_id)
	var definition: ItemDefinition = null if instance == null else _context.content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return _context.failed(&"invalid_session_continuation", "The item awaiting drop confirmation is unavailable.")
	var probe = _context.rules.inventory.classic_drop_probe(character, instance)
	if not probe.allowed:
		return _context.failed(&"item_cannot_drop", probe.reason)
	_context.session_interaction = null
	_context.session_continuation.clear()
	if not body.accepted:
		return _context.completed(_single_event(DomainEvent.new(&"item_drop_declined", {"characterId": character.id, "instanceId": instance.id})))
	var removed = _context.rules.inventory.remove_item(character, instance.id, definition)
	if removed == null:
		return _context.failed(&"item_drop_failed", "The item could not be removed from inventory.")
	return _context.completed(_single_event(DomainEvent.new(&"item_dropped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})))


func _respond_character_spell_confirmation(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return _context.failed(&"invalid_interaction_response", "Starting-spell confirmation requires a yes/no response.")
	var application = _context.session_continuation.application()
	if application == null:
		return _context.failed(&"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	var character_id = application.character_id
	if _context.state.character_draft == null or _context.state.character_draft.generated_character == null or _context.state.character_draft.generated_character.id != character_id:
		return _context.failed(&"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	_context.session_interaction = null
	_context.session_continuation.clear()
	if not body.accepted:
		return _context.completed(_single_event(DomainEvent.new(&"character_spell_confirmation_declined", {"characterId": character_id})))
	return _commit_character_draft(_single_event(DomainEvent.new(&"character_spell_confirmation_accepted", {"characterId": character_id})))


func _respond_character_vault_publication(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return _context.failed(&"invalid_interaction_response", "Character-vault publication requires a yes/no response.")
	var application = _context.session_continuation.application()
	if application == null:
		return _context.failed(&"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	var character_id = application.character_id
	var character = _context.state.party.character_by_id(character_id)
	if _context.state.party_setup_completed or character == null:
		return _context.failed(&"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	_context.session_interaction = null
	_context.session_continuation.clear()
	if body.accepted:
		return _context.completed(_single_event(DomainEvent.new(&"character_publication_requested", {"characterId": character_id})))
	return _context.completed(_single_event(DomainEvent.new(&"character_publication_declined", {"characterId": character_id})))


func _respond_session_retreat(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return _context.failed(&"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	var continuation = _context.session_continuation.combat()
	if continuation == null or _context.state.combat == null or _context.state.combat.completed or _context.state.combat.battle_id != continuation.battle_id or _context.state.combat.active_actor_id() != continuation.actor_id:
		return _context.failed(&"invalid_session_continuation", "The character awaiting Escape confirmation is unavailable.")
	_context.session_interaction = null
	_context.session_continuation.clear()
	if not body.accepted:
		return _context.completed(_single_event(DomainEvent.new(&"combat_retreat_declined", {"actorId": continuation.actor_id, "mode": String(continuation.mode), "source": "classic"})))
	var result = _context.rules.combat_flow.retreat_character(_context.state, _context.content, continuation.actor_id, continuation.mode, continuation.destination, _context.rng)
	return _finish_combat_result(result)


func _respond_session_friendly_collision(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return _context.failed(&"invalid_interaction_response", "The Classic friendly-collision choice requires a yes/no response.")
	var continuation = _context.session_continuation.combat()
	if continuation == null or _context.state.combat == null or _context.state.combat.completed or _context.state.combat.battle_id != continuation.battle_id or _context.state.combat.active_actor_id() != continuation.actor_id or _context.rules.combat_flow.friendly_collision_target_id(_context.state, continuation.actor_id, continuation.destination).is_empty():
		return _context.failed(&"invalid_session_continuation", "The adjacent ally awaiting a collision choice is unavailable.")
	_context.session_interaction = null
	_context.session_continuation.clear()
	var action := &"swap" if body.accepted else &"attack"
	var result = _context.rules.combat_flow.move_character(_context.state, _context.content, continuation.actor_id, continuation.destination, _context.rng, false, action)
	return _finish_combat_result(result)


func _finish_with_age_updates(events: Array[DomainEvent], resume_kind: StringName, resume_continuation: SessionContinuation = null) -> SessionCoordinatorResult:
	var updates = CharacterAgingResult.update_bodies(events)
	if updates.is_empty():
		if resume_kind == &"post-move":
			_context.set_continuation(resume_continuation.copy())
			return _context.exploration()._continue_post_move(events)
		if resume_kind == &"post-clock":
			_context.set_continuation(resume_continuation.copy())
			return _context.exploration()._continue_post_time(events)
		if resume_kind == &"combat-monster-turns":
			return _continue_after_session_combat_age_update(events)
		return _context.completed(events)
	var age = SessionContinuation.AgeBody.new()
	for update: InteractionRequest.AgeUpdateBody in updates:
		age.updates.append(InteractionRequest.age_update_body("session.age-copy", update).body as InteractionRequest.AgeUpdateBody)
	age.index = 1
	age.resume_kind = resume_kind
	age.resume_continuation = null if resume_continuation == null else resume_continuation.copy()
	_context.set_continuation(SessionContinuation.age_updates(age))
	_context.session_interaction = InteractionRequest.age_update_body(_session_age_update_request_id(updates[0], 0), updates[0])
	events.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return _context.waiting(_context.session_interaction, events)


func _respond_session_age_update(response: InteractionResponse) -> SessionCoordinatorResult:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return _context.failed(&"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var age = _context.session_continuation.age()
	if age == null:
		return _context.failed(&"invalid_session_continuation", "The age-update queue is unavailable.")
	var updates = age.updates
	var index = age.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return _context.failed(&"invalid_session_continuation", "The age-update queue is unavailable.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		age.index = index + 1
		_context.session_interaction = InteractionRequest.age_update_body(_session_age_update_request_id(next_payload, index), next_payload)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return _context.waiting(_context.session_interaction, events)
	var resume_kind = age.resume_kind
	var resume_continuation = age.resume_continuation
	_context.session_interaction = null
	_context.session_continuation.clear()
	if resume_kind == &"post-move":
		_context.set_continuation(resume_continuation.copy())
		return _context.exploration()._continue_post_move(events)
	if resume_kind == &"post-clock":
		_context.set_continuation(resume_continuation.copy())
		return _context.exploration()._continue_post_time(events)
	if resume_kind == &"combat-monster-turns":
		return _continue_after_session_combat_age_update(events)
	if resume_kind == &"completed":
		return _context.completed(events)
	return _context.failed(&"invalid_session_continuation", "The age-update queue has no valid completion path.", events)


func _continue_after_session_combat_age_update(events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var continued = _context.rules.combat_flow.continue_after_age_update(_context.state, _context.content, _context.rng)
	if not continued.ok:
		return _context.failed(continued.error_code, continued.error_message, events)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _finish_with_age_updates(events, "combat-monster-turns")
	if not _context.event_payload(continued.events, &"monster_death_macro_requested").is_empty():
		return _context.scenario()._start_session_death_macro(events)
	if continued.completed:
		return _context.scenario()._finish_direct_battle(events)
	return _context.completed(events)


func _session_age_update_request_id(update: InteractionRequest.AgeUpdateBody, index: int) -> String:
	return "session.age-update:%s:%d:%d" % [update.character_id, _context.next_revision(), index]


func _respond_session_ally_selection(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.AllySelectionBody
	if response.kind != &"ally_selection" or body == null:
		return _context.failed(&"invalid_interaction_response", "Ally selection requires selectedIds.")
	var continuation = _context.session_continuation.combat()
	if continuation == null or _context.state.combat == null or not _context.state.combat.completed or _context.state.combat.battle_id != continuation.battle_id:
		return _context.failed(&"invalid_session_continuation", "The completed battle is unavailable for ally selection.")
	# Development saves from before the Castle body-count correction can retain an
	# impossible empty selection boundary. Re-evaluate the source-backed candidate
	# set and advance it exactly as a fresh terminal battle now does.
	if _context.rules.combat_flow.ally_selection_payload(_context.state, _context.content).is_empty():
		_context.session_interaction = null
		_context.session_continuation.clear()
		return _context.scenario()._finish_direct_battle_recovery(_no_events())
	var result = _context.rules.combat_flow.apply_ally_selection(_context.state, _context.content, body.selected_ids)
	if not result.ok:
		return _context.failed(result.error_code, result.error_message)
	_context.session_interaction = null
	_context.session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _context.scenario()._finish_direct_battle_recovery(events)


func _respond_session_fumble_recovery(response: InteractionResponse) -> SessionCoordinatorResult:
	var body = response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return _context.failed(&"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	var continuation = _context.session_continuation.combat()
	if continuation == null or _context.state.combat == null or not _context.state.combat.completed or _context.state.combat.battle_id != continuation.battle_id:
		return _context.failed(&"invalid_session_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var result = _context.rules.combat_flow.apply_fumble_recovery(_context.state, _context.content, body.action, body.instance_id, body.character_id)
	if not result.ok:
		return _context.failed(result.error_code, result.error_message)
	_context.session_interaction = null
	_context.session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _context.scenario()._finish_direct_battle_recovery(events)


func _respond_session_battle_reward(response: InteractionResponse) -> SessionCoordinatorResult:
	var continuation = _context.session_continuation.reward()
	if continuation == null or _context.state.combat == null or not _context.state.combat.completed or _context.state.combat.battle_id != continuation.battle_id:
		return _context.failed(&"invalid_session_continuation", "The completed battle is unavailable for reward distribution.")
	if continuation.runtime_continuation == null:
		return _context.failed(&"invalid_session_continuation", "The battle reward continuation is unavailable.")
	var return_continuation = _context.battle_return_continuation.copy()
	var battle_outcome = _context.state.combat.outcome
	var result = _context.runtime_api.resume_classic(continuation.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _context.failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		continuation.runtime_continuation = result.continuation.copy()
		_context.session_interaction = result.interaction
		return _context.waiting(_context.session_interaction, result.events)
	_context.session_interaction = null
	_context.session_continuation.clear()
	return _context.scenario()._finish_after_direct_battle(result.events, return_continuation, battle_outcome)


func _finish_magic_transition(result: InventoryMagicServicesWorkflow.MagicTransitionResult) -> SessionCoordinatorResult:
	if result == null:
		return _context.failed(&"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return _context.failed(result.error_code, result.error_message)
	if result.completed:
		if result.process_age_updates:
			return _finish_magic_workflow(SessionWorkflowResult.completed(result.events))
		return _context.completed(result.events)
	if result.continuation == null or result.continuation.is_empty() or result.interaction == null:
		return _context.failed(&"invalid_workflow_result", "The magic workflow returned an incomplete interaction transition.")
	_context.set_continuation(result.continuation)
	_context.session_interaction = result.interaction
	return _context.waiting(_context.session_interaction, result.events)


func _finish_magic_workflow(result: SessionWorkflowResult) -> SessionCoordinatorResult:
	if result == null:
		return _context.failed(&"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return _context.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, &"completed")
	return _context.completed(result.events)


func _commit_character_draft(events: Array[DomainEvent] = []) -> SessionCoordinatorResult:
	var result := LifecyclePartyWorkflow.commit_character_draft(_context.workflow_context())
	if not result.ok:
		return _context.failed(result.error_code, result.error_message, events)
	events.append_array(result.events)
	var request_id := "character-vault:%s:%d" % [result.character_id, _context.next_revision()]
	_context.set_continuation(SessionContinuation.character_vault_publication(result.character_id))
	_context.session_interaction = SessionInteractionFactory.character_vault_confirmation(request_id, result.character_name)
	events.append(DomainEvent.new(&"character_vault_confirmation_requested", {"characterId": result.character_id}))
	return _context.waiting(_context.session_interaction, events)


func _finish_combat_result(result: CombatFlowResult) -> SessionCoordinatorResult:
	if not result.ok:
		return _context.failed(result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, &"combat-monster-turns")
	if not _context.event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _context.scenario()._start_session_death_macro(result.events)
	if result.completed:
		return _context.scenario()._finish_direct_battle(result.events)
	return _context.completed(result.events)


func _open_contextual_service(service_id: String, preceding_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var request_id := "service:%s:%d" % [service_id, _context.current_revision()]
	var operation: ScenarioRuntimeOperationResult
	if service_id == "realmz.service.temple":
		operation = _context.runtime_api.request_available_temple(request_id)
	elif service_id == "realmz.service.bank":
		operation = _context.runtime_api.request_available_bank(request_id)
	elif service_id == _context.state.active_shop_id:
		operation = _context.runtime_api.request_available_shop(request_id)
	else:
		return _context.failed(&"service_unavailable", "The selected service is not available at this location.", preceding_events)
	operation.events = preceding_events + operation.events
	return _begin_runtime_service(service_id, operation)
