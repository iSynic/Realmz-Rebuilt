## Executes validated player intents against one owned session context.

class_name SessionIntentCoordinator
extends RefCounted

var _context: SessionContext


func _init(context: SessionContext) -> void:
	_context = context


func submit(intent: PlayerIntent) -> SessionCoordinatorResult:
	var result := _submit_exploration_intent(intent)
	if result != null:
		return result
	result = _submit_magic_or_combat_intent(intent)
	if result != null:
		return result
	result = _submit_party_intent(intent)
	if result != null:
		return result
	result = _submit_inventory_or_service_intent(intent)
	if result != null:
		return result
	return SessionCoordinatorResult.rejected(&"intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func _submit_exploration_intent(intent: PlayerIntent) -> SessionCoordinatorResult:
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			var payload := intent.payload as ExplorationIntentPayloads.Move
			return _move(payload.direction, payload.aligns_dungeon_heading)
		PlayerIntent.Kind.DUNGEON_TURN:
			return _workflow(ExplorationMovementWorkflow.turn_dungeon(_context.workflow_context(), (intent.payload as ExplorationIntentPayloads.DungeonTurn).delta))
		PlayerIntent.Kind.SEARCH:
			return _search()
		PlayerIntent.Kind.TOGGLE_SEARCH:
			return _workflow(ExplorationSearchWorkflow.toggle_search(_context.workflow_context()))
		PlayerIntent.Kind.USE_TORCH:
			return _magic_transition(FieldItemWorkflow.begin_classic_torch(_context.workflow_context(), _context.next_revision()))
		PlayerIntent.Kind.CONTEXTUAL_ENCOUNTER:
			return _context.exploration().begin_contextual_encounter()
		PlayerIntent.Kind.CAMP:
			return _camp()
		PlayerIntent.Kind.REST:
			return _rest()
		PlayerIntent.Kind.HEAL:
			return _heal()
		PlayerIntent.Kind.SET_LOCATION_NOTE:
			return _workflow(LocationNoteWorkflow.set_note(_context.workflow_context(), (intent.payload as ExplorationIntentPayloads.LocationNote).text))
	return null


func _submit_magic_or_combat_intent(intent: PlayerIntent) -> SessionCoordinatorResult:
	match intent.kind:
		PlayerIntent.Kind.USE_ITEM, PlayerIntent.Kind.USE_ITEM_ON_TARGET:
			return _use_item(intent)
		PlayerIntent.Kind.CAST_SPELL:
			return _cast_spell(intent.payload as SpellIntentPayload)
		PlayerIntent.Kind.SET_FAST_SPELL:
			return _workflow(FieldMagicWorkflow.set_fast_spell(_context.workflow_context(), intent.payload as SpellIntentPayload))
		PlayerIntent.Kind.CHOOSE_COMBAT_ACTION:
			return _combat_action(intent.payload as CombatIntentPayloads.Action)
		PlayerIntent.Kind.COMBAT_MOVE:
			return _combat_move(intent.payload as CombatIntentPayloads.Move)
	return null


func _submit_party_intent(intent: PlayerIntent) -> SessionCoordinatorResult:
	var pending := _pending_interaction() != null
	match intent.kind:
		PlayerIntent.Kind.CREATE_PARTY:
			return _workflow(LifecyclePartyWorkflow.create_party(_context.workflow_context(), pending, (intent.payload as PartyIntentPayloads.Party).members))
		PlayerIntent.Kind.BEGIN_ADVENTURE:
			return _begin_adventure()
		PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
			return _workflow(LifecyclePartyWorkflow.import_vault_character(_context.workflow_context(), pending, intent.payload as PartyIntentPayloads.VaultImport))
		PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT:
			return _workflow(LifecyclePartyWorkflow.generate_character_draft(_context.workflow_context(), pending, intent.payload as PartyIntentPayloads.Draft))
		PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT:
			return _workflow(LifecyclePartyWorkflow.cancel_character_draft(_context.workflow_context(), pending))
		PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS:
			return _workflow(LifecyclePartyWorkflow.set_character_draft_spells(_context.workflow_context(), pending, (intent.payload as PartyIntentPayloads.StringList).values))
		PlayerIntent.Kind.FINALIZE_CHARACTER:
			return _finalize_character()
		PlayerIntent.Kind.REMOVE_PARTY_MEMBER:
			return _workflow(LifecyclePartyWorkflow.remove_party_member(_context.workflow_context(), pending, (intent.payload as PartyIntentPayloads.Character).character_id))
		PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS:
			var setup := intent.payload as PartyIntentPayloads.SetupOptions
			return _workflow(LifecyclePartyWorkflow.set_party_setup_options(_context.workflow_context(), pending, setup.difficulty, setup.monster_set))
		PlayerIntent.Kind.REORDER_PARTY:
			return _workflow(LifecyclePartyWorkflow.reorder_party(_context.workflow_context(), (intent.payload as PartyIntentPayloads.StringList).values))
		PlayerIntent.Kind.CHANGE_CHARACTER_APPEARANCE:
			return _workflow(LifecyclePartyWorkflow.change_character_appearance(_context.workflow_context(), intent.payload as PartyIntentPayloads.Appearance))
	return null


func _submit_inventory_or_service_intent(intent: PlayerIntent) -> SessionCoordinatorResult:
	match intent.kind:
		PlayerIntent.Kind.EQUIP_ITEM:
			return _workflow(InventoryWorkflow.equip_item(_context.workflow_context(), intent.payload as InventoryIntentPayloads.Action))
		PlayerIntent.Kind.UNEQUIP_ITEM:
			return _workflow(InventoryWorkflow.unequip_item(_context.workflow_context(), intent.payload as InventoryIntentPayloads.Action))
		PlayerIntent.Kind.SPLIT_ITEM:
			return _workflow(InventoryWorkflow.split_item(_context.workflow_context(), intent.payload as InventoryIntentPayloads.Action))
		PlayerIntent.Kind.JOIN_ITEM:
			return _workflow(InventoryWorkflow.join_item(_context.workflow_context(), intent.payload as InventoryIntentPayloads.Action))
		PlayerIntent.Kind.DROP_ITEM:
			return _request_drop_item(intent.payload as InventoryIntentPayloads.Action)
		PlayerIntent.Kind.TRADE_ITEM:
			return _workflow(InventoryWorkflow.trade_item(_context.workflow_context(), intent.payload as InventoryIntentPayloads.Action))
		PlayerIntent.Kind.MONEY_ACTION:
			return _workflow(SessionMoneyWorkflow.perform(_context.workflow_context(), intent.payload as EconomyIntentPayloads.Money))
		PlayerIntent.Kind.SERVICE_ACTION:
			return _service_action(intent.payload as EconomyIntentPayloads.Service)
	return null


func _camp() -> SessionCoordinatorResult:
	var result := ExplorationTimeWorkflow.toggle_camp(_context.workflow_context())
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	if not _context.state.party_camping and result.timed_day == 0:
		return _context.responses().finish_with_age_updates(result.events, &"completed")
	_context.exploration().set_post_time_continuation(result.map, "camp-entry-second" if _context.state.party_camping else "completed", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _context.responses().finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _rest() -> SessionCoordinatorResult:
	var result := ExplorationTimeWorkflow.rest(_context.workflow_context())
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	_context.exploration().set_post_time_continuation(result.map, "rest-second", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _context.responses().finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _heal() -> SessionCoordinatorResult:
	if _context.state.character_spellcasting_blocked:
		return SessionCoordinatorResult.completed([DomainEvent.new(&"classic_notification_requested", {"text": "Your characters can't cast spells in this area.", "soundId": 6000, "source": "classic-field-heal"})])
	var result := ExplorationTimeWorkflow.heal(_context.workflow_context())
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	_context.exploration().set_post_time_continuation(result.map, "heal", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _context.responses().finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _search() -> SessionCoordinatorResult:
	var result := ExplorationSearchWorkflow.search(_context.workflow_context())
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	_context.exploration().set_post_time_continuation(result.map, "area-search-second", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _context.responses().finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _move(direction: Vector2i, aligns_dungeon_heading: bool) -> SessionCoordinatorResult:
	var movement := _context.content.world.probe_movement(_context.state.party.map_id, _context.state.party.coordinate, direction, _context.state.world, _context.state.party_in_boat)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return SessionCoordinatorResult.rejected(&"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	var fatigue_warning := ExplorationMovementWorkflow.fatigue_warning(_context.workflow_context())
	if fatigue_warning != null:
		return SessionCoordinatorResult.completed([fatigue_warning])
	var events: Array[DomainEvent] = []
	if aligns_dungeon_heading:
		var heading := ExplorationMovementWorkflow.align_dungeon_heading(_context.workflow_context(), direction)
		if not heading.ok:
			return SessionCoordinatorResult.failed(heading.error_code, heading.error_message, heading.events)
		events.append_array(heading.events)
	if _context.state.location_services.bank_available and SessionInteractionFactory.has_pooled_wealth(_context.state.party):
		var banked := _context.state.party.pooled_wealth.to_data()
		_context.rules.economy.pool_to_bank(_context.state.party)
		_context.state.location_services.bank_available = false
		events.append(DomainEvent.new(&"pooled_wealth_banked_before_movement", {"wealth": banked, "direction": [direction.x, direction.y]}))
		return _context.exploration().move_after_pooled_wealth(direction, events)
	if not _context.state.location_services.bank_available and SessionInteractionFactory.has_pooled_wealth(_context.state.party):
		_context.set_continuation(ServiceContinuations.pooled_wealth_departure(&"warning", direction))
		_context.session_interaction = SessionInteractionFactory.pooled_wealth_departure_warning("pooled-wealth-departure:%d" % _context.next_revision())
		events.append(DomainEvent.new(&"pooled_wealth_departure_warning", {"wealth": _context.state.party.pooled_wealth.to_data(), "direction": [direction.x, direction.y]}))
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 20005, "waitForCompletion": false, "stopExisting": true, "source": "classic-pooled-wealth-departure-question"}))
		return SessionCoordinatorResult.waiting(_context.session_interaction, events)
	return _context.exploration().move_after_pooled_wealth(direction, events)


func _use_item(intent: PlayerIntent) -> SessionCoordinatorResult:
	var actor_id := ""
	var item_id := ""
	var target_id := ""
	var target_ids: Array[String] = []
	var target_coordinates: Array[Vector2i] = []
	var coordinate := CombatFlow.INVALID_COORDINATE
	var rotation := 0
	if intent.payload is InventoryIntentPayloads.Use:
		actor_id = (intent.payload as InventoryIntentPayloads.Use).actor_id
		item_id = (intent.payload as InventoryIntentPayloads.Use).item_id
	else:
		var target := intent.payload as InventoryIntentPayloads.Target
		actor_id = target.actor_id
		item_id = target.item_id
		target_id = target.target_id
		target_ids = target.target_ids
		target_coordinates = target.target_coordinates
		coordinate = target.coordinate
		rotation = target.rotation
	var character := _context.state.party.character_by_id(actor_id)
	if character == null:
		character = FieldItemWorkflow.item_owner(_context.workflow_context(), item_id)
	var instance := _context.item_instance(character, item_id)
	var item: ItemDefinition = null if instance == null else _context.content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or item == null:
		return SessionCoordinatorResult.rejected(&"unknown_item_instance", "The selected character does not carry that item instance.")
	if FieldItemWorkflow.is_classic_door_item(item):
		return _context.scenario().start_item_xap(character, instance, item)
	if _active_combat():
		return _combat_result(_context.rules.combat_flow.use_spell_item(_context.state, _context.content, character.id, target_id, instance.id, _context.rng, coordinate, rotation, target_ids, target_coordinates))
	return _magic_transition(FieldItemWorkflow.begin_field_spell_item(_context.workflow_context(), actor_id, item_id, target_id, target_ids, _context.next_revision()))


func _request_drop_item(payload: InventoryIntentPayloads.Action) -> SessionCoordinatorResult:
	var character := _context.state.party.character_by_id(payload.actor_id)
	var instance := _context.item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else _context.content.items.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionCoordinatorResult.rejected(&"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _context.rules.inventory.classic_drop_probe(character, instance)
	if not probe.allowed:
		return SessionCoordinatorResult.rejected(&"item_cannot_drop", probe.reason)
	var targeting := TargetingContinuationBody.new()
	targeting.character_id = character.id
	targeting.instance_id = instance.id
	_context.set_continuation(InventoryContinuations.drop_confirmation(targeting))
	var display_name := definition.name if instance.identified else definition.unidentified_name
	_context.session_interaction = SessionInteractionFactory.drop_item_confirmation("session.drop-item:%s:%d" % [instance.id, _context.next_revision()], display_name)
	return SessionCoordinatorResult.waiting(_context.session_interaction, [DomainEvent.new(&"item_drop_requested", {"characterId": character.id, "instanceId": instance.id})])


func _cast_spell(payload: SpellIntentPayload) -> SessionCoordinatorResult:
	if payload.operation == &"identify-inventory":
		return _workflow(FieldItemWorkflow.identify_inventory(_context.workflow_context(), payload))
	if payload.operation == &"make-scroll":
		return _workflow(FieldMagicWorkflow.make_scroll(_context.workflow_context(), payload))
	if payload.operation == &"use-scroll":
		return _use_scroll(payload)
	if not _active_combat():
		return _magic_transition(FieldMagicWorkflow.begin_field_spell(_context.workflow_context(), payload, _context.next_revision()))
	return _combat_result(_context.rules.combat_flow.cast_spell(_context.state, _context.content, payload.caster_id, payload.target_id, payload.spell_id, payload.power, _context.rng, payload.coordinate, payload.rotation, payload.target_ids, payload.target_coordinates))


func _use_scroll(payload: SpellIntentPayload) -> SessionCoordinatorResult:
	if _active_combat():
		return _combat_result(_context.rules.combat_flow.use_combat_scroll(_context.state, _context.content, payload.caster_id, payload.scroll_slot, payload.target_id, _context.rng, payload.coordinate, payload.rotation, payload.target_ids, payload.target_coordinates))
	return _magic_transition(FieldMagicWorkflow.begin_field_scroll(_context.workflow_context(), payload, _context.next_revision()))


func _combat_action(payload: CombatIntentPayloads.Action) -> SessionCoordinatorResult:
	if payload.action == &"retreat":
		var probe: Variant = _context.rules.combat_flow.reactions.probe_character_retreat(_context.state.combat, _context.state.party.characters(), payload.actor_id)
		if not probe.allowed:
			return SessionCoordinatorResult.rejected(probe.reason, probe.reason_text)
		return _request_retreat(payload.actor_id, &"explicit", Vector2i(-100_000, -100_000))
	return _combat_result(CombatCommandWorkflow.submit_action(_context.workflow_context(), payload))


func _combat_move(payload: CombatIntentPayloads.Move) -> SessionCoordinatorResult:
	var edge_probe: Variant = _context.rules.combat_flow.reactions.probe_edge_retreat(_context.state.combat, payload.actor_id, payload.destination)
	if edge_probe.allowed:
		if not edge_probe.forced:
			return _request_retreat(payload.actor_id, &"edge", payload.destination)
		return _combat_result(CombatCommandWorkflow.move_character(_context.workflow_context(), payload, true))
	var result := CombatCommandWorkflow.move_character(_context.workflow_context(), payload, false)
	if not result.ok and result.error_code == &"combat_friendly_collision_choice_required":
		return _request_friendly_collision(payload)
	return _combat_result(result)


func _request_retreat(actor_id: String, mode: StringName, destination: Vector2i) -> SessionCoordinatorResult:
	if _context.state.combat == null or _context.state.combat.turns.active_actor_id() != actor_id:
		return SessionCoordinatorResult.rejected(&"invalid_combat_actor", "The active character cannot retreat.")
	var combat := CombatContinuationBody.new()
	combat.battle_id = _context.state.combat.battle_id
	combat.actor_id = actor_id
	combat.mode = mode
	combat.destination = destination
	_context.set_continuation(CombatContinuations.retreat_confirmation(combat))
	_context.session_interaction = SessionInteractionFactory.retreat_confirmation("session.combat-retreat:%d" % _context.next_revision())
	return SessionCoordinatorResult.waiting(_context.session_interaction, [])


func _request_friendly_collision(payload: CombatIntentPayloads.Move) -> SessionCoordinatorResult:
	var target_id := _context.rules.combat_flow.reactions.friendly_collision_target_id(_context.state, payload.actor_id, payload.destination)
	if target_id.is_empty():
		return SessionCoordinatorResult.rejected(&"invalid_friendly_collision", "The adjacent ally is no longer available.")
	var collision := CombatContinuationBody.new()
	collision.battle_id = _context.state.combat.battle_id
	collision.actor_id = payload.actor_id
	collision.mode = &"friendly"
	collision.destination = payload.destination
	_context.set_continuation(CombatContinuations.friendly_collision(collision))
	_context.session_interaction = SessionInteractionFactory.friendly_collision("session.combat-friendly-collision:%d" % _context.next_revision())
	return SessionCoordinatorResult.waiting(_context.session_interaction, [])


func _begin_adventure() -> SessionCoordinatorResult:
	var result := LifecyclePartyWorkflow.begin_adventure(_context.workflow_context(), _pending_interaction() != null)
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	return _context.scenario().start_application_hook(ScenarioApplicationHooks.START_GAME, &"begin-adventure", "", result.events)


func _finalize_character() -> SessionCoordinatorResult:
	var result := LifecyclePartyWorkflow.prepare_character_finalize(_context.workflow_context(), _pending_interaction() != null)
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, result.events)
	if result.remaining_spell_points > 0:
		_context.set_continuation(CharacterContinuations.spell_confirmation(result.character_id, result.remaining_spell_points))
		_context.session_interaction = SessionInteractionFactory.character_spell_confirmation("character-spells:%s:%d" % [result.character_id, _context.next_revision()], result.remaining_spell_points)
		return SessionCoordinatorResult.waiting(_context.session_interaction, [DomainEvent.new(&"character_spell_confirmation_requested", {"characterId": result.character_id, "remaining": result.remaining_spell_points})])
	return _commit_character_draft()


func _commit_character_draft(events: Array[DomainEvent] = []) -> SessionCoordinatorResult:
	var result := LifecyclePartyWorkflow.commit_character_draft(_context.workflow_context())
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	events.append_array(result.events)
	_context.set_continuation(CharacterContinuations.vault_publication(result.character_id))
	_context.session_interaction = SessionInteractionFactory.character_vault_confirmation("character-vault:%s:%d" % [result.character_id, _context.next_revision()], result.character_name)
	events.append(DomainEvent.new(&"character_vault_confirmation_requested", {"characterId": result.character_id}))
	return SessionCoordinatorResult.waiting(_context.session_interaction, events)


func _service_action(payload: EconomyIntentPayloads.Service) -> SessionCoordinatorResult:
	if payload.action != &"enter":
		return SessionCoordinatorResult.rejected(&"unknown_service_action", "Only entering an available service is implemented through this intent.")
	if payload.service_id == "realmz.service.temple":
		if not _context.state.location_services.temple_available:
			return SessionCoordinatorResult.rejected(&"service_unavailable", "The selected temple is not available at this location.")
		return _context.scenario().start_application_hook(ScenarioApplicationHooks.TEMPLE, &"service", payload.service_id, [])
	if payload.service_id == "realmz.service.bank":
		return _open_contextual_service(payload.service_id)
	if payload.service_id == _context.state.location_services.active_shop_id:
		if payload.service_id.is_empty() or _context.content.economy.shop_by_id(payload.service_id) == null:
			return SessionCoordinatorResult.rejected(&"service_unavailable", "The selected shop is not available at this location.")
		return _context.scenario().start_application_hook(ScenarioApplicationHooks.SHOP, &"service", payload.service_id, [])
	return SessionCoordinatorResult.rejected(&"service_unavailable", "The selected service is not available at this location.")


func _open_contextual_service(service_id: String) -> SessionCoordinatorResult:
	var request_id := "service:%s:%d" % [service_id, _context.current_revision()]
	var operation: ScenarioRuntimeOperationResult
	if service_id == "realmz.service.temple":
		operation = _context.runtime_api.request_available_temple(request_id)
	elif service_id == "realmz.service.bank":
		operation = _context.runtime_api.request_available_bank(request_id)
	elif service_id == _context.state.location_services.active_shop_id:
		operation = _context.runtime_api.request_available_shop(request_id)
	else:
		return SessionCoordinatorResult.failed(&"service_unavailable", "The selected service is not available at this location.")
	return _context.responses().begin_runtime_service(service_id, operation)


func _workflow(result: SessionWorkflowResult) -> SessionCoordinatorResult:
	if result == null:
		return SessionCoordinatorResult.rejected(&"invalid_workflow_result", "The session workflow returned no result.")
	return SessionCoordinatorResult.completed(result.events) if result.ok else SessionCoordinatorResult.rejected(result.error_code, result.error_message)


func _combat_result(result: CombatFlowResult) -> SessionCoordinatorResult:
	if result == null:
		return SessionCoordinatorResult.rejected(&"invalid_combat_result", "The combat workflow returned no result.")
	if not result.ok:
		return SessionCoordinatorResult.rejected(result.error_code, result.error_message)
	return _context.responses().finish_combat_result(result)


func _magic_transition(result: MagicTransitionResult) -> SessionCoordinatorResult:
	if result == null:
		return SessionCoordinatorResult.rejected(&"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return SessionCoordinatorResult.rejected(result.error_code, result.error_message)
	if not result.completed and (result.continuation == null or result.continuation.is_empty() or result.interaction == null):
		return SessionCoordinatorResult.rejected(&"invalid_workflow_result", "The magic workflow returned an incomplete interaction transition.")
	return _context.responses().finish_magic_transition(result)


func _active_combat() -> bool:
	return _context.state.combat != null and not _context.state.combat.completed


func _pending_interaction() -> InteractionRequest:
	if _context.session_interaction != null:
		return _context.session_interaction
	return _context.scenario_vm.pending_request() if _context.scenario_vm != null else null
