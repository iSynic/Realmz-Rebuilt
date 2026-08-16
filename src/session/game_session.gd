class_name GameSession
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _scenario_vm: ScenarioVm
var _scenario_action_state: ScenarioActionState
var _runtime_api: RealmzRuntimeApi
var _session_continuation: SessionContinuation = SessionContinuation.new()
var _battle_return_continuation: SessionContinuation = SessionContinuation.new()
var _session_interaction: InteractionRequest
var _started: bool = false
var _view_revision: int = 0
var _view_projector := SessionViewProjector.new()


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_view_revision, &"session_already_started", "The session has already started.")
	if content == null or content.scenario == null:
		return SessionStep.failed(_view_revision, &"invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_view_revision, &"invalid_start_location", "The package start location is unavailable.")
	var starting_characters: Array[CharacterState] = []
	var game_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, starting_characters), RealmzClock.new())
	game_state.world.mark_visited(content.start_map_id, content.start_coordinate)
	var random_source := RealmzRng.new(initial_seed)
	var action_state := ScenarioActionState.new()
	var scenario_vm := ScenarioVm.new()
	scenario_vm.configure(content.scenario)
	_content = content
	_state = game_state
	_rng = random_source
	_rules = RealmzRules.new()
	_scenario_action_state = action_state
	_scenario_vm = scenario_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	_session_continuation.clear()
	_battle_return_continuation.clear()
	_session_interaction = null
	_view_projector.clear()
	_started = true
	_view_revision = 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SessionSnapshot) -> SessionStep:
	var result := SessionRestoreValidator.validate(content, save_envelope)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	var candidate := result.candidate
	_content = content
	_state = candidate.state
	_rng = candidate.rng
	_rules = candidate.rules
	_scenario_action_state = candidate.scenario_action_state
	_scenario_vm = candidate.scenario_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	_session_continuation = candidate.continuation
	_battle_return_continuation = candidate.battle_return_continuation
	_session_interaction = candidate.session_interaction
	_view_projector.clear()
	_view_revision = candidate.view_revision
	_started = true
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_restored")])


func close() -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "There is no active session to close.")
	var pending := _pending_interaction()
	if (_scenario_vm.is_active() and pending == null) or (pending != null and pending.kind != InteractionRequest.COMBAT):
		return SessionStep.failed(_view_revision, &"session_not_committed", "The session can close only at a committed boundary.")
	# Castle permits End Adventure during combat after confirmation. Abandon the
	# interrupted combat/VM interaction before the synchronous Global hooks run.
	if pending != null:
		_session_continuation.clear()
		_battle_return_continuation.clear()
		_session_interaction = null
		_scenario_vm = ScenarioVm.new()
		_scenario_vm.configure(_content.scenario)
		_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	return _start_application_hook(ScenarioApplicationHooks.END_ADVENTURE, "end-adventure", "", [])


func _commit_close(events: Array[DomainEvent], reason: String) -> SessionStep:
	var campaign_id := _content.campaign_id
	_session_continuation.clear()
	_battle_return_continuation.clear()
	_session_interaction = null
	_runtime_api = null
	_scenario_vm = null
	_scenario_action_state = null
	_rules = null
	_rng = null
	_state = null
	_content = null
	_view_projector.clear()
	_started = false
	_view_revision += 1
	var completed_events: Array[DomainEvent] = []
	completed_events.assign(events)
	completed_events.append(DomainEvent.new(&"session_ended", {"campaignId": campaign_id, "reason": reason}))
	return SessionStep.completed(_view_revision, completed_events)


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	if intent == null:
		return SessionStep.failed(_view_revision, &"invalid_intent", "A typed player intent is required.")
	if not intent.is_valid():
		return SessionStep.failed(_view_revision, &"invalid_intent_payload", "The player intent payload does not match its kind.")
	if intent.kind == PlayerIntent.Kind.SET_COMBAT_AUTO:
		return _set_combat_auto(intent)
	if _pending_interaction() != null or _scenario_vm.is_active():
		return SessionStep.failed(_view_revision, &"interaction_pending", "Respond to the pending interaction first.")
	if not _state.party_setup_completed and intent.kind not in [PlayerIntent.Kind.CREATE_PARTY, PlayerIntent.Kind.BEGIN_ADVENTURE, PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT, PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS, PlayerIntent.Kind.FINALIZE_CHARACTER, PlayerIntent.Kind.REMOVE_PARTY_MEMBER, PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS]:
		return SessionStep.failed(_view_revision, &"party_setup_incomplete", "Finish party setup before beginning the adventure.")
	if _state.combat != null and not _state.combat.completed and intent.kind not in [PlayerIntent.Kind.USE_ITEM, PlayerIntent.Kind.USE_ITEM_ON_TARGET, PlayerIntent.Kind.CAST_SPELL, PlayerIntent.Kind.CHOOSE_COMBAT_ACTION, PlayerIntent.Kind.COMBAT_MOVE]:
		return SessionStep.failed(_view_revision, &"battle_in_progress", "Resolve the active battle before returning to exploration.")
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			return _move((intent.payload as PlayerIntent.MovePayload).direction)
		PlayerIntent.Kind.SEARCH:
			return _search()
		PlayerIntent.Kind.CAMP:
			return _camp()
		PlayerIntent.Kind.REST:
			return _rest()
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
			return SessionStep.failed(_view_revision, &"intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func respond(response: InteractionResponse) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	var pending := _pending_interaction()
	if pending == null:
		return SessionStep.failed(_view_revision, &"no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != pending.request_id:
		return SessionStep.failed(_view_revision, &"interaction_mismatch", "The response does not match the pending request.")
	if not response.is_supported_kind():
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "The response payload does not match its interaction kind.")
	if _session_interaction != null:
		return _respond_session_interaction(response)
	var result := _scenario_vm.resume(response, _runtime_api)
	var events: Array[DomainEvent] = []
	events.append_array(result.events)
	if _session_continuation.kind == &"application-hook" and _events_have(result.events, &"party_revived"):
		_session_continuation.application().party_revived = true
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.WAITING:
		if _session_continuation.kind == &"post-clock" and not _session_continuation.exploration().active_timed_program_id.is_empty() and not _rebase_post_time_location():
			_session_continuation.clear()
			return _finish_failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
		return _finish_waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if not _session_continuation.is_empty():
		if _session_continuation.kind == &"combat-death-macro":
			return _continue_session_death_macro(events)
		return _continue_exploration_continuation(events)
	return _finish_completed(events)


func view() -> GameView:
	return _view_projector.project(_workflow_context(), _pending_interaction(), _view_revision, _started)


func _workflow_context(events: Array[DomainEvent] = []) -> SessionWorkflowContext:
	return SessionWorkflowContext.new(_content, _state, _rules, _rng, _scenario_vm, _scenario_action_state, events)


func _set_continuation(continuation: SessionContinuation) -> void:
	assert(continuation != null and not continuation.is_empty(), "A live continuation must have a typed body")
	_session_continuation = continuation


func snapshot() -> SessionSnapshot:
	if not _started or (_scenario_vm.is_active() and _scenario_vm.pending_request() == null):
		return null
	var state := GameState.from_data(_state.to_data())
	var vm_state := ScenarioVmSnapshot.from_data(_scenario_vm.snapshot().to_data())
	var action_state := ScenarioActionState.from_data(_scenario_action_state.to_data())
	var interaction: InteractionRequest = null
	if _session_interaction != null:
		interaction = InteractionRequest.from_data(_session_interaction.to_data())
	if state == null or vm_state == null or action_state == null or _session_interaction != null and interaction == null:
		return null
	var continuation := null if _session_continuation.is_empty() else SessionContinuation.from_data(_session_continuation.to_data())
	var battle_return := null if _battle_return_continuation.is_empty() else SessionContinuation.from_data(_battle_return_continuation.to_data())
	return SessionSnapshot.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, state, _rng.snapshot(), vm_state, action_state, continuation, battle_return, interaction)


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _scenario_vm == null else _scenario_vm.trace()


func _camp() -> SessionStep:
	var result := ExplorationTimeWorkflow.toggle_camp(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if not _state.party_camping and result.timed_day == 0:
		return _finish_with_age_updates(result.events, "completed")
	_set_post_time_continuation(result.map, "completed", Vector2i.ZERO, result.check_random, result.timed_day, _state.party.coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _session_continuation.copy())


func _rest() -> SessionStep:
	var result := ExplorationTimeWorkflow.rest(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	_set_post_time_continuation(result.map, "completed", Vector2i.ZERO, result.check_random, result.timed_day, _state.party.coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _session_continuation.copy())


func _use_item(intent: PlayerIntent) -> SessionStep:
	var actor_id := ""
	var item_id := ""
	var target_id := ""
	var target_ids: Array[String] = []
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
	var character := _state.party.character_by_id(actor_id)
	if character == null:
		character = InventoryMagicServicesWorkflow.item_owner(_workflow_context(), item_id)
	var instance := _item_instance(character, item_id)
	var item: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or item == null:
		return SessionStep.failed(_view_revision, &"unknown_item_instance", "The selected character does not carry that item instance.")
	if _state.combat != null and not _state.combat.completed:
		var combat_result := _rules.combat_flow.use_spell_item(_state, _content, character.id, target_id, instance.id, _rng)
		if not combat_result.ok:
			return SessionStep.failed(_view_revision, combat_result.error_code, combat_result.error_message)
		if not CharacterAgingResult.update_payloads(combat_result.events).is_empty():
			return _finish_with_age_updates(combat_result.events, "combat-monster-turns")
		if not _event_payload(combat_result.events, &"monster_death_macro_requested").is_empty():
			return _start_session_death_macro(combat_result.events)
		if combat_result.completed:
			return _finish_direct_battle(combat_result.events)
		return _finish_completed(combat_result.events)
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_field_spell_item(_workflow_context(), actor_id, item_id, target_id, target_ids, _view_revision + 1))


func _request_drop_item(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ItemActionPayload
	var character := _state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _rules.inventory.classic_drop_probe(character, instance)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_drop", probe.reason)
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.instance_id = instance.id
	_set_continuation(SessionContinuation.targeting_selection(&"drop-item-confirmation", targeting))
	var display_name := definition.name if instance.identified else definition.unidentified_name
	_session_interaction = SessionInteractionFactory.drop_item_confirmation("session.drop-item:%s:%d" % [instance.id, _view_revision + 1], display_name)
	return _finish_waiting(_session_interaction, [DomainEvent.new(&"item_drop_requested", {"characterId": character.id, "instanceId": instance.id})])


func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null or instance_id.is_empty():
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


func _cast_spell(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.SpellPayload
	if payload.operation == &"make-scroll":
		return _commit_workflow_result(InventoryMagicServicesWorkflow.make_scroll(_workflow_context(), payload))
	if payload.operation == &"use-scroll":
		return _use_scroll(payload)
	if _state.combat == null or _state.combat.completed:
		return _cast_field_spell(payload)
	var result := _rules.combat_flow.cast_spell(_state, _content, payload.caster_id, payload.target_id, payload.spell_id, payload.power, _rng, payload.coordinate, payload.rotation, payload.target_ids)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _use_scroll(payload: PlayerIntent.SpellPayload) -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		var combat_result := _rules.combat_flow.use_combat_scroll(_state, _content, payload.caster_id, payload.scroll_slot, payload.target_id, _rng, payload.coordinate, payload.rotation, payload.target_ids)
		if not combat_result.ok:
			return SessionStep.failed(_view_revision, combat_result.error_code, combat_result.error_message)
		if not _event_payload(combat_result.events, &"monster_death_macro_requested").is_empty():
			return _start_session_death_macro(combat_result.events)
		if combat_result.completed:
			return _finish_direct_battle(combat_result.events)
		return _finish_completed(combat_result.events)
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_field_scroll(_workflow_context(), payload, _view_revision + 1))


func _cast_field_spell(payload: PlayerIntent.SpellPayload) -> SessionStep:
	return _finish_magic_transition(InventoryMagicServicesWorkflow.begin_field_spell(_workflow_context(), payload, _view_revision + 1))


func _combat_action(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatActionPayload
	if payload.action == &"retreat":
		var retreat_probe: Variant = _rules.combat_flow.probe_character_retreat(_state.combat, _state.party.characters(), payload.actor_id)
		if not retreat_probe.allowed:
			return SessionStep.failed(_view_revision, retreat_probe.reason, retreat_probe.reason_text)
		return _request_session_retreat(payload.actor_id, &"explicit", Vector2i(-100_000, -100_000))
	var result := CombatRewardsWorkflow.submit_action(_workflow_context(), payload)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _set_combat_auto(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatAutoPayload
	if _state == null or _state.combat == null or _state.combat.completed:
		return SessionStep.failed(_view_revision, &"combat_auto_unavailable", "Persistent Auto can be changed only during an active battle.")
	var character := _state.party.character_by_id(payload.character_id)
	if character == null or character.current_health <= 0:
		return SessionStep.failed(_view_revision, &"invalid_combat_auto_character", "Persistent Auto requires a living party character.")
	var pending := _pending_interaction()
	if pending != null:
		if pending.kind != InteractionRequest.COMBAT or _scenario_vm == null or not _scenario_vm.is_active():
			return SessionStep.failed(_view_revision, &"interaction_pending", "Persistent Auto cannot replace this pending interaction.")
		var response_body := InteractionResponse.CombatBody.new(&"set_auto", payload.character_id)
		response_body.enabled = payload.enabled
		return respond(InteractionResponse.new(pending.request_id, pending.kind, response_body))
	return _finish_combat_result(CombatRewardsWorkflow.set_persistent_auto(_workflow_context(), payload))


func _combat_move(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatMovePayload
	var edge_probe: Variant = _rules.combat_flow.probe_edge_retreat(_state.combat, payload.actor_id, payload.destination)
	if edge_probe.allowed:
		if not edge_probe.forced:
			return _request_session_retreat(payload.actor_id, &"edge", payload.destination)
		var forced_result := CombatRewardsWorkflow.move_character(_workflow_context(), payload, true)
		return _finish_combat_result(forced_result)
	var result := CombatRewardsWorkflow.move_character(_workflow_context(), payload, false)
	return _finish_combat_result(result)


func _finish_combat_result(result: CombatFlowResult) -> SessionStep:
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _request_session_retreat(actor_id: String, mode: StringName, destination: Vector2i) -> SessionStep:
	if _state.combat == null or _state.combat.active_actor_id() != actor_id:
		return SessionStep.failed(_view_revision, &"invalid_combat_actor", "The active character cannot retreat.")
	var combat := SessionContinuation.CombatBody.new()
	combat.battle_id = _state.combat.battle_id
	combat.actor_id = actor_id
	combat.mode = mode
	combat.destination = destination
	_set_continuation(SessionContinuation.combat_state(&"combat-retreat-confirmation", combat))
	_session_interaction = SessionInteractionFactory.retreat_confirmation("session.combat-retreat:%d" % (_view_revision + 1))
	return _finish_waiting(_session_interaction, [])


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
		var request_id := "character-spells:%s:%d" % [result.character_id, _view_revision + 1]
		_set_continuation(SessionContinuation.character_spell_confirmation(result.character_id, result.remaining_spell_points))
		_session_interaction = SessionInteractionFactory.character_spell_confirmation(request_id, result.remaining_spell_points)
		return _finish_waiting(_session_interaction, [DomainEvent.new(&"character_spell_confirmation_requested", {"characterId": result.character_id, "remaining": result.remaining_spell_points})])
	return _commit_character_draft()


func _commit_character_draft(events: Array[DomainEvent] = []) -> SessionStep:
	var result := LifecyclePartyWorkflow.commit_character_draft(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, events)
	events.append_array(result.events)
	var request_id := "character-vault:%s:%d" % [result.character_id, _view_revision + 1]
	_set_continuation(SessionContinuation.character_vault_publication(result.character_id))
	_session_interaction = SessionInteractionFactory.character_vault_confirmation(request_id, result.character_name)
	events.append(DomainEvent.new(&"character_vault_confirmation_requested", {"characterId": result.character_id}))
	return _finish_waiting(_session_interaction, events)


func _search() -> SessionStep:
	var result := ExplorationTimeWorkflow.search(_workflow_context())
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	return _finish_with_age_updates(result.events, "completed")


func _move(direction: Vector2i) -> SessionStep:
	var movement := _content.world.probe_movement(_state.party.map_id, _state.party.coordinate, direction, _state.world)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return SessionStep.failed(_view_revision, &"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	if _state.bank_available and SessionInteractionFactory.has_pooled_wealth(_state.party):
		var banked := _state.party.pooled_wealth.to_data()
		_rules.economy.pool_to_bank(_state.party)
		_state.bank_available = false
		return _move_after_pooled_wealth(direction, [DomainEvent.new(&"pooled_wealth_banked_before_movement", {"wealth": banked, "direction": [direction.x, direction.y]})])
	if not _state.bank_available and SessionInteractionFactory.has_pooled_wealth(_state.party):
		_set_continuation(SessionContinuation.pooled_wealth_departure(&"warning", direction))
		_session_interaction = SessionInteractionFactory.pooled_wealth_departure_warning("pooled-wealth-departure:%d" % (_view_revision + 1))
		return _finish_waiting(_session_interaction, [
			DomainEvent.new(&"pooled_wealth_departure_warning", {"wealth": _state.party.pooled_wealth.to_data(), "direction": [direction.x, direction.y]}),
			DomainEvent.new(&"sound_requested", {"soundId": 20005, "waitForCompletion": false, "stopExisting": true, "source": "classic-pooled-wealth-departure-question"}),
		])
	return _move_after_pooled_wealth(direction)


func _move_after_pooled_wealth(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionStep:
	var result := ExplorationTimeWorkflow.depart_camp_for_movement(_workflow_context(), direction, preceding_events) if _state.party_camping else ExplorationTimeWorkflow.commit_move(_workflow_context(), direction, preceding_events)
	return _finish_exploration_movement(result)


func _finish_exploration_movement(result: ExplorationTimeWorkflow.MovementTransitionResult) -> SessionStep:
	if not result.ok:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if not result.post_clock:
		return _finish_completed(result.events)
	_set_post_time_continuation(result.map, result.resume_kind, result.direction, result.check_random, result.timed_day, result.timed_coordinate)
	return _finish_with_age_updates(result.events, &"post-clock", _session_continuation.copy())


func _set_post_time_continuation(map: MapDefinition, resume_kind: String, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> void:
	_set_continuation(ExplorationTimeWorkflow.post_time_continuation(_workflow_context(), map, StringName(resume_kind), direction, check_random, timed_day, timed_coordinate))


func _continue_post_time(events: Array[DomainEvent]) -> SessionStep:
	var exploration := _session_continuation.exploration()
	if _session_continuation.kind != &"post-clock" or exploration == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var active_timed_program_id := exploration.active_timed_program_id
	if not active_timed_program_id.is_empty() and not _rebase_post_time_location():
		_session_continuation.clear()
		return _finish_failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	var map := _content.world.map_by_id(exploration.map_id)
	if map == null or _state.party.map_id != map.id or _state.party.coordinate != exploration.coordinate:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	if not active_timed_program_id.is_empty():
		exploration.active_timed_program_id = ""
	var timed_step := _continue_timed_encounters(events)
	if timed_step != null:
		return timed_step
	map = _content.world.map_by_id(exploration.map_id)
	if map == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_timed_encounter_location", "Timed encounter continuation references an unavailable map.", events)
	var active_program_id := exploration.active_random_program_id
	if not active_program_id.is_empty():
		exploration.active_random_program_id = ""
		return _complete_post_time(events)
	if exploration.check_random and exploration.resume_kind != &"post-move":
		var random_step := _continue_random_regions(map, events)
		if random_step != null:
			return random_step
	return _complete_post_time(events)


func _complete_post_time(events: Array[DomainEvent]) -> SessionStep:
	var exploration := _session_continuation.exploration()
	if _session_continuation.kind != &"post-clock" or exploration == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	var resume_kind := exploration.resume_kind
	var direction := exploration.direction
	_session_continuation.clear()
	if resume_kind == &"move":
		return _finish_exploration_movement(ExplorationTimeWorkflow.commit_move(_workflow_context(), direction, events))
	if resume_kind == &"post-move":
		var map := _content.world.map_by_id(_state.party.map_id)
		_set_post_move_continuation(map, _state.party.coordinate)
		return _continue_post_move(events)
	if resume_kind == &"completed":
		return _finish_completed(events)
	return _finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation has no valid completion path.", events)


func _continue_timed_encounters(events: Array[DomainEvent]) -> SessionStep:
	var exploration := _session_continuation.exploration()
	if _session_continuation.kind != &"post-clock" or exploration == null:
		return _finish_failed(&"invalid_session_continuation", "Timed encounters require a post-clock continuation.", events)
	var timed_day := exploration.timed_day
	if timed_day <= 0:
		return null
	var encounters := _content.timed_encounters()
	while exploration.timed_encounter_index < encounters.size():
		var index := exploration.timed_encounter_index
		var encounter := encounters[index]
		exploration.timed_encounter_index = index + 1
		var effective := _state.timed_encounter_override(encounter.id)
		var effective_day := int(effective.get("day", encounter.day))
		if effective_day != timed_day:
			continue
		var increment := int(effective.get("increment", encounter.increment))
		effective["day"] = effective_day + increment
		_state.set_timed_encounter_override(encounter.id, effective)
		events.append(DomainEvent.new(&"timed_encounter_advanced", {"encounterId": encounter.id, "day": effective_day, "nextDay": effective["day"], "source": "classic-midnight"}))
		var chance := int(effective.get("percent", encounter.chance_percent))
		var roll := _rng.draw(100, StringName("timed-encounter.%d" % encounter.id))
		var map := _content.world.map_by_id(_state.party.map_id)
		if map == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_timed_encounter_location", "Timed encounter eligibility references an unavailable map.", events)
		var eligible := roll <= chance and _timed_encounter_requirements_met(encounter, map)
		events.append(DomainEvent.new(&"timed_encounter_checked", {"encounterId": encounter.id, "roll": roll, "chancePercent": chance, "eligible": eligible}))
		if not eligible:
			continue
		_apply_pending_midnight_recovery(events)
		var trigger := _content.trigger_by_map_record(map.id, encounter.trigger_record_index)
		if trigger == null:
			_session_continuation.clear()
			return _finish_failed(&"unknown_timed_encounter_trigger", "Timed Encounter %d references unavailable Action Point record %d on map '%s'." % [encounter.id, encounter.trigger_record_index, map.id], events)
		exploration.active_timed_program_id = trigger.program_id
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "triggerId": trigger.id, "programId": trigger.program_id}))
		var context := ScenarioExecutionContext.trigger(&"action", trigger.id, map.id, exploration.timed_check_coordinate, true).set_timed_encounter(encounter.id)
		var started := _scenario_vm.start_program(trigger.program_id, context)
		if started.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(started.error_code, started.error_message, events)
		var result := _scenario_vm.run(_runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			if not _rebase_post_time_location():
				_session_continuation.clear()
				return _finish_failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
			return _finish_waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(result.error_code, result.error_message, events)
		exploration.active_timed_program_id = ""
		if not _rebase_post_time_location():
			_session_continuation.clear()
			return _finish_failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	_apply_pending_midnight_recovery(events)
	exploration.timed_day = 0
	return null


func _apply_pending_midnight_recovery(events: Array[DomainEvent]) -> void:
	ExplorationTimeWorkflow.apply_pending_midnight_recovery(_workflow_context(), _session_continuation.exploration(), events)


func _rebase_post_time_location() -> bool:
	return ExplorationTimeWorkflow.rebase_post_time_location(_workflow_context(), _session_continuation)


func _timed_encounter_requirements_met(encounter: TimedEncounterDefinition, map: MapDefinition) -> bool:
	return ExplorationTimeWorkflow.timed_encounter_requirements_met(_workflow_context(), encounter, map, _session_continuation.exploration())


func _set_post_move_continuation(map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> void:
	_set_continuation(ExplorationTimeWorkflow.post_move_continuation(_workflow_context(), map, coordinate, destination_depth))


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	var exploration := _session_continuation.exploration()
	if _session_continuation.kind != &"post-move" or exploration == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	if _events_have(events, &"destination_trigger_recheck_requested") and exploration.action_point_destination_depth == 0:
		var requested_map := _content.world.map_by_id(_state.party.map_id)
		if requested_map == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
		_set_post_move_continuation(requested_map, _state.party.coordinate, 1)
		exploration = _session_continuation.exploration()
	var map := _content.world.map_by_id(exploration.map_id)
	var coordinate := exploration.coordinate
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	var active_random_program_id := exploration.active_random_program_id
	if not active_random_program_id.is_empty():
		_session_continuation.clear()
		return _finish_completed(events)
	var active_trigger_id := exploration.active_trigger_id
	if not active_trigger_id.is_empty():
		var completed_trigger := _content.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		_finalize_completed_trigger(completed_trigger, events)
		if _apply_trigger_destination(completed_trigger, events, exploration.action_point_destination_depth == 0):
			var destination_map := _content.world.map_by_id(_state.party.map_id)
			_set_post_move_continuation(destination_map, _state.party.coordinate, 1)
			return _continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = exploration.trigger_ids.size()
	var trigger_ids := exploration.trigger_ids
	while exploration.trigger_index < trigger_ids.size():
		var trigger_index := exploration.trigger_index
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger := _content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _state.world.trigger_is_disabled(trigger_id):
			exploration.trigger_index = trigger_ids.size()
			break
		var trigger_chance := _state.world.trigger_chance(trigger.id, trigger.chance_percent)
		if trigger_chance < 1:
			exploration.trigger_index = trigger_ids.size()
			break
		if trigger_chance < 100:
			var chance_roll := _rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger_chance:
				exploration.trigger_index = trigger_ids.size()
				break
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		exploration.active_trigger_id = trigger.id
		var started := _scenario_vm.start_program(trigger.program_id, ScenarioExecutionContext.trigger(&"action", trigger.id, map.id, coordinate, true))
		if started.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(started.error_code, started.error_message, events)
		var result := _scenario_vm.run(_runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return _begin_scenario_handoff(result, events)
		if result.state == ScenarioVmResult.State.WAITING:
			return _finish_waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(result.error_code, result.error_message, events)
		_finalize_completed_trigger(trigger, events)
		if _events_have(result.events, &"destination_trigger_recheck_requested"):
			var requested_map := _content.world.map_by_id(_state.party.map_id)
			if requested_map == null:
				_session_continuation.clear()
				return _finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
			_set_post_move_continuation(requested_map, _state.party.coordinate, 1)
			return _continue_post_move(events)
		if _apply_trigger_destination(trigger, events, exploration.action_point_destination_depth == 0):
			var destination_map := _content.world.map_by_id(_state.party.map_id)
			_set_post_move_continuation(destination_map, _state.party.coordinate, 1)
			return _continue_post_move(events)
		exploration.active_trigger_id = ""
		exploration.trigger_index = trigger_ids.size()
	var random_step := _continue_random_regions(map, events)
	if random_step != null:
		return random_step
	_session_continuation.clear()
	return _finish_completed(events)


func _continue_exploration_continuation(events: Array[DomainEvent]) -> SessionStep:
	if _session_continuation.kind == &"application-hook":
		return _continue_application_hook(events)
	if _session_continuation.kind == &"post-clock":
		return _continue_post_time(events)
	if _session_continuation.kind == &"post-move":
		return _continue_post_move(events)
	return _finish_failed(&"invalid_session_continuation", "The completed scenario has no valid exploration continuation.", events)


func _start_application_hook(hook: StringName, resume_kind: StringName, service_id: String, preceding_events: Array[DomainEvent], suspended: SessionContinuation.ApplicationBody = null) -> SessionStep:
	var continuation := ScenarioApplicationHookWorkflow.continuation(_content, hook, resume_kind, service_id, suspended)
	if continuation == null:
		return _finish_failed(&"invalid_application_hook_resume", "The application hook has an unsupported resume path.", preceding_events)
	_session_continuation = continuation
	var body := _session_continuation.body as SessionContinuation.ApplicationBody
	var program_id := body.program_id
	if program_id.is_empty():
		return _continue_application_hook(preceding_events)
	var started := _scenario_vm.start_program(program_id, ScenarioApplicationHookWorkflow.start_context(hook, service_id))
	if started.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(started.error_code, started.error_message, preceding_events)
	var result := _scenario_vm.run(_runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"application_hook_started", {"hook": String(hook), "programId": program_id}))
	events.append_array(result.events)
	if _events_have(result.events, &"party_revived"):
		body.party_revived = true
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _finish_failed(&"nested_party_defeat_handoff", "An application hook cannot suspend another total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(result.interaction, events)
	return _continue_application_hook(events)


func _continue_application_hook(events: Array[DomainEvent]) -> SessionStep:
	var body := _session_continuation.body as SessionContinuation.ApplicationBody
	if body == null:
		return _finish_failed(&"invalid_session_continuation", "Application-hook continuation body is unavailable.", events)
	var hook := body.hook
	var program_id := body.program_id
	var resume_kind := String(body.resume_kind)
	var service_id := body.service_id
	var party_revived := body.party_revived
	var suspended_vm := ScenarioVmSnapshot.from_data(body.suspended_vm.to_data()) if body.suspended_vm != null else null
	var suspended_owner := body.suspended_owner
	var vm_handoff := body.vm_handoff.copy() if body.vm_handoff != null else null
	_session_continuation.clear()
	if not program_id.is_empty():
		events.append(ScenarioApplicationHookWorkflow.completion_event(body))
	match resume_kind:
		"begin-adventure":
			events.append(DomainEvent.new(&"adventure_begun", {"campaignId": _content.campaign_id}))
			return _finish_completed(events)
		"service":
			return _open_contextual_service(service_id, events)
		"end-adventure":
			return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "end-adventure-close", "", events)
		"end-adventure-close":
			if party_revived:
				events.append(DomainEvent.new(&"adventure_end_suppressed", {"reason": "classic-party-death-revival"}))
				return _finish_completed(events)
			return _commit_close(events, "end-adventure")
		"party-defeat":
			if not party_revived:
				return _commit_close(events, "party-defeat")
			if _state.combat == null or not _state.combat.completed or _state.combat.outcome != &"defeat":
				return _finish_failed(&"invalid_battle_continuation", "Party Death revival lost its completed defeat.", events)
			_state.combat.outcome = &"retreated"
			_state.last_battle_outcome = &"retreated"
			events.append(DomainEvent.new(&"party_defeat_revived", {"battleId": _state.combat.battle_id, "source": "classic-party-death-hook"}))
			return _finish_direct_battle_without_rewards(events)
		"scenario-party-defeat":
			if not party_revived:
				return _commit_close(events, "party-defeat")
			return _resume_scenario_party_defeat(suspended_vm, suspended_owner, vm_handoff, events)
	return _finish_failed(&"invalid_session_continuation", "Application hook '%s' has invalid resume kind '%s'." % [hook, resume_kind], events)


func _begin_scenario_handoff(result: ScenarioVmResult, events: Array[DomainEvent]) -> SessionStep:
	if result == null or result.state != ScenarioVmResult.State.SUSPENDED or result.handoff == null or result.handoff.runtime == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_vm_handoff", "The Scenario VM did not provide a typed application handoff.", events)
	if _session_continuation.kind not in [&"post-clock", &"post-move"]:
		_session_continuation.clear()
		return _finish_failed(&"unsupported_vm_handoff_owner", "Total-party defeat cannot suspend this scenario caller.", events)
	var saved := _scenario_vm.snapshot()
	if not ScenarioVm.handoff_is_valid(result.handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_content, _state, result.handoff.runtime):
		_session_continuation.clear()
		return _finish_failed(&"invalid_party_defeat_handoff", "The Scenario VM total-party defeat handoff is invalid.", events)
	var suspended := SessionContinuation.ApplicationBody.new()
	suspended.suspended_vm = ScenarioVmSnapshot.from_data(saved.to_data())
	suspended.suspended_owner = _session_continuation.copy()
	suspended.vm_handoff = result.handoff.copy()
	_scenario_vm.reset()
	return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, &"scenario-party-defeat", "", events, suspended)


func _resume_scenario_party_defeat(saved: ScenarioVmSnapshot, suspended_owner: SessionContinuation, vm_handoff: ScenarioVmHandoff, events: Array[DomainEvent]) -> SessionStep:
	if not ScenarioVm.handoff_is_valid(vm_handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_content, _state, vm_handoff.runtime) or not SessionRestoreValidator.suspended_scenario_owner_is_valid(_content, _state, suspended_owner, saved):
		return _finish_failed(&"invalid_party_defeat_handoff", "The saved scenario defeat continuation is invalid.", events)
	var restored_vm := ScenarioVm.new()
	restored_vm.configure(_content.scenario)
	if not restored_vm.restore(saved):
		return _finish_failed(&"invalid_vm_state", "The suspended scenario cannot be restored after Party Death.", events)
	var operation := _runtime_api.complete_party_defeat_handoff(vm_handoff.runtime)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(operation.error_code, operation.error_message, events)
	_scenario_vm = restored_vm
	var resumed := _scenario_vm.resume_handoff(vm_handoff, operation, _runtime_api)
	events.append_array(resumed.events)
	_set_continuation(suspended_owner.copy())
	if resumed.state == ScenarioVmResult.State.SUSPENDED:
		return _begin_scenario_handoff(resumed, events)
	if resumed.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(resumed.interaction, events)
	if resumed.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(resumed.error_code, resumed.error_message, events)
	if _session_continuation.is_empty():
		return _finish_completed(events)
	return _continue_exploration_continuation(events)


func _apply_trigger_destination(trigger: TriggerDefinition, events: Array[DomainEvent], allow_destination: bool) -> bool:
	var destination := trigger.post_action_location
	if not allow_destination or destination == null or destination.map_id == _state.party.map_id and destination.coordinate == _state.party.coordinate:
		return false
	var source_map_id := _state.party.map_id
	var source_coordinate := _state.party.coordinate
	_state.party.map_id = destination.map_id
	_state.party.coordinate = destination.coordinate
	_state.world.mark_visited(destination.map_id, destination.coordinate)
	events.append(DomainEvent.new(&"party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": destination.map_id, "x": destination.coordinate.x, "y": destination.coordinate.y, "source": "action-point-destination", "triggerId": trigger.id}))
	return true


func _finalize_completed_trigger(trigger: TriggerDefinition, events: Array[DomainEvent]) -> void:
	if _events_keep_trigger(events, trigger.id) or _state.world.trigger_is_disabled(trigger.id):
		return
	_state.world.disable_trigger(trigger.id)
	events.append(DomainEvent.new(&"trigger_disabled", {"triggerId": trigger.id, "source": "classic-default-one-shot"}))


static func _events_have(events: Array[DomainEvent], kind: StringName) -> bool:
	for event: DomainEvent in events:
		if event.kind == kind:
			return true
	return false


static func _events_keep_trigger(events: Array[DomainEvent], trigger_id: String) -> bool:
	for event: DomainEvent in events:
		if event.kind == &"action_point_kept" and String(event.payload.get("triggerId", "")) == trigger_id:
			return true
	return false


static func _event_payload(events: Array[DomainEvent], kind: StringName) -> Dictionary:
	for index: int in range(events.size() - 1, -1, -1):
		if events[index].kind == kind:
			return events[index].payload
	return {}


func _start_session_death_macro(preceding_events: Array[DomainEvent]) -> SessionStep:
	var request := _event_payload(preceding_events, &"monster_death_macro_requested")
	var combat := _state.combat
	if request.is_empty() or combat == null:
		return _finish_failed(&"invalid_death_macro_request", "Monster death-macro execution requires an active combatant request.", preceding_events)
	var combatant_id := str(request.get("combatantId", ""))
	var program_id := str(request.get("programId", ""))
	var monster := combat.monster_by_id(combatant_id)
	if monster == null or _content.scenario.program_by_id(program_id) == null:
		return _finish_failed(&"invalid_death_macro_request", "Monster death-macro execution references unavailable content.", preceding_events)
	var continuation_body := SessionContinuation.CombatBody.new()
	continuation_body.battle_id = combat.battle_id
	continuation_body.combatant_id = combatant_id
	continuation_body.program_id = program_id
	continuation_body.reset_traitor_on_complete = bool(request.get("resetTraitorOnComplete", true))
	_set_continuation(SessionContinuation.combat_state(&"combat-death-macro", continuation_body))
	var death_context := ScenarioExecutionContext.calling(&"monster-death-macro")
	death_context.set_battle(combat.battle_id)
	death_context.set_combatant(combatant_id, int(request.get("classicMonsterId", 0)), bool(request.get("traitor", monster.traitor)), true)
	var started := _scenario_vm.start_program(program_id, death_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(started.error_code, started.error_message, preceding_events)
	var result := _scenario_vm.run(_runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"monster_death_macro_started", {"battleId": combat.battle_id, "combatantId": combatant_id, "programId": program_id}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		_session_continuation.clear()
		return _finish_failed(&"unsupported_vm_handoff_owner", "A session-owned monster death macro cannot suspend a total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(result.interaction, events)
	return _continue_session_death_macro(events)


func _continue_session_death_macro(events: Array[DomainEvent]) -> SessionStep:
	var combat := _state.combat
	var continuation := _session_continuation.combat()
	if continuation == null:
		return _finish_failed(&"invalid_battle_continuation", "Monster death-macro continuation is unavailable.", events)
	var battle_id := continuation.battle_id
	var combatant_id := continuation.combatant_id
	var program_id := continuation.program_id
	if combat == null or combat.battle_id != battle_id:
		_session_continuation.clear()
		return _finish_failed(&"invalid_battle_continuation", "Monster death-macro completion lost its battle.", events)
	var monster := combat.monster_by_id(combatant_id)
	if monster != null and continuation.reset_traitor_on_complete:
		monster.traitor = false
	events.append(DomainEvent.new(&"monster_death_macro_completed", {"battleId": battle_id, "combatantId": combatant_id, "programId": program_id, "revived": monster != null and monster.current_health > 0}))
	_session_continuation.clear()
	var continued := _rules.combat_flow.continue_after_monster_death_macro(_state, _content, _rng, combatant_id)
	if not continued.ok:
		return _finish_failed(continued.error_code, continued.error_message, events)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _finish_with_age_updates(events, "combat-monster-turns")
	if not _event_payload(continued.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(events)
	if continued.completed:
		return _finish_direct_battle(events)
	return _finish_completed(events)


func _append_session_battle_after_message(battle_id: String, events: Array[DomainEvent]) -> void:
	var battle := _content.battle_by_id(battle_id)
	if battle == null or battle.message_after_id == 0:
		return
	var message := _content.message_by_id(absi(battle.message_after_id))
	if message != null:
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-battle-definition"}))


func _finish_direct_battle(events: Array[DomainEvent]) -> SessionStep:
	if _state.combat == null or not _state.combat.completed:
		return _finish_failed(&"invalid_battle_continuation", "Post-battle completion requires a completed battle.", events)
	if _state.combat.outcome == &"defeat":
		return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "party-defeat", "", events)
	var payload := _rules.combat_flow.ally_selection_payload(_state, _content)
	if not payload.is_empty():
		var request_id := "session.ally-selection.%d" % (_view_revision + 1)
		var combat := SessionContinuation.CombatBody.new()
		combat.battle_id = _state.combat.battle_id
		_set_continuation(SessionContinuation.combat_state(&"combat-ally-selection", combat))
		_session_interaction = InteractionRequest.from_payload(request_id, &"ally_selection", payload)
		return _finish_waiting(_session_interaction, events)
	return _finish_direct_battle_recovery(events)


func _finish_direct_battle_recovery(events: Array[DomainEvent]) -> SessionStep:
	var payload := _rules.combat_flow.fumble_recovery_payload(_state, _content)
	if not payload.is_empty():
		var request_id := "session.fumble-recovery.%d" % (_view_revision + 1)
		var combat := SessionContinuation.CombatBody.new()
		combat.battle_id = _state.combat.battle_id
		_set_continuation(SessionContinuation.combat_state(&"combat-fumble-recovery", combat))
		_session_interaction = InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, payload)
		return _finish_waiting(_session_interaction, events)
	return _begin_direct_battle_reward(events)


func _finish_direct_battle_without_rewards(events: Array[DomainEvent]) -> SessionStep:
	if _state.combat == null or not _state.combat.completed:
		return _finish_failed(&"invalid_battle_continuation", "Suppressed battle rewards require a completed battle.", events)
	var battle_id := _state.combat.battle_id
	var return_continuation := _battle_return_continuation.copy()
	var battle_outcome := _state.combat.outcome
	events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": String(battle_outcome)}))
	_state.combat = null
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionStep:
	var return_continuation := _battle_return_continuation.copy()
	var battle_outcome := _state.combat.outcome
	var request_id := "session.battle-reward.%d" % (_view_revision + 1)
	var operation := _runtime_api.begin_completed_battle_reward(request_id)
	events.append_array(operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(operation.error_code, operation.error_message, events)
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		_set_continuation(SessionContinuation.combat_reward(_state.combat.battle_id, operation.continuation))
		_session_interaction = operation.interaction
		return _finish_waiting(_session_interaction, events)
	_session_interaction = null
	_session_continuation.clear()
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _finish_after_direct_battle(events: Array[DomainEvent], return_continuation: SessionContinuation, battle_outcome: StringName) -> SessionStep:
	_battle_return_continuation.clear()
	if return_continuation == null or return_continuation.is_empty() or battle_outcome == &"defeat" or not _events_have(events, &"battle_returned"):
		return _finish_completed(events)
	_set_continuation(return_continuation.copy())
	return _continue_post_time(events)


func _continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionStep:
	if not _state.random_encounters_enabled:
		return null
	var exploration := _session_continuation.exploration()
	if exploration == null:
		return _finish_failed(&"invalid_session_continuation", "Random encounters require an exploration continuation.", events)
	var region_ids := exploration.random_region_ids
	while exploration.random_region_index >= 0:
		var region_index := exploration.random_region_index
		var region_id: String = String(region_ids[region_index])
		var region := map.random_region_by_id(region_id)
		if region == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_session_continuation", "Random-region continuation references unavailable content.", events)
		var effective := _state.world.random_region(region)
		var roll := _rng.draw(10_000, StringName("random-region.%s" % region.id))
		var triggered := roll <= effective.chance_ten_thousand
		events.append(DomainEvent.new("random_encounter_checked", {"regionId": region.id, "roll": roll, "chanceTenThousand": effective.chance_ten_thousand, "triggered": triggered}))
		if triggered:
			events.append(DomainEvent.new(&"random_region_triggered", {"regionId": region.id}))
			var door_ids := region.random_doors()
			var door_percents := effective.random_door_percents()
			for door_index: int in door_ids.size():
				var door_roll := _rng.draw(100, StringName("random-region.%s.door.%d" % [region.id, door_index]))
				var door_fired := door_roll <= absi(door_percents[door_index])
				events.append(DomainEvent.new(&"random_door_checked", {"regionId": region.id, "doorIndex": door_index, "programId": "xap:%d" % door_ids[door_index], "roll": door_roll, "chancePercent": door_percents[door_index], "triggered": door_fired}))
				if not door_fired:
					continue
				effective.consume_random_door(door_index)
				_state.world.set_random_region(effective)
				var program_id := "xap:%d" % door_ids[door_index]
				exploration.active_random_program_id = program_id
				events.append(DomainEvent.new(&"random_door_triggered", {"regionId": region.id, "programId": program_id, "oneShot": door_percents[door_index] > 0}))
				var context := ScenarioExecutionContext.trigger(&"action", "", map.id, _state.party.coordinate, true).set_random_region(region.id)
				var started := _scenario_vm.start_program(program_id, context)
				if started.state == ScenarioVmResult.State.FAILED:
					_session_continuation.clear()
					return _finish_failed(started.error_code, started.error_message, events)
				var result := _scenario_vm.run(_runtime_api)
				events.append_array(result.events)
				if result.state == ScenarioVmResult.State.SUSPENDED:
					return _begin_scenario_handoff(result, events)
				if result.state == ScenarioVmResult.State.WAITING:
					return _finish_waiting(result.interaction, events)
				if result.state == ScenarioVmResult.State.FAILED:
					_session_continuation.clear()
					return _finish_failed(result.error_code, result.error_message, events)
				if _events_have(result.events, &"destination_trigger_recheck_requested"):
					var requested_map := _content.world.map_by_id(_state.party.map_id)
					if requested_map == null:
						_session_continuation.clear()
						return _finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
					_set_post_move_continuation(requested_map, _state.party.coordinate, 1)
					return _continue_post_move(events)
				return _complete_random_program(events)
			if effective.battle_minimum != 0 and not _state.party.conditions.is_active(7):
				var good_surprise_roll := _rng.draw(100, StringName("random-region.%s.good-surprise" % region.id))
				if good_surprise_roll < region.option:
					var message := _content.message_by_id(absi(region.text_id))
					var prompt := message.text if message != null else "Take the advantage and enter battle?"
					exploration.active_random_region_id = region.id
					exploration.random_battle_stage = &"surprise-choice"
					var request_id := "random-surprise:%s:%d" % [region.id, _rng.snapshot().draw_count]
					_session_interaction = InteractionRequest.from_payload(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
					if region.sound_id > 0:
						events.append(DomainEvent.new(&"audio_requested", {"soundId": region.sound_id}))
					return _finish_waiting(_session_interaction, events)
				var bad_surprise_roll := _rng.draw(100, StringName("random-region.%s.bad-surprise" % region.id))
				var surprise := -1 if bad_surprise_roll < 10 else 0
				return _start_random_battle(region, surprise, events)
		exploration.random_region_index = region_index - 1
		if region.only:
			break
	return null


func _complete_random_program(events: Array[DomainEvent]) -> SessionStep:
	if _session_continuation.kind == &"post-clock":
		_session_continuation.exploration().active_random_program_id = ""
		return _complete_post_time(events)
	_session_continuation.clear()
	return _finish_completed(events)


func _finish_completed(events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.completed(_view_revision, events)


func _commit_workflow_result(result: SessionWorkflowResult) -> SessionStep:
	if result == null:
		return SessionStep.failed(_view_revision, &"invalid_workflow_result", "The session workflow returned no result.")
	return _finish_completed(result.events) if result.ok else SessionStep.failed(_view_revision, result.error_code, result.error_message)


func _finish_magic_workflow(result: SessionWorkflowResult) -> SessionStep:
	if result == null:
		return SessionStep.failed(_view_revision, &"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "completed")
	return _finish_completed(result.events)


func _finish_magic_transition(result: InventoryMagicServicesWorkflow.MagicTransitionResult) -> SessionStep:
	if result == null:
		return SessionStep.failed(_view_revision, &"invalid_workflow_result", "The magic workflow returned no result.")
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if result.completed:
		return _finish_magic_workflow(SessionWorkflowResult.completed(result.events)) if result.process_age_updates else _finish_completed(result.events)
	if result.continuation == null or result.continuation.is_empty() or result.interaction == null:
		return SessionStep.failed(_view_revision, &"invalid_workflow_result", "The magic workflow returned an incomplete interaction transition.")
	_set_continuation(result.continuation)
	_session_interaction = result.interaction
	return _finish_waiting(_session_interaction, result.events)


func _finish_waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.waiting(_view_revision, request, events)


func _finish_failed(code: StringName, message: String, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.failed(_view_revision, code, message, events)


func _pending_interaction() -> InteractionRequest:
	if _session_interaction != null:
		return _session_interaction
	return _scenario_vm.pending_request() if _scenario_vm != null else null


func _respond_session_interaction(response: InteractionResponse) -> SessionStep:
	match _session_continuation.kind:
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
	var surprise_body := response.body as InteractionResponse.YesNoBody
	if response.kind != &"yes_no" or surprise_body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "The random encounter response must be a yes/no choice.")
	var exploration := _session_continuation.exploration()
	if exploration == null or exploration.random_battle_stage != &"surprise-choice":
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The random encounter choice has no matching continuation.")
	var map := _content.world.map_by_id(exploration.map_id)
	var region_id := exploration.active_random_region_id
	var region: RandomEncounterRegion = null if map == null else map.random_region_by_id(region_id)
	if region == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The random encounter choice references unavailable content.")
	_session_interaction = null
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	var events: Array[DomainEvent] = [DomainEvent.new(&"random_surprise_chosen", {"regionId": region.id, "accepted": surprise_body.accepted})]
	if surprise_body.accepted:
		return _start_random_battle(region, 1, events)
	exploration.random_region_index -= 1
	if region.only:
		if _session_continuation.kind == &"post-clock":
			return _complete_post_time(events)
		_session_continuation.clear()
		return _finish_completed(events)
	var next_step := _continue_random_regions(map, events)
	if next_step != null:
		return next_step
	if _session_continuation.kind == &"post-clock":
		return _complete_post_time(events)
	_session_continuation.clear()
	return _finish_completed(events)


func _respond_pooled_wealth_departure(response: InteractionResponse) -> SessionStep:
	var service := _session_continuation.service()
	if service == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The pooled-wealth departure continuation is unavailable.")
	var stage := service.stage
	var direction := service.direction
	if stage == &"warning":
		var warning_body := response.body as InteractionResponse.YesNoBody
		if response.kind != InteractionRequest.YES_NO or warning_body == null:
			return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Pooled-wealth departure requires a yes/no response.")
		if warning_body.accepted:
			service.stage = &"distribution"
			_session_interaction = _pooled_wealth_departure_distribution_request("pooled-wealth-departure:%d" % (_view_revision + 1))
			return _finish_waiting(_session_interaction, [
				DomainEvent.new(&"pooled_wealth_distribution_opened", {"wealth": _state.party.pooled_wealth.to_data()}),
				DomainEvent.new(&"sound_requested", {"soundId": 3003, "waitForCompletion": false, "stopExisting": true, "source": "classic-pooled-wealth-departure"}),
			])
		var discarded := _state.party.pooled_wealth.to_data()
		_state.party.pooled_wealth = WealthState.new()
		_session_interaction = null
		_session_continuation.clear()
		return _move_after_pooled_wealth(direction, [DomainEvent.new(&"pooled_wealth_left_behind", {"wealth": discarded, "movementContinues": true})])
	var body := response.body as InteractionResponse.BankBody
	if stage != &"distribution" or response.kind != InteractionRequest.POOLED_WEALTH_DEPARTURE or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Pooled-wealth distribution requires a typed money action.")
	var action := String(body.action)
	var selected_character_id := body.character_id
	if not selected_character_id.is_empty() and _state.party.character_by_id(selected_character_id) == null:
		return SessionStep.failed(_view_revision, &"unknown_money_target", "The selected pooled-wealth character is unavailable.")
	var events: Array[DomainEvent] = []
	if action == "leave":
		var discarded := _state.party.pooled_wealth.to_data()
		_state.party.pooled_wealth = WealthState.new()
		_session_interaction = null
		_session_continuation.clear()
		return _move_after_pooled_wealth(direction, [
			DomainEvent.new(&"pooled_wealth_left_behind", {"wealth": discarded, "movementContinues": true}),
			DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-done"}),
		])
	match action:
		"pool":
			var probe := _rules.economy.pool_probe(_state.party)
			if not probe.allowed:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", probe.reason)
			_rules.economy.pool_party_wealth(_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-pooled-wealth-departure", "wealth": _state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-pool"}))
		"share":
			var probe := _rules.economy.share_probe(_state.party)
			if not probe.allowed:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", probe.reason)
			_rules.economy.share_pooled_wealth(_state.party)
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-pooled-wealth-departure", "remaining": _state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-share"}))
		"to-pool", "to-character":
			if body.character_id.is_empty() or body.denomination.is_empty() or body.amount < 1:
				return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Pooled-wealth Swap requires character, denomination, and amount.")
			var character := _state.party.character_by_id(body.character_id)
			var kind := _money_kind(body.denomination)
			var amount := body.amount
			if character == null or kind < 0:
				return SessionStep.failed(_view_revision, &"unknown_money_target", "The selected pooled-wealth transfer is unavailable.")
			if amount != EconomyRules.classic_transfer_increment(kind as WealthState.Kind):
				return SessionStep.failed(_view_revision, &"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character := action == "to-character"
			var probe := _rules.economy.transfer_probe(_state.party, character, kind as WealthState.Kind, amount, to_character)
			if not probe.allowed:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", probe.reason)
			var transferred := _rules.economy.transfer_pool_to_character(_state.party, character, kind as WealthState.Kind, amount) if to_character else _rules.economy.transfer_character_to_pool(_state.party, character, kind as WealthState.Kind, amount)
			if not transferred:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", "The selected pooled-wealth transfer is no longer available.")
			_recalculate_party_movement()
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-pooled-wealth-departure", "characterId": character.id, "direction": action, "kind": body.denomination, "amount": amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-pooled-wealth-departure-swap"}))
		_:
			return SessionStep.failed(_view_revision, &"unknown_money_action", "Pooled-wealth action '%s' is unavailable." % action)
	_session_interaction = _pooled_wealth_departure_distribution_request("pooled-wealth-departure:%d" % (_view_revision + 1), selected_character_id)
	return _finish_waiting(_session_interaction, events)


func _pooled_wealth_departure_distribution_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	return SessionInteractionFactory.pooled_wealth_departure_distribution(_state, request_id, selected_character_id)


func _respond_item_use_target(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Item use requires an ordered characterIds array.")
	var target_ids := body.character_ids.duplicate()
	var targeting := _session_continuation.targeting()
	var saved_continuation := _session_continuation.copy()
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_spell_item(_workflow_context(), targeting, target_ids))
	if completed.state == SessionStep.State.FAILED:
		_set_continuation(saved_continuation)
		_session_interaction = saved_interaction
	return completed


func _respond_field_spell_target(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Field casting requires an ordered characterIds array.")
	var target_ids := body.character_ids.duplicate()
	var targeting := _session_continuation.targeting()
	var saved_continuation := _session_continuation.copy()
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_spell(_workflow_context(), targeting, target_ids))
	if completed.state == SessionStep.State.FAILED:
		_set_continuation(saved_continuation)
		_session_interaction = saved_interaction
	return completed


func _respond_scroll_target(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Scroll use requires an ordered characterIds array.")
	var target_ids := body.character_ids.duplicate()
	var targeting := _session_continuation.targeting()
	var saved_continuation := _session_continuation.copy()
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _finish_magic_transition(InventoryMagicServicesWorkflow.resume_field_scroll(_workflow_context(), targeting, target_ids))
	if completed.state == SessionStep.State.FAILED:
		_set_continuation(saved_continuation)
		_session_interaction = saved_interaction
	return completed


func _service_action(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ServicePayload
	if payload.action != &"enter":
		return SessionStep.failed(_view_revision, &"unknown_service_action", "Only entering an available service is implemented through this intent.")
	if payload.service_id == "realmz.service.temple":
		if not _state.temple_available:
			return SessionStep.failed(_view_revision, &"service_unavailable", "The selected temple is not available at this location.")
		return _start_application_hook(ScenarioApplicationHooks.TEMPLE, "service", payload.service_id, [])
	elif payload.service_id == "realmz.service.bank":
		return _open_contextual_service(payload.service_id, [])
	elif payload.service_id == _state.active_shop_id:
		if payload.service_id.is_empty() or _content.shop_by_id(payload.service_id) == null:
			return SessionStep.failed(_view_revision, &"service_unavailable", "The selected shop is not available at this location.")
		return _start_application_hook(ScenarioApplicationHooks.SHOP, "service", payload.service_id, [])
	else:
		return SessionStep.failed(_view_revision, &"service_unavailable", "The selected service is not available at this location.")


func _open_contextual_service(service_id: String, preceding_events: Array[DomainEvent]) -> SessionStep:
	var request_id := "service:%s:%d" % [service_id, _view_revision]
	var operation: ScenarioRuntimeOperationResult
	if service_id == "realmz.service.temple":
		operation = _runtime_api.request_available_temple(request_id)
	elif service_id == "realmz.service.bank":
		operation = _runtime_api.request_available_bank(request_id)
	elif service_id == _state.active_shop_id:
		operation = _runtime_api.request_available_shop(request_id)
	else:
		return _finish_failed(&"service_unavailable", "The selected service is not available at this location.", preceding_events)
	operation.events = preceding_events + operation.events
	return _begin_runtime_service(service_id, operation)


func _money_action(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.MoneyPayload
	var movement_error := _money_movement_context_error()
	if not movement_error.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_money_context", movement_error)
	var events: Array[DomainEvent] = []
	match payload.action:
		&"pool":
			var probe := _rules.economy.pool_probe(_state.party)
			if not probe.allowed:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", probe.reason)
			_rules.economy.pool_party_wealth(_state.party)
			events.append(DomainEvent.new(&"wealth_pooled", {"source": "classic-money", "wealth": _state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-money-pool"}))
		&"share":
			var probe := _rules.economy.share_probe(_state.party)
			if not probe.allowed:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", probe.reason)
			_rules.economy.share_pooled_wealth(_state.party)
			events.append(DomainEvent.new(&"wealth_shared", {"source": "classic-money", "remaining": _state.party.pooled_wealth.to_data()}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 128, "waitForCompletion": false, "source": "classic-money-share"}))
		&"to-pool", &"to-character":
			var character := _state.party.character_by_id(payload.character_id)
			var kind := _money_kind(payload.denomination)
			if character == null:
				return SessionStep.failed(_view_revision, &"unknown_character", "The selected money-transfer character is unavailable.")
			if kind < 0:
				return SessionStep.failed(_view_revision, &"unknown_wealth_kind", "The selected denomination is unavailable.")
			var expected_amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			if payload.amount != expected_amount:
				return SessionStep.failed(_view_revision, &"invalid_money_increment", "Classic Swap moves five gold or one gem or jewelry per action.")
			var to_character := payload.action == &"to-character"
			var probe := _rules.economy.transfer_probe(_state.party, character, kind as WealthState.Kind, payload.amount, to_character)
			if not probe.allowed:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", probe.reason)
			var transferred := _rules.economy.transfer_pool_to_character(_state.party, character, kind as WealthState.Kind, payload.amount) if to_character else _rules.economy.transfer_character_to_pool(_state.party, character, kind as WealthState.Kind, payload.amount)
			if not transferred:
				return SessionStep.failed(_view_revision, &"money_action_unavailable", "The selected wealth transfer is no longer available.")
			events.append(DomainEvent.new(&"wealth_transferred", {"source": "classic-money", "characterId": character.id, "direction": String(payload.action), "kind": payload.denomination, "amount": payload.amount}))
			events.append(DomainEvent.new(&"sound_requested", {"soundId": 10051 if to_character else 663, "waitForCompletion": false, "source": "classic-money-swap"}))
		_:
			return SessionStep.failed(_view_revision, &"unknown_money_action", "Money action '%s' is unavailable." % payload.action)
	_recalculate_party_movement()
	return _finish_completed(events)


func _money_movement_context_error() -> String:
	for character: CharacterState in _state.party.characters():
		if _content.race_by_id(character.race_id) == null or _content.caste_by_id(character.caste_id) == null:
			return "Character '%s' has no package-backed race or class for Classic movement recalculation." % character.id
	return ""


func _recalculate_party_movement() -> void:
	for character: CharacterState in _state.party.characters():
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		_rules.characters.recalculate_movement(character, race, caste.movement_bonus)


static func _money_kind(value: String) -> int:
	match value:
		"gold": return WealthState.Kind.GOLD
		"gems": return WealthState.Kind.GEMS
		"jewelry": return WealthState.Kind.JEWELRY
	return -1


func _begin_runtime_service(service_id: String, operation: ScenarioRuntimeOperationResult) -> SessionStep:
	if operation == null:
		return _finish_failed(&"service_failed", "The selected service returned no operation result.", [])
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(operation.error_code, operation.error_message, operation.events)
	if operation.state != ScenarioRuntimeOperationResult.State.WAITING or operation.interaction == null:
		return _finish_failed(&"service_failed", "The selected service did not produce its required interaction.", operation.events)
	_set_continuation(SessionContinuation.service_interaction(service_id, operation.continuation))
	_session_interaction = operation.interaction
	return _finish_waiting(_session_interaction, operation.events)


func _respond_runtime_service(response: InteractionResponse) -> SessionStep:
	var service := _session_continuation.service()
	if service == null or service.runtime_continuation == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The pending service has no runtime continuation.")
	var result := _runtime_api.resume_classic(service.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		service.runtime_continuation = result.continuation.copy()
		_session_interaction = result.interaction
		return _finish_waiting(_session_interaction, result.events)
	_session_interaction = null
	_session_continuation.clear()
	return _finish_completed(result.events)


func _respond_drop_item(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Dropping an item requires a yes/no response.")
	var targeting := _session_continuation.targeting()
	if targeting == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The item awaiting drop confirmation is unavailable.")
	var character_id := targeting.character_id
	var instance_id := targeting.instance_id
	var character := _state.party.character_by_id(character_id)
	var instance := _item_instance(character, instance_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The item awaiting drop confirmation is unavailable.")
	var probe := _rules.inventory.classic_drop_probe(character, instance)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_drop", probe.reason)
	_session_interaction = null
	_session_continuation.clear()
	if not body.accepted:
		return _finish_completed([DomainEvent.new(&"item_drop_declined", {"characterId": character.id, "instanceId": instance.id})])
	var removed := _rules.inventory.remove_item(character, instance.id, definition)
	if removed == null:
		return SessionStep.failed(_view_revision, &"item_drop_failed", "The item could not be removed from inventory.")
	return _finish_completed([DomainEvent.new(&"item_dropped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})])


func _respond_character_spell_confirmation(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Starting-spell confirmation requires a yes/no response.")
	var application := _session_continuation.application()
	if application == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	var character_id := application.character_id
	if _state.character_draft == null or _state.character_draft.generated_character == null or _state.character_draft.generated_character.id != character_id:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	_session_interaction = null
	_session_continuation.clear()
	if not body.accepted:
		return _finish_completed([DomainEvent.new(&"character_spell_confirmation_declined", {"characterId": character_id})])
	return _commit_character_draft([DomainEvent.new(&"character_spell_confirmation_accepted", {"characterId": character_id})])


func _respond_character_vault_publication(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Character-vault publication requires a yes/no response.")
	var application := _session_continuation.application()
	if application == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	var character_id := application.character_id
	var character := _state.party.character_by_id(character_id)
	if _state.party_setup_completed or character == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	_session_interaction = null
	_session_continuation.clear()
	if body.accepted:
		return _finish_completed([DomainEvent.new(&"character_publication_requested", {"characterId": character_id})])
	return _finish_completed([DomainEvent.new(&"character_publication_declined", {"characterId": character_id})])


func _respond_session_retreat(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	var continuation := _session_continuation.combat()
	if continuation == null or _state.combat == null or _state.combat.completed or _state.combat.battle_id != continuation.battle_id or _state.combat.active_actor_id() != continuation.actor_id:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting Escape confirmation is unavailable.")
	_session_interaction = null
	_session_continuation.clear()
	if not body.accepted:
		return _finish_completed([DomainEvent.new(&"combat_retreat_declined", {"actorId": continuation.actor_id, "mode": String(continuation.mode), "source": "classic"})])
	var result := _rules.combat_flow.retreat_character(_state, _content, continuation.actor_id, continuation.mode, continuation.destination, _rng)
	return _finish_combat_result(result)


func _finish_with_age_updates(events: Array[DomainEvent], resume_kind: StringName, resume_continuation: SessionContinuation = null) -> SessionStep:
	var updates := CharacterAgingResult.update_bodies(events)
	if updates.is_empty():
		if resume_kind == &"post-move":
			_set_continuation(resume_continuation.copy())
			return _continue_post_move(events)
		if resume_kind == &"post-clock":
			_set_continuation(resume_continuation.copy())
			return _continue_post_time(events)
		if resume_kind == &"combat-monster-turns":
			return _continue_after_session_combat_age_update(events)
		return _finish_completed(events)
	var age := SessionContinuation.AgeBody.new()
	for update: InteractionRequest.AgeUpdateBody in updates:
		age.updates.append(InteractionRequest.age_update_body("session.age-copy", update).body as InteractionRequest.AgeUpdateBody)
	age.index = 1
	age.resume_kind = resume_kind
	age.resume_continuation = null if resume_continuation == null else resume_continuation.copy()
	_set_continuation(SessionContinuation.age_updates(age))
	_session_interaction = InteractionRequest.age_update_body(_session_age_update_request_id(updates[0], 0), updates[0])
	events.append(CharacterAgingResult.sound_event_for_update(updates[0]))
	return _finish_waiting(_session_interaction, events)


func _respond_session_age_update(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var age := _session_continuation.age()
	if age == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The age-update queue is unavailable.")
	var updates := age.updates
	var index := age.index
	if updates.is_empty() or index < 1 or index > updates.size():
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The age-update queue is unavailable.")
	var acknowledged: InteractionRequest.AgeUpdateBody = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.character_id})]
	if index < updates.size():
		var next_payload: InteractionRequest.AgeUpdateBody = updates[index]
		age.index = index + 1
		_session_interaction = InteractionRequest.age_update_body(_session_age_update_request_id(next_payload, index), next_payload)
		events.append(CharacterAgingResult.sound_event_for_update(next_payload))
		return _finish_waiting(_session_interaction, events)
	var resume_kind := age.resume_kind
	var resume_continuation := age.resume_continuation
	_session_interaction = null
	_session_continuation.clear()
	if resume_kind == &"post-move":
		_set_continuation(resume_continuation.copy())
		return _continue_post_move(events)
	if resume_kind == &"post-clock":
		_set_continuation(resume_continuation.copy())
		return _continue_post_time(events)
	if resume_kind == &"combat-monster-turns":
		return _continue_after_session_combat_age_update(events)
	if resume_kind == &"completed":
		return _finish_completed(events)
	return _finish_failed(&"invalid_session_continuation", "The age-update queue has no valid completion path.", events)


func _continue_after_session_combat_age_update(events: Array[DomainEvent]) -> SessionStep:
	var continued := _rules.combat_flow.continue_after_age_update(_state, _content, _rng)
	if not continued.ok:
		return _finish_failed(continued.error_code, continued.error_message, events)
	events.append_array(continued.events)
	if not CharacterAgingResult.update_payloads(continued.events).is_empty():
		return _finish_with_age_updates(events, "combat-monster-turns")
	if not _event_payload(continued.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(events)
	if continued.completed:
		return _finish_direct_battle(events)
	return _finish_completed(events)


func _session_age_update_request_id(update: InteractionRequest.AgeUpdateBody, index: int) -> String:
	return "session.age-update:%s:%d:%d" % [update.character_id, _view_revision + 1, index]


func _respond_session_ally_selection(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.AllySelectionBody
	if response.kind != &"ally_selection" or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Ally selection requires selectedIds.")
	var continuation := _session_continuation.combat()
	if continuation == null or _state.combat == null or not _state.combat.completed or _state.combat.battle_id != continuation.battle_id:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for ally selection.")
	# Development saves from before the Castle body-count correction can retain an
	# impossible empty selection boundary. Re-evaluate the source-backed candidate
	# set and advance it exactly as a fresh terminal battle now does.
	if _rules.combat_flow.ally_selection_payload(_state, _content).is_empty():
		_session_interaction = null
		_session_continuation.clear()
		return _finish_direct_battle_recovery([])
	var result := _rules.combat_flow.apply_ally_selection(_state, _content, body.selected_ids)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	_session_interaction = null
	_session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _finish_direct_battle_recovery(events)


func _respond_session_fumble_recovery(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.TreasureBody
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	var continuation := _session_continuation.combat()
	if continuation == null or _state.combat == null or not _state.combat.completed or _state.combat.battle_id != continuation.battle_id:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var result := _rules.combat_flow.apply_fumble_recovery(_state, _content, body.action, body.instance_id, body.character_id)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	_session_interaction = null
	_session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _finish_direct_battle_recovery(events)


func _respond_session_battle_reward(response: InteractionResponse) -> SessionStep:
	var continuation := _session_continuation.reward()
	if continuation == null or _state.combat == null or not _state.combat.completed or _state.combat.battle_id != continuation.battle_id:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for reward distribution.")
	if continuation.runtime_continuation == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The battle reward continuation is unavailable.")
	var return_continuation := _battle_return_continuation.copy()
	var battle_outcome := _state.combat.outcome
	var result := _runtime_api.resume_classic(continuation.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		continuation.runtime_continuation = result.continuation.copy()
		_session_interaction = result.interaction
		return _finish_waiting(_session_interaction, result.events)
	_session_interaction = null
	_session_continuation.clear()
	return _finish_after_direct_battle(result.events, return_continuation, battle_outcome)


func _start_random_battle(region: RandomEncounterRegion, surprise: int, events: Array[DomainEvent]) -> SessionStep:
	var effective := _state.world.random_region(region)
	if effective.battle_maximum < effective.battle_minimum:
		_session_interaction = null
		_session_continuation.clear()
		return _finish_failed(&"invalid_random_battle_range", "Random rectangle '%s' has an inverted battle range." % region.id, events)
	var battle_id := _rng.draw_between(effective.battle_minimum, effective.battle_maximum, StringName("random-region.%s.battle" % region.id))
	var battle := _content.battle_by_classic_id(absi(battle_id))
	if battle == null:
		_session_interaction = null
		_session_continuation.clear()
		return _finish_failed(&"unknown_random_battle", "Random rectangle '%s' selected unavailable battle %d." % [region.id, battle_id], events)
	events.append(DomainEvent.new(&"random_encounter_triggered", {"regionId": region.id, "battleId": battle.id, "classicId": battle_id, "textId": region.text_id, "soundId": region.sound_id, "surprise": surprise}))
	var battle_result := _rules.combat_flow.start_battle(_state, _content, battle, _rng, surprise)
	if not battle_result.ok:
		_session_interaction = null
		_session_continuation.clear()
		return _finish_failed(battle_result.error_code, battle_result.error_message, events)
	events.append_array(battle_result.events)
	if _state.combat != null and _session_continuation.kind == &"post-clock":
		var exploration := _session_continuation.exploration()
		exploration.random_region_index = -1 if region.only else exploration.random_region_index - 1
		_battle_return_continuation = _session_continuation.copy()
	if not CharacterAgingResult.update_payloads(battle_result.events).is_empty():
		_session_interaction = null
		_session_continuation.clear()
		return _finish_with_age_updates(events, "combat-monster-turns")
	if not _event_payload(battle_result.events, &"monster_death_macro_requested").is_empty():
		_session_interaction = null
		_session_continuation.clear()
		return _start_session_death_macro(events)
	_session_interaction = null
	_session_continuation.clear()
	if battle_result.completed:
		return _finish_direct_battle(events)
	return _finish_completed(events)
