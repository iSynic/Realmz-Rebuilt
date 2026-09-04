## Defines the typed game session contract used by playthrough transactions.

class_name GameSession
extends RefCounted

var _context: SessionContext = SessionContext.new()
var _started: bool = false
var _view_projector := SessionViewProjector.new()
var _exploration_coordinator: RefCounted
var _scenario_coordinator: RefCounted
var _response_coordinator: RefCounted
var _debug_coordinator: RefCounted
var _debug_operation_active: bool = false


func _ensure_coordinators() -> void:
	if _exploration_coordinator != null:
		return
	_exploration_coordinator = SessionExplorationCoordinator.new(_context)
	_scenario_coordinator = SessionScenarioCoordinator.new(_context)
	_response_coordinator = SessionResponsesCoordinator.new(_context)
	_context.bind_coordinators(_exploration_coordinator, _scenario_coordinator, _response_coordinator)
	_debug_coordinator = SessionDebugCoordinator.new(_context)


func _release_coordinators() -> void:
	_context.release_coordinators()
	_exploration_coordinator = null
	_scenario_coordinator = null
	_response_coordinator = null
	_debug_coordinator = null


func _commit_coordinator_result(result: SessionCoordinatorResult) -> SessionStep:
	_release_coordinators()
	if result == null:
		return _finish_failed(&"invalid_coordinator_result", "The session coordinator returned no typed result.", [])
	match result.state:
		SessionCoordinatorResult.State.COMPLETED:
			return _finish_completed(result.events)
		SessionCoordinatorResult.State.WAITING:
			return _finish_waiting(result.interaction, result.events)
		SessionCoordinatorResult.State.FAILED:
			return _finish_failed(result.error_code, result.error_message, result.events)
		SessionCoordinatorResult.State.CLOSE:
			return _commit_close(result.events, result.close_reason)
	return _finish_failed(&"invalid_coordinator_result", "The session coordinator returned an unknown state.", [])


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_context.current_revision(), &"session_already_started", "The session has already started.")
	if content == null or content.scenario == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_start_location", "The package start location is unavailable.")
	var starting_characters: Array[CharacterState] = []
	var game_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, starting_characters), RealmzClock.new())
	game_state.world.mark_visited(content.start_map_id, content.start_coordinate)
	var random_source := RealmzRng.new(initial_seed)
	var action_state := ScenarioActionState.new()
	var scenario_vm := ScenarioVm.new()
	scenario_vm.configure(content.scenario)
	_context.content = content
	_context.state = game_state
	_context.rng = random_source
	_context.rules = RealmzRules.new()
	_context.scenario_action_state = action_state
	_context.scenario_vm = scenario_vm
	_context.runtime_api = RealmzRuntimeApi.new(_context.content, _context.state, _context.rng, _context.scenario_action_state, _context.rules)
	_context.session_continuation.clear()
	_context.battle_return_continuation.clear()
	_context.session_interaction = null
	_view_projector.clear()
	_started = true
	_record_current_visibility()
	_context.set_revision(1)
	return SessionStep.completed(_context.current_revision(), [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SessionSnapshot) -> SessionStep:
	var result := SessionRestoreValidator.validate(content, save_envelope)
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	var candidate := result.candidate
	_context.content = content
	_context.state = candidate.state
	_context.rng = candidate.rng
	_context.rules = candidate.rules
	_context.scenario_action_state = candidate.scenario_action_state
	_context.scenario_vm = candidate.scenario_vm
	_context.runtime_api = RealmzRuntimeApi.new(_context.content, _context.state, _context.rng, _context.scenario_action_state, _context.rules)
	_context.session_continuation = candidate.continuation
	_context.battle_return_continuation = candidate.battle_return_continuation
	_context.session_interaction = candidate.session_interaction
	_view_projector.clear()
	_context.set_revision(candidate.view_revision)
	_started = true
	_record_current_visibility()
	return SessionStep.completed(_context.current_revision(), [DomainEvent.new("session_restored")])


func close() -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"session_not_started", "There is no active session to close.")
	var pending := _pending_interaction()
	if (_context.scenario_vm.is_active() and pending == null) or (pending != null and pending.kind != InteractionRequest.COMBAT):
		return SessionStep.failed(_context.current_revision(), &"session_not_committed", "The session can close only at a committed boundary.")
	# Castle permits End Adventure during combat after confirmation. Abandon the
	# interrupted combat/VM interaction before the synchronous Global hooks run.
	if pending != null:
		_context.session_continuation.clear()
		_context.battle_return_continuation.clear()
		_context.session_interaction = null
		_context.scenario_vm = ScenarioVm.new()
		_context.scenario_vm.configure(_context.content.scenario)
		_context.runtime_api = RealmzRuntimeApi.new(_context.content, _context.state, _context.rng, _context.scenario_action_state, _context.rules)
	return _start_application_hook(ScenarioApplicationHooks.END_ADVENTURE, "end-adventure", "", [])


func _commit_close(events: Array[DomainEvent], reason: String) -> SessionStep:
	var campaign_id := _context.content.campaign_id
	_context.session_continuation.clear()
	_context.battle_return_continuation.clear()
	_context.session_interaction = null
	_context.runtime_api = null
	_context.scenario_vm = null
	_context.scenario_action_state = null
	_context.rules = null
	_context.rng = null
	_context.state = null
	_context.content = null
	_view_projector.clear()
	_started = false
	_context.set_revision(_context.next_revision())
	var completed_events: Array[DomainEvent] = []
	completed_events.assign(events)
	completed_events.append(DomainEvent.new(&"session_ended", {"campaignId": campaign_id, "reason": reason}))
	return SessionStep.completed(_context.current_revision(), completed_events)


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"session_not_started", "Start or restore the session first.")
	if intent == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_intent", "A typed player intent is required.")
	if not intent.is_valid():
		return SessionStep.failed(_context.current_revision(), &"invalid_intent_payload", "The player intent payload does not match its kind.")
	if intent.kind == PlayerIntent.Kind.SET_COMBAT_AUTO:
		return _set_combat_auto(intent)
	if _pending_interaction() != null or _context.scenario_vm.is_active():
		return SessionStep.failed(_context.current_revision(), &"interaction_pending", "Respond to the pending interaction first.")
	if not _context.state.party_setup_completed and intent.kind not in [PlayerIntent.Kind.CREATE_PARTY, PlayerIntent.Kind.BEGIN_ADVENTURE, PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT, PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS, PlayerIntent.Kind.FINALIZE_CHARACTER, PlayerIntent.Kind.REMOVE_PARTY_MEMBER, PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS]:
		return SessionStep.failed(_context.current_revision(), &"party_setup_incomplete", "Finish party setup before beginning the adventure.")
	if _context.state.combat != null and not _context.state.combat.completed and intent.kind not in [PlayerIntent.Kind.USE_ITEM, PlayerIntent.Kind.USE_ITEM_ON_TARGET, PlayerIntent.Kind.CAST_SPELL, PlayerIntent.Kind.CHOOSE_COMBAT_ACTION, PlayerIntent.Kind.COMBAT_MOVE]:
		return SessionStep.failed(_context.current_revision(), &"battle_in_progress", "Resolve the active battle before returning to exploration.")
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			var move_payload := intent.payload as PlayerIntent.MovePayload
			return _move(move_payload.direction, move_payload.aligns_dungeon_heading)
		PlayerIntent.Kind.DUNGEON_TURN:
			return _turn_dungeon((intent.payload as PlayerIntent.DungeonTurnPayload).delta)
		PlayerIntent.Kind.SEARCH:
			return _search()
		PlayerIntent.Kind.TOGGLE_SEARCH:
			return _toggle_search()
		PlayerIntent.Kind.USE_TORCH:
			return _use_torch()
		PlayerIntent.Kind.CONTEXTUAL_ENCOUNTER:
			return _contextual_encounter()
		PlayerIntent.Kind.CAMP:
			return _camp()
		PlayerIntent.Kind.REST:
			return _rest()
		PlayerIntent.Kind.HEAL:
			return _heal()
		PlayerIntent.Kind.USE_ITEM:
			return _use_item(intent)
		PlayerIntent.Kind.USE_ITEM_ON_TARGET:
			return _use_item(intent)
		PlayerIntent.Kind.CAST_SPELL:
			return _cast_spell(intent)
		PlayerIntent.Kind.SET_FAST_SPELL:
			return _commit_workflow_result(InventoryMagicServicesWorkflow.set_fast_spell(_workflow_context(), intent.payload as PlayerIntent.SpellPayload))
		PlayerIntent.Kind.CHOOSE_COMBAT_ACTION:
			return _combat_action(intent)
		PlayerIntent.Kind.COMBAT_MOVE:
			return _combat_move(intent)
		PlayerIntent.Kind.SET_COMBAT_AUTO:
			return _set_combat_auto(intent)
		PlayerIntent.Kind.CREATE_PARTY:
			return _commit_workflow_result(LifecyclePartyWorkflow.create_party(_workflow_context(), _pending_interaction() != null, (intent.payload as PlayerIntent.PartyPayload).members))
		PlayerIntent.Kind.BEGIN_ADVENTURE:
			return _begin_adventure()
		PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
			return _commit_workflow_result(LifecyclePartyWorkflow.import_vault_character(_workflow_context(), _pending_interaction() != null, intent.payload as PlayerIntent.VaultImportPayload))
		PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT:
			return _commit_workflow_result(LifecyclePartyWorkflow.generate_character_draft(_workflow_context(), _pending_interaction() != null, intent.payload as PlayerIntent.CharacterDraftPayload))
		PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT:
			return _commit_workflow_result(LifecyclePartyWorkflow.cancel_character_draft(_workflow_context(), _pending_interaction() != null))
		PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS:
			return _commit_workflow_result(LifecyclePartyWorkflow.set_character_draft_spells(_workflow_context(), _pending_interaction() != null, (intent.payload as PlayerIntent.StringListPayload).values))
		PlayerIntent.Kind.FINALIZE_CHARACTER:
			return _finalize_character(intent)
		PlayerIntent.Kind.REMOVE_PARTY_MEMBER:
			return _commit_workflow_result(LifecyclePartyWorkflow.remove_party_member(_workflow_context(), _pending_interaction() != null, (intent.payload as PlayerIntent.CharacterPayload).character_id))
		PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS:
			var setup := intent.payload as PlayerIntent.PartySetupOptionsPayload
			return _commit_workflow_result(LifecyclePartyWorkflow.set_party_setup_options(_workflow_context(), _pending_interaction() != null, setup.difficulty, setup.monster_set))
		PlayerIntent.Kind.REORDER_PARTY:
			return _commit_workflow_result(LifecyclePartyWorkflow.reorder_party(_workflow_context(), (intent.payload as PlayerIntent.StringListPayload).values))
		PlayerIntent.Kind.CHANGE_CHARACTER_APPEARANCE:
			return _commit_workflow_result(LifecyclePartyWorkflow.change_character_appearance(_workflow_context(), intent.payload as PlayerIntent.AppearancePayload))
		PlayerIntent.Kind.EQUIP_ITEM:
			return _commit_workflow_result(InventoryMagicServicesWorkflow.equip_item(_workflow_context(), intent.payload as PlayerIntent.ItemActionPayload))
		PlayerIntent.Kind.UNEQUIP_ITEM:
			return _commit_workflow_result(InventoryMagicServicesWorkflow.unequip_item(_workflow_context(), intent.payload as PlayerIntent.ItemActionPayload))
		PlayerIntent.Kind.SPLIT_ITEM:
			return _commit_workflow_result(InventoryMagicServicesWorkflow.split_item(_workflow_context(), intent.payload as PlayerIntent.ItemActionPayload))
		PlayerIntent.Kind.JOIN_ITEM:
			return _commit_workflow_result(InventoryMagicServicesWorkflow.join_item(_workflow_context(), intent.payload as PlayerIntent.ItemActionPayload))
		PlayerIntent.Kind.DROP_ITEM:
			return _request_drop_item(intent)
		PlayerIntent.Kind.TRADE_ITEM:
			return _commit_workflow_result(InventoryMagicServicesWorkflow.trade_item(_workflow_context(), intent.payload as PlayerIntent.ItemActionPayload))
		PlayerIntent.Kind.MONEY_ACTION:
			return _money_action(intent)
		PlayerIntent.Kind.SERVICE_ACTION:
			return _service_action(intent)
		PlayerIntent.Kind.SET_LOCATION_NOTE:
			return _commit_workflow_result(ExplorationTimeWorkflow.set_location_note(_workflow_context(), (intent.payload as PlayerIntent.LocationNotePayload).text))
		_:
			return SessionStep.failed(_context.current_revision(), &"intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func apply_debug_command(command: SessionDebugCommand) -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"debug_command_unavailable", "Debug commands require a committed active adventure boundary.")
	_ensure_coordinators()
	var result: SessionCoordinatorResult = _debug_coordinator.run(command)
	if _debug_coordinator.started_ephemeral_operation:
		_debug_operation_active = true
	return _commit_coordinator_result(result)


func respond(response: InteractionResponse) -> SessionStep:
	if not _started:
		return SessionStep.failed(_context.current_revision(), &"session_not_started", "Start or restore the session first.")
	var pending := _pending_interaction()
	if pending == null:
		return SessionStep.failed(_context.current_revision(), &"no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != pending.request_id:
		return SessionStep.failed(_context.current_revision(), &"interaction_mismatch", "The response does not match the pending request.")
	if not response.is_supported_kind():
		return SessionStep.failed(_context.current_revision(), &"invalid_interaction_response", "The response payload does not match its interaction kind.")
	if _context.session_interaction != null:
		return _respond_session_interaction(response)
	var result := _context.scenario_vm.resume(response, _context.runtime_api)
	if _debug_operation_active and result.state != ScenarioVmResult.State.WAITING:
		_debug_operation_active = false
	var events: Array[DomainEvent] = []
	events.append_array(result.events)
	if _context.session_continuation.kind == &"application-hook" and _events_have(result.events, &"party_revived"):
		_context.session_continuation.application().party_revived = true
	return _finish_resumed_vm_result(result, events)


func _finish_resumed_vm_result(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.finish_resumed_vm_result(result, events))


func view(events: Array[DomainEvent] = []) -> GameView:
	var result := _view_projector.project(_workflow_context(), _pending_interaction(), _context.current_revision(), _started, events)
	if result != null and result.combat_action_request == null and result.pending_interaction == null and result.combat_view != null and result.combat_view.outcome == &"active":
		result.combat_action_request = _context.runtime_api.active_combat_request("session.combat-command:%d" % _context.current_revision())
	return result


func set_map_projection_size(requested_size: Vector2i) -> bool:
	return _view_projector.set_map_projection_size(requested_size)


func _workflow_context(events: Array[DomainEvent] = []) -> SessionWorkflowContext:
	return SessionWorkflowContext.new(_context.content, _context.state, _context.rules, _context.rng, _context.scenario_vm, _context.scenario_action_state, events)


func _set_continuation(continuation: SessionContinuation) -> void:
	assert(continuation != null and not continuation.is_empty(), "A live continuation must have a typed body")
	_context.session_continuation = continuation


func snapshot() -> SessionSnapshot:
	if not _started or _debug_operation_active or (_context.scenario_vm.is_active() and _context.scenario_vm.pending_request() == null):
		return null
	var state := GameState.from_data(_context.state.to_data())
	var vm_state := ScenarioVmSnapshot.from_data(_context.scenario_vm.snapshot().to_data())
	var action_state := ScenarioActionState.from_data(_context.scenario_action_state.to_data())
	var interaction: InteractionRequest = null
	if _context.session_interaction != null:
		interaction = InteractionRequest.from_data(_context.session_interaction.to_data())
	if state == null or vm_state == null or action_state == null or _context.session_interaction != null and interaction == null:
		return null
	var continuation := null if _context.session_continuation.is_empty() else SessionContinuation.from_data(_context.session_continuation.to_data())
	var battle_return := null if _context.battle_return_continuation.is_empty() else SessionContinuation.from_data(_context.battle_return_continuation.to_data())
	return SessionSnapshot.new(_context.content.campaign_id, _context.content.package_hash, _context.content.rules_version, _context.current_revision(), state, _context.rng.snapshot(), vm_state, action_state, continuation, battle_return, interaction)


func rng_trace() -> Array[Dictionary]:
	return [] if _context.rng == null else _context.rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _context.scenario_vm == null else _context.scenario_vm.trace()


func _camp() -> SessionStep:
	var result := ExplorationTimeWorkflow.toggle_camp(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if not _context.state.party_camping and result.timed_day == 0:
		return _finish_with_age_updates(result.events, "completed")
	_set_post_time_continuation(result.map, "camp-entry-second" if _context.state.party_camping else "completed", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _rest() -> SessionStep:
	var result := ExplorationTimeWorkflow.rest(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	_set_post_time_continuation(result.map, "rest-second", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _heal() -> SessionStep:
	if _context.state.character_spellcasting_blocked:
		return _finish_completed([
			DomainEvent.new(&"classic_notification_requested", {
				"text": "Your characters can't cast spells in this area.",
				"soundId": 6000,
				"source": "classic-field-heal",
			}),
		])
	var result := ExplorationTimeWorkflow.heal(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	_set_post_time_continuation(result.map, "heal", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _use_item(intent: PlayerIntent) -> SessionStep:
	var actor_id := ""
	var item_id := ""
	var target_id := ""
	var target_ids: Array[String] = []
	var target_coordinates: Array[Vector2i] = []
	var target_coordinate := CombatFlow.INVALID_COORDINATE
	var rotation := 0
	if intent.payload is PlayerIntent.ItemUsePayload:
		var use_payload := intent.payload as PlayerIntent.ItemUsePayload
		actor_id = use_payload.actor_id
		item_id = use_payload.item_id
	else:
		var target_payload := intent.payload as PlayerIntent.ItemTargetPayload
		actor_id = target_payload.actor_id
		item_id = target_payload.item_id
		target_id = target_payload.target_id
		target_ids = target_payload.target_ids.duplicate()
		target_coordinates = target_payload.target_coordinates.duplicate()
		target_coordinate = target_payload.coordinate
		rotation = target_payload.rotation
	var character := _context.state.party.character_by_id(actor_id)
	if character == null:
		character = InventoryMagicServicesWorkflow.item_owner(_workflow_context(), item_id)
	var instance := _item_instance(character, item_id)
	var item: ItemDefinition = null if instance == null else _context.content.item_by_id(instance.definition_id)
	if character == null or instance == null or item == null:
		return SessionStep.failed(_context.current_revision(), &"unknown_item_instance", "The selected character does not carry that item instance.")
	if InventoryMagicServicesWorkflow.is_classic_door_item(item):
		_ensure_coordinators()
		return _commit_coordinator_result(_scenario_coordinator.start_item_xap(character, instance, item))
	if _context.state.combat != null and not _context.state.combat.completed:
		var combat_result := _context.rules.combat_flow.use_spell_item(_context.state, _context.content, character.id, target_id, instance.id, _context.rng, target_coordinate, rotation, target_ids, target_coordinates)
		if not combat_result.ok:
			return SessionStep.failed(_context.current_revision(), combat_result.error_code, combat_result.error_message)
		if not CharacterAgingResult.update_payloads(combat_result.events).is_empty():
			return _finish_with_age_updates(combat_result.events, "combat-monster-turns")
		if not _event_payload(combat_result.events, &"monster_death_macro_requested").is_empty():
			return _start_session_death_macro(combat_result.events)
		if combat_result.completed:
			return _finish_direct_battle(combat_result.events)
		return _finish_completed(combat_result.events)
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_field_spell_item(_workflow_context(), actor_id, item_id, target_id, target_ids, _context.next_revision()))


func _request_drop_item(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ItemActionPayload
	var character := _context.state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else _context.content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_context.current_revision(), &"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _context.rules.inventory.classic_drop_probe(character, instance)
	if not probe.allowed:
		return SessionStep.failed(_context.current_revision(), &"item_cannot_drop", probe.reason)
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.instance_id = instance.id
	_set_continuation(SessionContinuation.targeting_selection(&"drop-item-confirmation", targeting))
	var display_name := definition.name if instance.identified else definition.unidentified_name
	_context.session_interaction = SessionInteractionFactory.drop_item_confirmation("session.drop-item:%s:%d" % [instance.id, _context.next_revision()], display_name)
	return _finish_waiting(_context.session_interaction, [DomainEvent.new(&"item_drop_requested", {"characterId": character.id, "instanceId": instance.id})])


func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null or instance_id.is_empty():
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


func _cast_spell(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.SpellPayload
	if payload.operation == &"identify-inventory":
		return _commit_workflow_result(InventoryMagicServicesWorkflow.identify_inventory(_workflow_context(), payload))
	if payload.operation == &"make-scroll":
		return _commit_workflow_result(InventoryMagicServicesWorkflow.make_scroll(_workflow_context(), payload))
	if payload.operation == &"use-scroll":
		return _use_scroll(payload)
	if _context.state.combat == null or _context.state.combat.completed:
		return _cast_field_spell(payload)
	var result := _context.rules.combat_flow.cast_spell(_context.state, _context.content, payload.caster_id, payload.target_id, payload.spell_id, payload.power, _context.rng, payload.coordinate, payload.rotation, payload.target_ids, payload.target_coordinates)
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _use_scroll(payload: PlayerIntent.SpellPayload) -> SessionStep:
	if _context.state.combat != null and not _context.state.combat.completed:
		var combat_result := _context.rules.combat_flow.use_combat_scroll(_context.state, _context.content, payload.caster_id, payload.scroll_slot, payload.target_id, _context.rng, payload.coordinate, payload.rotation, payload.target_ids, payload.target_coordinates)
		if not combat_result.ok:
			return SessionStep.failed(_context.current_revision(), combat_result.error_code, combat_result.error_message)
		if not _event_payload(combat_result.events, &"monster_death_macro_requested").is_empty():
			return _start_session_death_macro(combat_result.events)
		if combat_result.completed:
			return _finish_direct_battle(combat_result.events)
		return _finish_completed(combat_result.events)
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_field_scroll(_workflow_context(), payload, _context.next_revision()))


func _cast_field_spell(payload: PlayerIntent.SpellPayload) -> SessionStep:
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_field_spell(_workflow_context(), payload, _context.next_revision()))


func _combat_action(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatActionPayload
	if payload.action == &"retreat":
		var retreat_probe: Variant = _context.rules.combat_flow.reactions.probe_character_retreat(_context.state.combat, _context.state.party.characters(), payload.actor_id)
		if not retreat_probe.allowed:
			return SessionStep.failed(_context.current_revision(), retreat_probe.reason, retreat_probe.reason_text)
		return _request_session_retreat(payload.actor_id, &"explicit", Vector2i(-100_000, -100_000))
	var result := CombatRewardsWorkflow.submit_action(_workflow_context(), payload)
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _set_combat_auto(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatAutoPayload
	if _context.state == null or _context.state.combat == null or _context.state.combat.completed:
		return SessionStep.failed(_context.current_revision(), &"combat_auto_unavailable", "Persistent Auto can be changed only during an active battle.")
	var character := _context.state.party.character_by_id(payload.character_id)
	if character == null or character.current_health <= 0:
		return SessionStep.failed(_context.current_revision(), &"invalid_combat_auto_character", "Persistent Auto requires a living party character.")
	var pending := _pending_interaction()
	if pending != null:
		if pending.kind != InteractionRequest.COMBAT or _context.session_interaction != null:
			return SessionStep.failed(_context.current_revision(), &"interaction_pending", "Persistent Auto cannot replace this pending interaction.")
		if _context.scenario_vm != null and _context.scenario_vm.pending_request() == pending:
			var response_body := InteractionResponse.CombatBody.new(&"set_auto", payload.character_id)
			response_body.enabled = payload.enabled
			return respond(InteractionResponse.new(pending.request_id, pending.kind, response_body))
	return _finish_combat_result(CombatRewardsWorkflow.set_persistent_auto(_workflow_context(), payload))


func _combat_move(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatMovePayload
	var edge_probe: Variant = _context.rules.combat_flow.reactions.probe_edge_retreat(_context.state.combat, payload.actor_id, payload.destination)
	if edge_probe.allowed:
		if not edge_probe.forced:
			return _request_session_retreat(payload.actor_id, &"edge", payload.destination)
		var forced_result := CombatRewardsWorkflow.move_character(_workflow_context(), payload, true)
		return _finish_combat_result(forced_result)
	var result := CombatRewardsWorkflow.move_character(_workflow_context(), payload, false)
	if not result.ok and result.error_code == &"combat_friendly_collision_choice_required":
		var target_id := _context.rules.combat_flow.reactions.friendly_collision_target_id(_context.state, payload.actor_id, payload.destination)
		if target_id.is_empty():
			return SessionStep.failed(_context.current_revision(), &"invalid_friendly_collision", "The adjacent ally is no longer available.")
		var collision := SessionContinuation.CombatBody.new()
		collision.battle_id = _context.state.combat.battle_id
		collision.actor_id = payload.actor_id
		collision.mode = &"friendly"
		collision.destination = payload.destination
		_set_continuation(SessionContinuation.combat_state(&"combat-friendly-collision", collision))
		_context.session_interaction = SessionInteractionFactory.friendly_collision("session.combat-friendly-collision:%d" % (_context.next_revision()))
		return _finish_waiting(_context.session_interaction, [])
	return _finish_combat_result(result)


func _finish_combat_result(result: CombatFlowResult) -> SessionStep:
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _request_session_retreat(actor_id: String, mode: StringName, destination: Vector2i) -> SessionStep:
	if _context.state.combat == null or _context.state.combat.active_actor_id() != actor_id:
		return SessionStep.failed(_context.current_revision(), &"invalid_combat_actor", "The active character cannot retreat.")
	var combat := SessionContinuation.CombatBody.new()
	combat.battle_id = _context.state.combat.battle_id
	combat.actor_id = actor_id
	combat.mode = mode
	combat.destination = destination
	_set_continuation(SessionContinuation.combat_state(&"combat-retreat-confirmation", combat))
	_context.session_interaction = SessionInteractionFactory.retreat_confirmation("session.combat-retreat:%d" % (_context.next_revision()))
	return _finish_waiting(_context.session_interaction, [])


func _begin_adventure() -> SessionStep:
	var result := LifecyclePartyWorkflow.begin_adventure(_workflow_context(), _pending_interaction() != null)
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	return _start_application_hook(ScenarioApplicationHooks.START_GAME, "begin-adventure", "", result.events)


func _finalize_character(_intent: PlayerIntent) -> SessionStep:
	var result := LifecyclePartyWorkflow.prepare_character_finalize(_workflow_context(), _pending_interaction() != null)
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.remaining_spell_points > 0:
		var request_id := "character-spells:%s:%d" % [result.character_id, _context.next_revision()]
		_set_continuation(SessionContinuation.character_spell_confirmation(result.character_id, result.remaining_spell_points))
		_context.session_interaction = SessionInteractionFactory.character_spell_confirmation(request_id, result.remaining_spell_points)
		return _finish_waiting(_context.session_interaction, [DomainEvent.new(&"character_spell_confirmation_requested", {"characterId": result.character_id, "remaining": result.remaining_spell_points})])
	return _commit_character_draft()


func _commit_character_draft(events: Array[DomainEvent] = []) -> SessionStep:
	var result := LifecyclePartyWorkflow.commit_character_draft(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, events)
	events.append_array(result.events)
	var request_id := "character-vault:%s:%d" % [result.character_id, _context.next_revision()]
	_set_continuation(SessionContinuation.character_vault_publication(result.character_id))
	_context.session_interaction = SessionInteractionFactory.character_vault_confirmation(request_id, result.character_name)
	events.append(DomainEvent.new(&"character_vault_confirmation_requested", {"characterId": result.character_id}))
	return _finish_waiting(_context.session_interaction, events)


func _search() -> SessionStep:
	var result := ExplorationTimeWorkflow.search(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	_set_post_time_continuation(result.map, "area-search-second", Vector2i.ZERO, result.check_random, result.timed_day, _context.state.party.coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _context.session_continuation.copy())


func _toggle_search() -> SessionStep:
	return _commit_workflow_result(ExplorationTimeWorkflow.toggle_search(_workflow_context()))


func _turn_dungeon(delta: int) -> SessionStep:
	return _commit_workflow_result(ExplorationTimeWorkflow.turn_dungeon(_workflow_context(), delta))


func _use_torch() -> SessionStep:
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_classic_torch(_workflow_context(), _context.next_revision()))


func _contextual_encounter() -> SessionStep:
	_ensure_coordinators()
	var result: SessionCoordinatorResult = _exploration_coordinator.begin_contextual_encounter()
	return _commit_coordinator_result(result)


func _move(direction: Vector2i, aligns_dungeon_heading: bool = false) -> SessionStep:
	var movement := _context.content.world.probe_movement(_context.state.party.map_id, _context.state.party.coordinate, direction, _context.state.world, _context.state.party_in_boat)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return SessionStep.failed(_context.current_revision(), &"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	var fatigue_warning := ExplorationTimeWorkflow.movement_fatigue_warning(_workflow_context())
	if fatigue_warning != null:
		return _finish_completed([fatigue_warning])
	var preceding_events: Array[DomainEvent] = []
	if aligns_dungeon_heading:
		var heading_result := ExplorationTimeWorkflow.align_dungeon_heading_for_overhead_move(_workflow_context(), direction)
		if not heading_result.ok:
			return _finish_failed(heading_result.error_code, heading_result.error_message, heading_result.events)
		preceding_events.append_array(heading_result.events)
	if _context.state.bank_available and SessionInteractionFactory.has_pooled_wealth(_context.state.party):
		var banked := _context.state.party.pooled_wealth.to_data()
		_context.rules.economy.pool_to_bank(_context.state.party)
		_context.state.bank_available = false
		preceding_events.append(DomainEvent.new(&"pooled_wealth_banked_before_movement", {"wealth": banked, "direction": [direction.x, direction.y]}))
		return _move_after_pooled_wealth(direction, preceding_events)
	if not _context.state.bank_available and SessionInteractionFactory.has_pooled_wealth(_context.state.party):
		_set_continuation(SessionContinuation.pooled_wealth_departure(&"warning", direction))
		_context.session_interaction = SessionInteractionFactory.pooled_wealth_departure_warning("pooled-wealth-departure:%d" % (_context.next_revision()))
		preceding_events.append_array([
			DomainEvent.new(&"pooled_wealth_departure_warning", {"wealth": _context.state.party.pooled_wealth.to_data(), "direction": [direction.x, direction.y]}),
			DomainEvent.new(&"sound_requested", {"soundId": 20005, "waitForCompletion": false, "stopExisting": true, "source": "classic-pooled-wealth-departure-question"}),
		])
		return _finish_waiting(_context.session_interaction, preceding_events)
	return _move_after_pooled_wealth(direction, preceding_events)


func _move_after_pooled_wealth(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.move_after_pooled_wealth(direction, preceding_events))


func _set_post_time_continuation(map: MapDefinition, resume_kind: String, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> void:
	_ensure_coordinators()
	_exploration_coordinator.set_post_time_continuation(map, resume_kind, direction, check_random, timed_day, timed_coordinate)
	_release_coordinators()


func _continue_post_time(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.continue_post_time(events))


func _complete_post_time(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.complete_post_time(events))


func _continue_timed_encounters(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.continue_timed_encounters(events))


func _apply_pending_midnight_recovery(events: Array[DomainEvent]) -> void:
	_ensure_coordinators()
	_exploration_coordinator.apply_pending_midnight_recovery(events)
	_release_coordinators()


func _rebase_post_time_location() -> bool:
	_ensure_coordinators()
	var result: bool = _exploration_coordinator.rebase_post_time_location()
	_release_coordinators()
	return result


func _timed_encounter_requirements_met(encounter: TimedEncounterDefinition, map: MapDefinition) -> bool:
	_ensure_coordinators()
	var result: bool = _exploration_coordinator.timed_encounter_requirements_met(encounter, map)
	_release_coordinators()
	return result


func _set_post_move_continuation(map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> void:
	_ensure_coordinators()
	_exploration_coordinator.set_post_move_continuation(map, coordinate, destination_depth)
	_release_coordinators()


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.continue_post_move(events))


func _continue_exploration_continuation(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.continue_exploration_continuation(events))


func _start_application_hook(hook: StringName, resume_kind: StringName, service_id: String, preceding_events: Array[DomainEvent], suspended: SessionContinuation.ApplicationBody = null) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.start_application_hook(hook, resume_kind, service_id, preceding_events, suspended))


func _continue_application_hook(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.continue_application_hook(events))


func _begin_scenario_handoff(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.begin_scenario_handoff(result, events))


func _resume_scenario_party_defeat(saved: ScenarioVmSnapshot, suspended_owner: SessionContinuation, vm_handoff: ScenarioVmHandoff, events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.resume_scenario_party_defeat(saved, suspended_owner, vm_handoff, events))


func _apply_trigger_destination(trigger: TriggerDefinition, events: Array[DomainEvent], allow_destination: bool) -> bool:
	_ensure_coordinators()
	var result: bool = _scenario_coordinator.apply_trigger_destination(trigger, events, allow_destination)
	_release_coordinators()
	return result


func _finalize_completed_trigger(trigger: TriggerDefinition, events: Array[DomainEvent]) -> void:
	_ensure_coordinators()
	_scenario_coordinator.finalize_completed_trigger(trigger, events)
	_release_coordinators()


func _events_have(events: Array[DomainEvent], kind: StringName) -> bool:
	return _context.events_have(events, kind)


func _events_keep_trigger(events: Array[DomainEvent], trigger_id: String) -> bool:
	_ensure_coordinators()
	var result: bool = _scenario_coordinator.events_keep_trigger(events, trigger_id)
	_release_coordinators()
	return result


func _event_payload(events: Array[DomainEvent], kind: StringName) -> Dictionary:
	return _context.event_payload(events, kind)


func _start_session_death_macro(preceding_events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.start_session_death_macro(preceding_events))


func _continue_session_death_macro(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.continue_session_death_macro(events))


func _append_session_battle_after_message(battle_id: String, events: Array[DomainEvent]) -> void:
	_ensure_coordinators()
	_scenario_coordinator.append_session_battle_after_message(battle_id, events)
	_release_coordinators()


func _finish_direct_battle(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.finish_direct_battle(events))


func _finish_direct_battle_recovery(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.finish_direct_battle_recovery(events))


func _finish_direct_battle_without_rewards(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.finish_direct_battle_without_rewards(events))


func _begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.begin_direct_battle_reward(events))


func _finish_after_direct_battle(events: Array[DomainEvent], return_continuation: SessionContinuation, battle_outcome: StringName) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_scenario_coordinator.finish_after_direct_battle(events, return_continuation, battle_outcome))


func _continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.continue_random_regions(map, events))


func _complete_random_program(events: Array[DomainEvent]) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_exploration_coordinator.complete_random_program(events))


func _finish_completed(events: Array[DomainEvent]) -> SessionStep:
	_record_current_visibility()
	_context.set_revision(_context.next_revision())
	return SessionStep.completed(_context.current_revision(), events)


func _commit_workflow_result(result: SessionWorkflowResult) -> SessionStep:
	if result == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_workflow_result", "The session workflow returned no result.")
	return _finish_completed(result.events) if result.ok else SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)


func _finish_magic_workflow(result: SessionWorkflowResult) -> SessionStep:
	if result == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "completed")
	return _finish_completed(result.events)


func _finish_magic_transition(result: InventoryMagicServicesWorkflow.MagicTransitionResult) -> SessionStep:
	if result == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return SessionStep.failed(_context.current_revision(), result.error_code, result.error_message)
	if result.completed:
		return _finish_magic_workflow(SessionWorkflowResult.completed(result.events)) if result.process_age_updates else _finish_completed(result.events)
	if result.continuation == null or result.continuation.is_empty() or result.interaction == null:
		return SessionStep.failed(_context.current_revision(), &"invalid_workflow_result", "The magic workflow returned an incomplete interaction transition.")
	_set_continuation(result.continuation)
	_context.session_interaction = result.interaction
	return _finish_waiting(_context.session_interaction, result.events)


func _finish_waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionStep:
	_record_current_visibility()
	_context.set_revision(_context.next_revision())
	return SessionStep.waiting(_context.current_revision(), request, events)


func _finish_failed(code: StringName, message: String, events: Array[DomainEvent]) -> SessionStep:
	_context.set_revision(_context.next_revision())
	return SessionStep.failed(_context.current_revision(), code, message, events)


func _record_current_visibility() -> void:
	if not _started or _context.content == null or _context.state == null:
		return
	var map := _context.content.world.map_by_id(_context.state.party.map_id)
	if map == null or not map.uses_los:
		return
	var wizard_eye := _context.state.party.conditions.is_active(ConditionRules.PARTY_WIZARDS_EYE)
	var visible_coordinates := map.topology.exploration_visible_cells(_context.state.party.coordinate, _context.state.world, true, wizard_eye)
	_context.state.world.mark_seen_many(map.id, visible_coordinates)
	_view_projector.record_visibility(map.id, _context.state.party.coordinate, visible_coordinates, _context.state.world.topology_revision(), wizard_eye)


func _pending_interaction() -> InteractionRequest:
	if _context.session_interaction != null:
		return _context.session_interaction
	return _context.scenario_vm.pending_request() if _context.scenario_vm != null else null


func _respond_session_interaction(response: InteractionResponse) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_response_coordinator.respond_session_interaction(response))


func _service_action(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ServicePayload
	if payload.action != &"enter":
		return SessionStep.failed(_context.current_revision(), &"unknown_service_action", "Only entering an available service is implemented through this intent.")
	if payload.service_id == "realmz.service.temple":
		if not _context.state.temple_available:
			return SessionStep.failed(_context.current_revision(), &"service_unavailable", "The selected temple is not available at this location.")
		return _start_application_hook(ScenarioApplicationHooks.TEMPLE, "service", payload.service_id, [])
	elif payload.service_id == "realmz.service.bank":
		return _open_contextual_service(payload.service_id, [])
	elif payload.service_id == _context.state.active_shop_id:
		if payload.service_id.is_empty() or _context.content.shop_by_id(payload.service_id) == null:
			return SessionStep.failed(_context.current_revision(), &"service_unavailable", "The selected shop is not available at this location.")
		return _start_application_hook(ScenarioApplicationHooks.SHOP, "service", payload.service_id, [])
	else:
		return SessionStep.failed(_context.current_revision(), &"service_unavailable", "The selected service is not available at this location.")


func _open_contextual_service(service_id: String, preceding_events: Array[DomainEvent]) -> SessionStep:
	var request_id := "service:%s:%d" % [service_id, _context.current_revision()]
	var operation: ScenarioRuntimeOperationResult
	if service_id == "realmz.service.temple":
		operation = _context.runtime_api.request_available_temple(request_id)
	elif service_id == "realmz.service.bank":
		operation = _context.runtime_api.request_available_bank(request_id)
	elif service_id == _context.state.active_shop_id:
		operation = _context.runtime_api.request_available_shop(request_id)
	else:
		return _finish_failed(&"service_unavailable", "The selected service is not available at this location.", preceding_events)
	operation.events = preceding_events + operation.events
	return _begin_runtime_service(service_id, operation)


func _money_action(intent: PlayerIntent) -> SessionStep:
	return _commit_workflow_result(SessionMoneyWorkflow.perform(_workflow_context(), intent.payload as PlayerIntent.MoneyPayload))


func _begin_runtime_service(service_id: String, operation: ScenarioRuntimeOperationResult) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_response_coordinator.begin_runtime_service(service_id, operation))


func _finish_with_age_updates(events: Array[DomainEvent], resume_kind: StringName, resume_continuation: SessionContinuation = null) -> SessionStep:
	_ensure_coordinators()
	return _commit_coordinator_result(_response_coordinator.finish_with_age_updates(events, resume_kind, resume_continuation))
