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
	_session_interaction = null
	_view_projector.clear()
	_started = true
	_view_revision = 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SessionSnapshot) -> SessionStep:
	if content == null or content.scenario == null or save_envelope == null:
		return SessionStep.failed(_view_revision, &"invalid_restore", "Validated content and save data are required.")
	if save_envelope.campaign_id != content.campaign_id or save_envelope.package_hash != content.package_hash:
		return SessionStep.failed(_view_revision, &"package_mismatch", "The save belongs to a different package build.")
	if save_envelope.rules_version != content.rules_version:
		return SessionStep.failed(_view_revision, &"rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(save_envelope.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(save_envelope.game_state.party.coordinate) == null:
		return SessionStep.failed(_view_revision, &"invalid_saved_location", "The saved party location is unavailable.")
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(save_envelope.rng_state):
		return SessionStep.failed(_view_revision, &"invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(save_envelope.game_state.to_data())
	var replacement_action_state := ScenarioActionState.from_data(save_envelope.scenario_action_state.to_data())
	if replacement_state == null or replacement_action_state == null:
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved game or Scenario Action state is invalid.")
	if not content.available_monster_sets().has(replacement_state.monster_set):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved game selects a monster set unavailable in this package.")
	if replacement_state.party_setup_completed and replacement_state.experience_multiplier < 0.0:
		replacement_state.experience_multiplier = _party_experience_multiplier(replacement_state.party.characters(), replacement_state.difficulty, content.campaign_definition())
	if replacement_state.combat != null:
		if not replacement_state.combat.return_continuation.is_empty():
			var battle_return := replacement_state.combat.return_continuation
			var battle_exploration := battle_return.exploration()
			if battle_return.kind != &"post-clock" or battle_exploration == null or battle_exploration.resume_kind != &"move" or not _valid_post_time_continuation(content, replacement_state, battle_return, null, null):
				return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved battle return references an unavailable exploration continuation.")
		for item: ItemInstance in replacement_state.combat.fumbled_items():
			if content.item_by_id(item.definition_id) == null:
				return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved fumble queue references unavailable item content.")
		for monster: MonsterState in replacement_state.combat.monsters():
			for item_id: String in monster.loot_item_ids():
				if not item_id.is_empty() and content.item_by_id(item_id) == null:
					return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved monster loot references unavailable item content.")
	var replacement_rules := RealmzRules.new()
	_normalize_age_groups(replacement_state, content, replacement_rules)
	if not _party_inventory_is_valid(content, replacement_state, replacement_rules):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved party inventory or carried load is invalid for this package.")
	if not _party_fast_spells_are_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved Fast Spell bindings reference unavailable package content.")
	if not _party_appearance_is_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved party appearance references unavailable package content.")
	if not _shop_state_is_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved shop state references unavailable package content.")
	if not _location_notes_are_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved location notes reference unavailable maps, cells, or invalid Classic note data.")
	if not _journal_messages_are_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved journal references unavailable or unrepresentable Classic messages.")
	if not _acquired_player_maps_are_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved acquired maps reference unavailable package content.")
	if not _character_draft_is_valid(content, replacement_state, replacement_rules):
		return SessionStep.failed(_view_revision, &"invalid_character_draft", "The saved character-creation draft is invalid for this campaign.")
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(save_envelope.scenario_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM state is invalid.")
	if not _valid_vm_reward_continuation(content, replacement_state, replacement_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM reward continuation is invalid.")
	if not _valid_player_map_vm_continuation(content, replacement_state, replacement_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM player-map continuation is invalid.")
	var replacement_continuation := SessionContinuation.new() if save_envelope.continuation == null else SessionContinuation.from_data(save_envelope.continuation.to_data())
	if replacement_continuation == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The saved session continuation is invalid.")
	var replacement_session_interaction: InteractionRequest = null
	if save_envelope.session_interaction != null:
		replacement_session_interaction = InteractionRequest.from_data(save_envelope.session_interaction.to_data())
		if replacement_session_interaction == null:
			return SessionStep.failed(_view_revision, &"invalid_session_interaction", "The saved session interaction is invalid.")
	if not replacement_continuation.is_empty() and not _valid_session_continuation(content, replacement_state, replacement_continuation, replacement_vm.pending_request(), replacement_session_interaction):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The saved session continuation is invalid.")
	if replacement_continuation.is_empty() and replacement_session_interaction != null:
		return SessionStep.failed(_view_revision, &"invalid_session_interaction", "The saved session interaction has no owning continuation.")
	_content = content
	_state = replacement_state
	_rng = replacement_rng
	_rules = replacement_rules
	_scenario_action_state = replacement_action_state
	_scenario_vm = replacement_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	_session_continuation = replacement_continuation
	_session_interaction = replacement_session_interaction
	_view_projector.clear()
	_view_revision = save_envelope.view_revision
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
		_session_interaction = null
		_scenario_vm = ScenarioVm.new()
		_scenario_vm.configure(_content.scenario)
		_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state, _rules)
	return _start_application_hook(ScenarioApplicationHooks.END_ADVENTURE, "end-adventure", "", [])


func _commit_close(events: Array[DomainEvent], reason: String) -> SessionStep:
	var campaign_id := _content.campaign_id
	_session_continuation.clear()
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
			return _create_party((intent.payload as PlayerIntent.PartyPayload).members)
		PlayerIntent.Kind.BEGIN_ADVENTURE:
			return _begin_adventure()
		PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
			return _import_vault_character(intent)
		PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT:
			return _generate_character_draft(intent)
		PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT:
			return _cancel_character_draft()
		PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS:
			return _set_character_draft_spells((intent.payload as PlayerIntent.StringListPayload).values)
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


func _character_spell_candidates(character: CharacterState, caste: CasteDefinition) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	if character == null or caste == null or character.spellcaster_type < 1:
		return result
	var maximum_level := _rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in _content.spell_definitions():
		if int(spell.classic_id / 1000) != character.spellcaster_type:
			continue
		var tier := spell.classic_tier()
		var slot := spell.classic_slot()
		if tier >= 0 and tier < maximum_level and slot >= 1 and slot <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


func _character_draft_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if state.character_draft == null:
		return true
	if state.party_setup_completed or state.character_draft.finalized or state.character_draft.generated_character == null:
		return false
	var draft := state.character_draft
	var character := draft.generated_character
	if character.name != draft.name or character.gender != draft.gender or character.race_id != draft.race_id or character.caste_id != draft.caste_id or character.portrait_id != draft.portrait_id or character.combat_icon_id != draft.combat_icon_id:
		return false
	var race := content.race_by_id(character.race_id)
	var caste := content.caste_by_id(character.caste_id)
	if race == null or caste == null:
		return false
	var restrictions := content.campaign_definition().restrictions
	if restrictions.banned_races.has(race.id) or restrictions.banned_castes.has(caste.id):
		return false
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return false
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return false
	for current: CharacterState in state.party.characters():
		if current.id == character.id or current.name.to_lower() == character.name.to_lower():
			return false
	var candidate_ids: Dictionary = {}
	for spell: SpellDefinition in content.spell_definitions():
		if int(spell.classic_id / 1000) == character.spellcaster_type:
			var tier := spell.classic_tier()
			if tier >= 0 and tier < rules.characters.maximum_spell_selection_level(caste):
				candidate_ids[spell.id] = spell
	var spent := 0
	for spell_id: String in character.known_spells():
		if not candidate_ids.has(spell_id):
			return false
		var spell: SpellDefinition = candidate_ids[spell_id]
		spent += rules.characters.spell_selection_cost(spell)
	if spent > rules.characters.spell_selection_total(character, caste):
		return false
	for item: ItemInstance in character.inventory():
		if content.item_by_id(item.definition_id) == null:
			return false
	return true


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
	return SessionSnapshot.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, state, _rng.snapshot(), vm_state, action_state, continuation, interaction)


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _scenario_vm == null else _scenario_vm.trace()


func _camp() -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"camp_during_battle", "The party cannot camp during battle.")
	if not _state.camping_allowed and not _state.party_camping:
		return SessionStep.failed(_view_revision, &"camping_disabled", "Camping is not allowed at this location.")
	_state.party_camping = not _state.party_camping
	var events: Array[DomainEvent] = [DomainEvent.new(&"camp_mode_changed", {"camping": _state.party_camping, "source": "classic"})]
	if _state.party_camping:
		_state.clear_location_services()
	var map := _content.world.map_by_id(_state.party.map_id)
	if map == null:
		return _finish_failed(&"unknown_map", "The current map is unavailable for Camp.", events)
	var time_scale := _classic_time_scale(map)
	var previous_day := _state.clock.day()
	events.append_array(_rules.clock.advance_classic_field_time(_state, _content, 5 if _state.party_camping else 2, time_scale, true))
	if not _state.party_camping:
		if _state.clock.day() == previous_day:
			return _finish_with_age_updates(events, "completed")
		_set_post_time_continuation(map, "completed", Vector2i.ZERO, false, _state.clock.day(), _state.party.coordinate)
		return _finish_with_age_updates(events, &"post-clock", _session_continuation.copy())
	_set_post_time_continuation(map, "completed", Vector2i.ZERO, true, _state.clock.day() if _state.clock.day() != previous_day else 0, _state.party.coordinate)
	return _finish_with_age_updates(events, &"post-clock", _session_continuation.copy())


func _rest() -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"rest_during_battle", "The party cannot rest during battle.")
	if not _state.party_camping:
		return SessionStep.failed(_view_revision, &"rest_outside_camp", "Make camp before resting.")
	var map := _content.world.map_by_id(_state.party.map_id)
	if map == null:
		return SessionStep.failed(_view_revision, &"unknown_map", "The current map is unavailable for Rest.")
	var previous_fatigue := _state.party.fatigue
	_rules.clock.change_fatigue(_state.party, -2)
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"fatigue_changed", {"previous": previous_fatigue, "current": _state.party.fatigue, "reason": "rest", "source": "classic"}),
	]
	var previous_day := _state.clock.day()
	events.append_array(_rules.clock.advance_classic_field_time(_state, _content, 5, _classic_time_scale(map), true))
	events.append(DomainEvent.new(&"party_rested", {"timeclicks": 5, "mapId": map.id, "source": "classic"}))
	_set_post_time_continuation(map, "completed", Vector2i.ZERO, true, _state.clock.day() if _state.clock.day() != previous_day else 0, _state.party.coordinate)
	return _finish_with_age_updates(events, &"post-clock", _session_continuation.copy())


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
		character = _item_owner(item_id)
	var instance := _item_instance(character, item_id)
	var item: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	var spell: SpellDefinition = null if item == null else _content.spell_by_classic_id(item.special_2)
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
	var probe := _field_spell_item_probe(character, instance, item, spell)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, _item_use_error_code(instance, item, spell), probe.reason)
	var power := absi(item.special_1)
	var random_power_checkpoint: Dictionary = {}
	if power == 8:
		random_power_checkpoint = _rng.checkpoint()
		power = _rng.draw(7, StringName("item.use.power.%s" % instance.id))
	target_ids = _field_item_target_ids(character, spell, target_ids, target_id)
	var required_count := _field_item_target_count(spell, power)
	if target_ids.size() == required_count:
		var completed := _commit_field_spell_item(character.id, instance.id, spell.id, power, target_ids)
		if completed.state == SessionStep.State.FAILED and not random_power_checkpoint.is_empty():
			_rng.rollback(random_power_checkpoint)
		return completed
	if not target_ids.is_empty():
		if not random_power_checkpoint.is_empty():
			_rng.rollback(random_power_checkpoint)
		return SessionStep.failed(_view_revision, &"invalid_item_use_target", "The item requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.instance_id = instance.id
	targeting.spell_id = spell.id
	targeting.power = power
	targeting.target_count = required_count
	targeting.starting_charges = instance.charges
	_set_continuation(SessionContinuation.targeting_selection(&"item-use-target-selection", targeting))
	_session_interaction = _item_target_request("session.item-use:%s:%d" % [instance.id, _view_revision + 1], character, instance.id, item, spell, required_count, _state.party.characters())
	return _finish_waiting(_session_interaction, [DomainEvent.new(&"item_target_requested", {"characterId": character.id, "instanceId": instance.id, "itemId": item.id, "spellId": spell.id, "power": power, "targetCount": required_count, "source": "classic"})])


func _field_spell_item_probe(character: CharacterState, instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> InventoryActionProbe:
	var probe := _rules.inventory.classic_spell_item_probe(character, instance, item, spell, _content.race_by_id(character.race_id) if character != null else null, _content.caste_by_id(character.caste_id) if character != null else null, false)
	if not probe.allowed:
		return probe
	var ordinary := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9
	var healing := absi(spell.special) == 57
	if not ordinary and not healing:
		return InventoryActionProbe.block("This item's Classic field spell effect is not implemented yet.")
	if spell.target_type == 7:
		return InventoryActionProbe.block("This item changes party-wide field state that is not implemented yet.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This item's Classic field target type is invalid.")
	return InventoryActionProbe.permit()


func _field_item_target_ids(character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		var party_ids: Array[String] = []
		for member: CharacterState in _state.party.characters():
			party_ids.append(member.id)
		return party_ids
	var values: Array[String] = requested_targets.duplicate()
	if values.is_empty() and not requested_target.is_empty():
		values.append(requested_target)
	return values


func _field_item_target_count(spell: SpellDefinition, power: int) -> int:
	if spell.target_type == 5:
		return 1
	if spell.target_type > 2:
		return _state.party.characters().size()
	return mini(power, _state.party.characters().size()) if spell.target_type == 0 else 1


func _commit_field_spell_item(character_id: String, instance_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionStep:
	var character := _state.party.character_by_id(character_id)
	var instance := _item_instance(character, instance_id)
	var item: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	var spell := _content.spell_by_id(spell_id)
	var probe := _field_spell_item_probe(character, instance, item, spell)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, _item_use_error_code(instance, item, spell), probe.reason)
	var selected: Dictionary = {}
	for target_id: String in requested_target_ids:
		if target_id.is_empty() or selected.has(target_id) or _state.party.character_by_id(target_id) == null:
			return SessionStep.failed(_view_revision, &"invalid_item_use_target", "The item target selection contains an unavailable or duplicate character.")
		selected[target_id] = true
	if selected.size() != _field_item_target_count(spell, power):
		return SessionStep.failed(_view_revision, &"invalid_item_use_target", "The item target selection has the wrong number of characters.")
	var targets: Array[CharacterState] = []
	for member: CharacterState in _state.party.characters():
		if selected.has(member.id):
			targets.append(member)
	if targets.size() != selected.size():
		return SessionStep.failed(_view_revision, &"invalid_item_use_target", "The item target selection is unavailable.")
	if not _rules.inventory.use_charge(character, instance.id, item):
		return SessionStep.failed(_view_revision, &"item_charge_commit_failed", "The validated item charge could not be committed.")
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for target: CharacterState in targets:
		castes.append(_content.caste_by_id(target.caste_id))
		races.append(_content.race_by_id(target.race_id))
	var resolution := _rules.magic.resolve_field_spell(character, targets, spell, power, _rng, castes, races, false)
	if resolution == null or not resolution.cast:
		return SessionStep.failed(_view_revision, &"item_spell_failed", "The item spell could not be resolved.")
	var charges_remaining := -1
	var dropped := true
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			charges_remaining = carried.charges
			dropped = false
			break
	var events: Array[DomainEvent] = [DomainEvent.new(&"item_used", {"characterId": character.id, "instanceId": instance_id, "itemId": item.id, "spellId": spell.id, "power": power, "chargesRemaining": charges_remaining, "droppedOnEmpty": dropped, "source": "classic"})]
	var native_sound_id := item.sound_id + 600
	if item.sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(native_sound_id), "waitForCompletion": native_sound_id < 0, "source": "classic-item"}))
	for index: int in resolution.resolutions.size():
		var target_resolution := resolution.resolutions[index]
		events.append(DomainEvent.new(&"item_spell_resolved", {"characterId": character.id, "targetId": resolution.target_ids[index], "itemId": item.id, "instanceId": instance_id, "spellId": spell.id, "power": power, "resisted": target_resolution.resisted, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}))
	return _finish_completed(events)


func _item_owner(instance_id: String) -> CharacterState:
	for character: CharacterState in _state.party.characters():
		if _item_instance(character, instance_id) != null:
			return character
	return null


static func _item_use_error_code(instance: ItemInstance, item: ItemDefinition, spell: SpellDefinition) -> StringName:
	if instance == null or item == null:
		return &"unknown_item_instance"
	if instance.charges == 0:
		return &"item_has_no_charges"
	if item.special_2 <= 1100:
		return &"item_has_no_spell_effect"
	if spell == null:
		return &"unknown_item_spell"
	return &"item_cannot_be_used"


static func _item_target_request(request_id: String, character: CharacterState, instance_id: String, item: ItemDefinition, spell: SpellDefinition, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var eligible: Array[Dictionary] = []
	for member: CharacterState in party:
		eligible.append({"id": member.id, "name": member.name, "currentHealth": member.current_health, "maximumHealth": member.maximum_health})
	var display_name := item.unidentified_name
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			display_name = item.name if carried.identified else item.unidentified_name
			break
	return InteractionRequest.from_payload(request_id, InteractionRequest.CHARACTER_SELECTION, {"prompt": "%s uses %s. Choose %d target%s." % [character.name, display_name, required_count, "" if required_count == 1 else "s"], "count": required_count, "eligible": eligible, "mode": "item-use", "itemInstanceId": instance_id, "spellId": spell.id})


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
	_session_interaction = _drop_item_confirmation_request("session.drop-item:%s:%d" % [instance.id, _view_revision + 1], display_name)
	return _finish_waiting(_session_interaction, [DomainEvent.new(&"item_drop_requested", {"characterId": character.id, "instanceId": instance.id})])


func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null or instance_id.is_empty():
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func _drop_item_confirmation_request(request_id: String, item_name: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "Drop %s? The item will be lost." % item_name, "Drop", "Keep")


func _cast_spell(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.SpellPayload
	if payload.operation == &"make-scroll":
		return _make_scroll(payload)
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


func _make_scroll(payload: PlayerIntent.SpellPayload) -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"scroll_scribing_in_battle", "Classic scroll scribing is available only while camped.")
	var character := _state.party.character_by_id(payload.caster_id)
	var spell := _content.spell_by_id(payload.spell_id)
	var probe := _make_scroll_probe(character, spell, payload.power)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"scroll_scribing_unavailable", probe.reason)
	var slot_index := _first_empty_scroll_slot(character)
	var parchment := _parchment_instance(character)
	var parchment_definition: ItemDefinition = null if parchment == null else _content.item_by_id(parchment.definition_id)
	if slot_index < 0 or parchment == null or parchment_definition == null or not _rules.inventory.use_charge(character, parchment.id, parchment_definition):
		return SessionStep.failed(_view_revision, &"scroll_scribing_commit_failed", "The validated scroll materials could not be committed.")
	var cost := absi(spell.cost * payload.power * 2)
	character.spell_points -= cost
	if not character.write_scroll(slot_index, spell.id, payload.power):
		return SessionStep.failed(_view_revision, &"scroll_scribing_commit_failed", "The validated scroll slot could not be committed.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_created", {"characterId": character.id, "slot": slot_index, "spellId": spell.id, "power": payload.power, "cost": cost, "parchmentInstanceId": parchment.id, "source": "classic"})]
	var sound_id := spell.sound_start + 600
	if sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(sound_id), "waitForCompletion": false, "source": "classic-scroll-scribing"}))
	return _finish_completed(events)


func _make_scroll_probe(character: CharacterState, spell: SpellDefinition, power: int) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if not _state.party_camping:
		return InventoryActionProbe.block("Enter camp before making a scroll.")
	if character.current_health < 1 or character.spellcaster_type < 1:
		return InventoryActionProbe.block("The selected character cannot scribe scrolls.")
	if not _has_equipped_scroll_case(character):
		return InventoryActionProbe.block("Equip a scroll case before making a scroll.")
	if _first_empty_scroll_slot(character) < 0:
		return InventoryActionProbe.block("The scroll case already contains five spells.")
	if _parchment_instance(character) == null:
		return InventoryActionProbe.block("The character has no parchment.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected scroll power.")
	if character.spell_points < absi(spell.cost * power * 2):
		return InventoryActionProbe.block("Scribing requires twice the spell's normal spell-point cost.")
	return InventoryActionProbe.permit()


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
	var character := _state.party.character_by_id(payload.caster_id)
	var scroll := character.scroll_at(payload.scroll_slot) if character != null else null
	var spell := _content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
	var probe := _scroll_use_probe(character, payload.scroll_slot, spell)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"scroll_unavailable", probe.reason)
	var target_ids := _field_spell_target_ids(character, spell, payload.target_ids, payload.target_id)
	var required_count := _field_spell_target_count(spell, scroll.power)
	if target_ids.size() == required_count:
		return _commit_field_scroll(character.id, payload.scroll_slot, spell.id, scroll.power, target_ids)
	if not target_ids.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_scroll_target", "The scroll requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.scroll_slot = payload.scroll_slot
	targeting.spell_id = spell.id
	targeting.power = scroll.power
	targeting.target_count = required_count
	_set_continuation(SessionContinuation.targeting_selection(&"scroll-target-selection", targeting))
	_session_interaction = _scroll_target_request("session.scroll:%s:%d:%d" % [character.id, payload.scroll_slot, _view_revision + 1], character, payload.scroll_slot, spell, required_count, _state.party.characters())
	return _finish_waiting(_session_interaction, [DomainEvent.new(&"scroll_target_requested", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": scroll.power, "targetCount": required_count, "source": "classic"})])


func _scroll_use_probe(character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if character == null or slot_index < 0 or slot_index >= 5:
		return InventoryActionProbe.block("The scroll slot is unavailable.")
	var scroll := character.scroll_at(slot_index)
	if scroll == null or scroll.is_empty() or spell == null or spell.id != scroll.spell_id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not _has_equipped_scroll_case(character):
		return InventoryActionProbe.block("Equip the scroll case before using its spells.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This scroll cannot be used outside battle; Classic offers to discard it.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This scroll has an invalid Classic field target type.")
	if spell.target_type in [3, 7, 9] and not _state.party.allies().is_empty():
		return InventoryActionProbe.block("This scroll also targets allied creatures; that Classic field branch is not implemented yet.")
	if not _field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This scroll's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


func _commit_field_scroll(character_id: String, slot_index: int, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionStep:
	var character := _state.party.character_by_id(character_id)
	var spell := _content.spell_by_id(spell_id)
	var probe := _scroll_use_probe(character, slot_index, spell)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"scroll_unavailable", probe.reason)
	var selected: Dictionary = {}
	for target_id: String in requested_target_ids:
		if target_id.is_empty() or selected.has(target_id) or _state.party.character_by_id(target_id) == null:
			return SessionStep.failed(_view_revision, &"invalid_scroll_target", "The scroll target selection contains an unavailable or duplicate character.")
		selected[target_id] = true
	if selected.size() != _field_spell_target_count(spell, power):
		return SessionStep.failed(_view_revision, &"invalid_scroll_target", "The scroll target selection has the wrong number of characters.")
	var targets: Array[CharacterState] = []
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for member: CharacterState in _state.party.characters():
		if selected.has(member.id):
			targets.append(member)
			castes.append(_content.caste_by_id(member.caste_id))
			races.append(_content.race_by_id(member.race_id))
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := _rules.magic.resolve_field_spell(character, targets, spell, power, _rng, castes, races, false, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionStep.failed(_view_revision, &"scroll_spell_failed", "The scroll spell could not be resolved.")
	if not character.clear_scroll(slot_index):
		return SessionStep.failed(_view_revision, &"scroll_commit_failed", "The resolved scroll could not be removed from its case.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"scroll_used", {"characterId": character.id, "slot": slot_index, "spellId": spell.id, "power": power, "source": "classic"})]
	var start_sound := spell.sound_start + 600
	if start_sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(start_sound), "waitForCompletion": true, "source": "classic-scroll"}))
	var special := absi(spell.special)
	if special == 68:
		_state.party.fatigue = 4
		events.append(DomainEvent.new(&"party_fatigue_changed", {"fatigue": 4, "spellId": spell.id, "source": "classic-scroll"}))
	elif spell.target_type == 7:
		var condition_index := 0 if special == 50 else special
		var next_value := power * 30 - 1 if special == 50 else maxi(_state.party.conditions.value(condition_index), resolution.duration)
		if special != 50 or power * 30 > _state.party.conditions.value(condition_index):
			_state.party.conditions.set_value(condition_index, next_value)
		events.append(DomainEvent.new(&"party_condition_changed", {"condition": condition_index, "value": _state.party.conditions.value(condition_index), "spellId": spell.id, "source": "classic-scroll"}))
	for index: int in resolution.resolutions.size():
		var target_resolution := resolution.resolutions[index]
		events.append(DomainEvent.new(&"scroll_spell_resolved", {"characterId": character.id, "targetId": resolution.target_ids[index], "spellId": spell.id, "power": power, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}))
		if target_resolution.aging != null and target_resolution.aging.changed_group():
			var target := _state.party.character_by_id(resolution.target_ids[index])
			events.append(DomainEvent.new(&"character_age_changed", target_resolution.aging.event_payload(target, _content.race_by_id(target.race_id))))
	if spell.target_type == 11 and spell.sound_end + 600 != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(spell.sound_end + 600), "waitForCompletion": false, "source": "classic-scroll"}))
	if not CharacterAgingResult.update_payloads(events).is_empty():
		return _finish_with_age_updates(events, "completed")
	return _finish_completed(events)


func _has_equipped_scroll_case(character: CharacterState) -> bool:
	if character == null:
		return false
	for instance: ItemInstance in character.inventory():
		var definition := _content.item_by_id(instance.definition_id)
		if instance.equipped and definition != null and absi(definition.item_type) == 13:
			return true
	return false


func _parchment_instance(character: CharacterState) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		var definition := _content.item_by_id(instance.definition_id)
		if definition != null and definition.classic_id == 806 and instance.charges != 0:
			return instance
	return null


static func _first_empty_scroll_slot(character: CharacterState) -> int:
	if character == null:
		return -1
	for index: int in character.scroll_case().size():
		if character.scroll_at(index).is_empty():
			return index
	return -1


static func _scroll_target_request(request_id: String, character: CharacterState, slot_index: int, spell: SpellDefinition, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var eligible: Array[Dictionary] = []
	for member: CharacterState in party:
		eligible.append({"id": member.id, "name": member.name, "currentHealth": member.current_health, "maximumHealth": member.maximum_health})
	return InteractionRequest.from_payload(request_id, InteractionRequest.CHARACTER_SELECTION, {"prompt": "%s uses %s from scroll slot %d. Choose %d target%s." % [character.name, spell.name, slot_index + 1, required_count, "" if required_count == 1 else "s"], "count": required_count, "eligible": eligible, "mode": "scroll-use", "scrollSlot": slot_index, "spellId": spell.id})


func _cast_field_spell(payload: PlayerIntent.SpellPayload) -> SessionStep:
	var character := _state.party.character_by_id(payload.caster_id)
	var spell := _content.spell_by_id(payload.spell_id)
	var probe := _field_spell_probe(character, spell, payload.power)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"field_spell_unavailable", probe.reason)
	var target_ids := _field_spell_target_ids(character, spell, payload.target_ids, payload.target_id)
	var required_count := _field_spell_target_count(spell, payload.power)
	if target_ids.size() == required_count:
		return _commit_field_spell(character.id, spell.id, payload.power, target_ids)
	if not target_ids.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_field_spell_target", "The spell requires exactly %d valid party target%s." % [required_count, "" if required_count == 1 else "s"])
	var targeting := SessionContinuation.TargetingBody.new()
	targeting.character_id = character.id
	targeting.spell_id = spell.id
	targeting.power = payload.power
	targeting.target_count = required_count
	targeting.starting_spell_points = character.spell_points
	_set_continuation(SessionContinuation.targeting_selection(&"field-spell-target-selection", targeting))
	_session_interaction = _field_spell_target_request("session.field-spell:%s:%d" % [spell.id, _view_revision + 1], character, spell, required_count, _state.party.characters())
	return _finish_waiting(_session_interaction, [DomainEvent.new(&"field_spell_target_requested", {"characterId": character.id, "spellId": spell.id, "power": payload.power, "targetCount": required_count, "source": "classic"})])


func _field_spell_probe(character: CharacterState, spell: SpellDefinition, power: int) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if _state.character_spellcasting_blocked:
		return InventoryActionProbe.block("Classic scenario state currently blocks character spellcasting.")
	if character.current_health < 1 or character.spell_points < 1:
		return InventoryActionProbe.block("The character cannot cast in their current state.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if character.conditions.is_active(condition):
			return InventoryActionProbe.block("The character's current Classic condition prevents spellcasting.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This spell cannot be cast outside battle.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected power level.")
	if character.spell_points < absi(spell.cost * power):
		return InventoryActionProbe.block("The character does not have enough spell points.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This spell has an invalid Classic field target type.")
	if spell.target_type in [3, 7, 9] and not _state.party.allies().is_empty():
		return InventoryActionProbe.block("This spell also targets allied creatures; that Classic field branch is not implemented yet.")
	if not _field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This spell's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


func _field_spell_effect_supported(spell: SpellDefinition) -> bool:
	var special := absi(spell.special)
	if spell.target_type == 7:
		return special == 50 or special >= 1 and special < ConditionSet.PARTY_COUNT
	if special == 68:
		return true
	if special > 0 and special < 41 or special in [48, 57, 59, 60, 61, 64, 66, 91, 92] or special > 99:
		return true
	return special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


func _field_spell_target_ids(character: CharacterState, spell: SpellDefinition, requested_targets: Array[String], requested_target: String) -> Array[String]:
	if spell.target_type == 5:
		return [character.id]
	if spell.target_type > 2:
		if spell.target_type == 7 or absi(spell.special) == 68:
			return []
		var party_ids: Array[String] = []
		for member: CharacterState in _state.party.characters():
			party_ids.append(member.id)
		return party_ids
	var values: Array[String] = requested_targets.duplicate()
	if values.is_empty() and not requested_target.is_empty():
		values.append(requested_target)
	return values


func _field_spell_target_count(spell: SpellDefinition, power: int) -> int:
	if spell.target_type == 7 or absi(spell.special) == 68:
		return 0
	if spell.target_type == 5:
		return 1
	if spell.target_type > 2:
		return _state.party.characters().size()
	return mini(power, _state.party.characters().size()) if spell.target_type == 0 else 1


func _commit_field_spell(character_id: String, spell_id: String, power: int, requested_target_ids: Array[String]) -> SessionStep:
	var character := _state.party.character_by_id(character_id)
	var spell := _content.spell_by_id(spell_id)
	var probe := _field_spell_probe(character, spell, power)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"field_spell_unavailable", probe.reason)
	var selected: Dictionary = {}
	for target_id: String in requested_target_ids:
		if target_id.is_empty() or selected.has(target_id) or _state.party.character_by_id(target_id) == null:
			return SessionStep.failed(_view_revision, &"invalid_field_spell_target", "The spell target selection contains an unavailable or duplicate character.")
		selected[target_id] = true
	if selected.size() != _field_spell_target_count(spell, power):
		return SessionStep.failed(_view_revision, &"invalid_field_spell_target", "The spell target selection has the wrong number of characters.")
	var targets: Array[CharacterState] = []
	var castes: Array[CasteDefinition] = []
	var races: Array[RaceDefinition] = []
	for member: CharacterState in _state.party.characters():
		if selected.has(member.id):
			targets.append(member)
			castes.append(_content.caste_by_id(member.caste_id))
			races.append(_content.race_by_id(member.race_id))
	var allow_empty := spell.target_type == 7 or absi(spell.special) == 68
	var resolution := _rules.magic.resolve_field_spell(character, targets, spell, power, _rng, castes, races, true, allow_empty)
	if resolution == null or not resolution.cast:
		return SessionStep.failed(_view_revision, &"field_spell_failed", "The field spell could not be resolved.")
	var events: Array[DomainEvent] = [DomainEvent.new(&"field_spell_cast", {"characterId": character.id, "spellId": spell.id, "power": power, "cost": resolution.cost, "source": "classic"})]
	var start_sound := spell.sound_start + 600
	if start_sound != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(start_sound), "waitForCompletion": true, "source": "classic-field-spell"}))
	var special := absi(spell.special)
	if special == 68:
		_state.party.fatigue = 4
		events.append(DomainEvent.new(&"party_fatigue_changed", {"fatigue": 4, "spellId": spell.id, "source": "classic"}))
	elif spell.target_type == 7:
		var condition_index := 0 if special == 50 else special
		var next_value := power * 30 - 1 if special == 50 else maxi(_state.party.conditions.value(condition_index), resolution.duration)
		if special != 50 or power * 30 > _state.party.conditions.value(condition_index):
			_state.party.conditions.set_value(condition_index, next_value)
		events.append(DomainEvent.new(&"party_condition_changed", {"condition": condition_index, "value": _state.party.conditions.value(condition_index), "spellId": spell.id, "source": "classic"}))
	for index: int in resolution.resolutions.size():
		var target_resolution := resolution.resolutions[index]
		events.append(DomainEvent.new(&"field_spell_resolved", {"characterId": character.id, "targetId": resolution.target_ids[index], "spellId": spell.id, "power": power, "saved": target_resolution.saved, "damage": target_resolution.damage, "healing": maxi(0, -target_resolution.damage), "duration": target_resolution.duration, "source": "classic"}))
		if target_resolution.aging != null and target_resolution.aging.changed_group():
			var target := _state.party.character_by_id(resolution.target_ids[index])
			events.append(DomainEvent.new(&"character_age_changed", target_resolution.aging.event_payload(target, _content.race_by_id(target.race_id))))
	if spell.target_type == 11 and spell.sound_end + 600 != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(spell.sound_end + 600), "waitForCompletion": false, "source": "classic-field-spell"}))
	if not CharacterAgingResult.update_payloads(events).is_empty():
		return _finish_with_age_updates(events, "completed")
	return _finish_completed(events)


static func _field_spell_target_request(request_id: String, character: CharacterState, spell: SpellDefinition, required_count: int, party: Array[CharacterState]) -> InteractionRequest:
	var eligible: Array[Dictionary] = []
	for member: CharacterState in party:
		eligible.append({"id": member.id, "name": member.name, "currentHealth": member.current_health, "maximumHealth": member.maximum_health})
	return InteractionRequest.from_payload(request_id, InteractionRequest.CHARACTER_SELECTION, {"prompt": "%s casts %s. Choose %d target%s." % [character.name, spell.name, required_count, "" if required_count == 1 else "s"], "count": required_count, "eligible": eligible, "mode": "field-spell", "spellId": spell.id})


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
	_session_interaction = _retreat_confirmation_request("session.combat-retreat:%d" % (_view_revision + 1))
	return _finish_waiting(_session_interaction, [])


static func _retreat_confirmation_request(request_id: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "Will this character flee from battle?", "Embrace Cowardice", "Stay and Fight")


static func _character_spell_confirmation_request(request_id: String, remaining: int) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "%d starting-spell selection points remain. Accept this character anyway?" % remaining, "Accept character", "Choose more spells")


static func _character_vault_confirmation_request(request_id: String, character_name: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "Publish %s as a reusable character-vault revision?" % character_name, "Publish to vault", "Keep in this party only")


func _create_party(specs: Array[CharacterCreationSpec]) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party creation is available only during party setup.")
	if _state.character_draft != null:
		return SessionStep.failed(_view_revision, &"character_draft_active", "Finish or cancel the character currently being created.")
	var maximum_party_size := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	if specs.is_empty() or specs.size() > maximum_party_size:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "This campaign allows one through %d characters." % maximum_party_size)
	var requested_levels := 0
	for requested: CharacterCreationSpec in specs:
		requested_levels += requested.starting_level
	var campaign := _content.campaign_definition()
	if campaign != null and campaign.guidance_authored and campaign.maximum_party_levels > 0 and requested_levels > campaign.maximum_party_levels:
		return SessionStep.failed(_view_revision, &"party_level_limit_exceeded", "This party's combined %d levels exceed the scenario maximum of %d." % [requested_levels, campaign.maximum_party_levels])
	var created: Array[CharacterState] = []
	var names: Dictionary = {}
	for index: int in specs.size():
		var spec: CharacterCreationSpec = specs[index]
		var validation := _character_creation_error(spec, names)
		if not validation.is_empty():
			return SessionStep.failed(_view_revision, StringName(validation["code"]), String(validation["message"]))
		var character := _create_character_from_spec(spec, "party.character.%d" % (index + 1), true, created)
		if character == null:
			return SessionStep.failed(_view_revision, &"character_creation_failed", "Realmz rules rejected a party member.")
		names[spec.name.to_lower()] = true
		created.append(character)
	var replacement := PartyState.new(_state.party.map_id, _state.party.coordinate, created)
	_state.party = replacement
	_state.experience_multiplier = _party_experience_multiplier(created, _state.difficulty, _content.campaign_definition())
	_state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in created:
		character_ids.append(character.id)
	return _finish_completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


func _begin_adventure() -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party setup is no longer active.")
	if _state.character_draft != null:
		return SessionStep.failed(_view_revision, &"character_draft_active", "Finish or cancel the character currently being created before beginning.")
	var characters := _state.party.characters()
	if characters.is_empty():
		return SessionStep.failed(_view_revision, &"empty_party", "Add or import at least one character before beginning.")
	var aggregate_error := _aggregate_party_level_error(characters)
	if not aggregate_error.is_empty():
		return SessionStep.failed(_view_revision, &"party_level_limit_exceeded", aggregate_error)
	_state.experience_multiplier = _party_experience_multiplier(characters, _state.difficulty, _content.campaign_definition())
	_state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in characters:
		character_ids.append(character.id)
	return _start_application_hook(ScenarioApplicationHooks.START_GAME, "begin-adventure", "", [DomainEvent.new(&"party_created", {"characterIds": character_ids})])


func _import_vault_character(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.VaultImportPayload
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Vault import is available only during party setup.")
	if _state.character_draft != null:
		return SessionStep.failed(_view_revision, &"character_draft_active", "Finish or cancel the character currently being created before importing from the vault.")
	if payload.character_id.is_empty() or payload.revision_hash.is_empty() or payload.character_state == null:
		return SessionStep.failed(_view_revision, &"invalid_vault_import", "A validated vault character revision is required.")
	var imported := CharacterState.from_data(payload.character_state.to_data())
	if imported == null or imported.id != payload.character_id:
		return SessionStep.failed(_view_revision, &"invalid_vault_import", "The vault character state is malformed.")
	var restrictions := _content.campaign_definition().restrictions
	var maximum_party_size := clampi(restrictions.maximum_party_size, 1, 6)
	var current_characters := _state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	if _content.race_by_id(imported.race_id) == null or _content.caste_by_id(imported.caste_id) == null:
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's race or class is not defined by this campaign.")
	if restrictions.banned_races.has(imported.race_id) or restrictions.banned_castes.has(imported.caste_id):
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The campaign restrictions reject this vault character.")
	if restrictions.maximum_level > 0 and imported.level > restrictions.maximum_level:
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character exceeds this campaign's maximum level.")
	var prospective_party := current_characters.duplicate()
	prospective_party.append(imported)
	var aggregate_error := _aggregate_party_level_error(prospective_party)
	if not aggregate_error.is_empty():
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", aggregate_error)
	var race := _content.race_by_id(imported.race_id)
	var caste := _content.caste_by_id(imported.caste_id)
	_rules.characters.ensure_age_group(imported, race, caste)
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's race cannot use that class.")
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's class is not available to that race.")
	for item: ItemInstance in imported.inventory():
		if _content.item_by_id(item.definition_id) == null:
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character carries an item unavailable in this campaign.")
	var imported_load := _rules.inventory.calculated_load(imported, _content.item_definitions())
	if imported_load < 0 or imported_load > imported.maximum_load:
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's carried wealth and items exceed this character's load limit.")
	# Vault revisions preserve item identity and equipment state, but load is derived
	# again from the target package so stale local revisions cannot bypass capacity.
	imported.carried_load = imported_load
	for spell_id: String in imported.known_spells():
		if _content.spell_by_id(spell_id) == null:
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character knows a spell unavailable in this campaign.")
	for scroll: SpellScrollState in imported.scroll_case():
		if not scroll.is_empty() and _content.spell_by_id(scroll.spell_id) == null:
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's scroll case contains a spell unavailable in this campaign.")
	for binding: FastSpellBindingState in imported.fast_spells():
		if binding.is_empty():
			continue
		var bound_spell := _content.spell_by_id(binding.spell_id)
		if bound_spell == null or not imported.known_spells().has(binding.spell_id):
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's Fast Spell bindings reference an unavailable or unknown spell.")
		if binding.power < 1 or binding.power > 7 or bound_spell.cost < 0 and binding.power != 1:
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's Fast Spell bindings contain an invalid power.")
	if _content.has_character_appearance_catalog():
		var portrait := _content.appearance_by_id(imported.portrait_id) if not imported.portrait_id.is_empty() else null
		if (portrait != null and portrait.kind != CharacterAppearanceDefinition.PORTRAIT) or (not imported.portrait_id.is_empty() and portrait == null):
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character uses a portrait unavailable in this campaign package.")
		var combat_icon := _content.appearance_by_id(imported.combat_icon_id) if not imported.combat_icon_id.is_empty() else null
		if (combat_icon != null and combat_icon.kind != CharacterAppearanceDefinition.COMBAT_ICON) or (not imported.combat_icon_id.is_empty() and combat_icon == null):
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character uses a combat icon unavailable in this campaign package.")
	for current: CharacterState in current_characters:
		if current.id == imported.id or current.name.to_lower() == imported.name.to_lower():
			return SessionStep.failed(_view_revision, &"duplicate_party_member", "That vault character is already represented in the party.")
	if not _state.party.add_character(imported):
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The validated vault character could not be added to the party.")
	return _finish_completed([DomainEvent.new(&"vault_character_imported", {"characterId": imported.id, "revisionHash": payload.revision_hash, "sourceCampaignId": payload.source_campaign_id})])


func _generate_character_draft(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CharacterDraftPayload
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Character creation is available only during party setup.")
	if payload.spec == null:
		return SessionStep.failed(_view_revision, &"invalid_character_spec", "Generate Character requires exactly one typed specification.")
	var maximum_party_size := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var current_characters := _state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	var names: Dictionary = {}
	for current: CharacterState in current_characters:
		names[current.name.to_lower()] = true
	var spec := payload.spec
	var validation := _character_creation_error(spec, names)
	if not validation.is_empty():
		return SessionStep.failed(_view_revision, StringName(validation["code"]), String(validation["message"]))
	var character_id := _state.character_draft.generated_character.id if _state.character_draft != null and _state.character_draft.generated_character != null else _next_party_character_id()
	var character := _create_character_from_spec(spec, character_id)
	if character == null:
		return SessionStep.failed(_view_revision, &"character_creation_failed", "Realmz rules rejected the character draft.")
	var draft := CharacterDraft.new()
	draft.name = spec.name
	draft.gender = spec.gender
	draft.starting_level = spec.starting_level
	draft.race_id = spec.race_id
	draft.caste_id = spec.caste_id
	draft.portrait_id = character.portrait_id
	draft.combat_icon_id = character.combat_icon_id
	draft.generated_character = character
	_state.character_draft = draft
	return _finish_completed([DomainEvent.new(&"character_draft_generated", {"characterId": character.id, "name": character.name})])


func _cancel_character_draft() -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Character creation is available only during party setup.")
	if _state.character_draft == null:
		return SessionStep.failed(_view_revision, &"no_character_draft", "There is no generated character to cancel.")
	var character_id := _state.character_draft.generated_character.id if _state.character_draft.generated_character != null else ""
	_state.character_draft = null
	return _finish_completed([DomainEvent.new(&"character_draft_cancelled", {"characterId": character_id})])


func _set_character_draft_spells(spell_ids: Array[String]) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Spell selection is available only during character creation.")
	if _state.character_draft == null or _state.character_draft.generated_character == null:
		return SessionStep.failed(_view_revision, &"no_character_draft", "Generate the character before choosing spells.")
	var character := _state.character_draft.generated_character
	var caste := _content.caste_by_id(character.caste_id)
	var candidates := _character_spell_candidates(character, caste)
	var candidate_ids: Dictionary = {}
	for spell: SpellDefinition in candidates:
		candidate_ids[spell.id] = spell
	var selected: Array[String] = []
	var spent := 0
	for spell_id: String in spell_ids:
		if selected.has(spell_id) or not candidate_ids.has(spell_id):
			return SessionStep.failed(_view_revision, &"invalid_character_spell", "The selected spell is not available to this character.")
		selected.append(spell_id)
		var spell: SpellDefinition = candidate_ids[spell_id]
		spent += _rules.characters.spell_selection_cost(spell)
	var total := _rules.characters.spell_selection_total(character, caste)
	if spent > total:
		return SessionStep.failed(_view_revision, &"character_spell_budget_exceeded", "The selected spells exceed this character's Classic selection points.")
	character.set_known_spells(selected)
	return _finish_completed([DomainEvent.new(&"character_draft_spells_changed", {"characterId": character.id, "spellIds": selected, "remaining": total - spent})])


func _finalize_character(_intent: PlayerIntent) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Character creation is available only during party setup.")
	if _state.character_draft == null or _state.character_draft.generated_character == null:
		return SessionStep.failed(_view_revision, &"no_character_draft", "Generate and review the character before finalizing it.")
	var maximum_party_size := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var current_characters := _state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	var draft := _state.character_draft
	var names: Dictionary = {}
	for current: CharacterState in current_characters:
		names[current.name.to_lower()] = true
	var validation := _character_creation_error(draft.to_creation_spec(), names)
	if not validation.is_empty():
		return SessionStep.failed(_view_revision, StringName(validation["code"]), String(validation["message"]))
	var caste := _content.caste_by_id(draft.generated_character.caste_id)
	var total := _rules.characters.spell_selection_total(draft.generated_character, caste)
	var spent := 0
	for spell_id: String in draft.generated_character.known_spells():
		spent += _rules.characters.spell_selection_cost(_content.spell_by_id(spell_id))
	var remaining := maxi(0, total - spent)
	if remaining > 0:
		var request_id := "character-spells:%s:%d" % [draft.generated_character.id, _view_revision + 1]
		_set_continuation(SessionContinuation.character_spell_confirmation(draft.generated_character.id, remaining))
		_session_interaction = _character_spell_confirmation_request(request_id, remaining)
		return _finish_waiting(_session_interaction, [DomainEvent.new(&"character_spell_confirmation_requested", {"characterId": draft.generated_character.id, "remaining": remaining})])
	return _commit_character_draft()


func _commit_character_draft(events: Array[DomainEvent] = []) -> SessionStep:
	if _state.character_draft == null or _state.character_draft.generated_character == null:
		return _finish_failed(&"no_character_draft", "The generated character is no longer available.", events)
	var maximum_party_size := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	if _state.party.characters().size() >= maximum_party_size:
		return _finish_failed(&"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size, events)
	var draft := _state.character_draft
	var character := CharacterState.from_data(draft.generated_character.to_data())
	if character == null:
		return _finish_failed(&"character_creation_failed", "Realmz rules rejected the generated character.", events)
	var party_context := _state.party.characters()
	party_context.append(character)
	var aggregate_error := _aggregate_party_level_error(party_context)
	if not aggregate_error.is_empty():
		return _finish_failed(&"party_level_limit_exceeded", aggregate_error, events)
	if not _materialize_initial_inventory(character, _content.caste_by_id(character.caste_id), party_context) or not _state.party.add_character(character):
		return _finish_failed(&"character_creation_failed", "Realmz rules rejected the generated character.", events)
	_state.character_draft = null
	events.append(DomainEvent.new(&"character_finalized", {"characterId": character.id}))
	var request_id := "character-vault:%s:%d" % [character.id, _view_revision + 1]
	_set_continuation(SessionContinuation.character_vault_publication(character.id))
	_session_interaction = _character_vault_confirmation_request(request_id, character.name)
	events.append(DomainEvent.new(&"character_vault_confirmation_requested", {"characterId": character.id}))
	return _finish_waiting(_session_interaction, events)


func _aggregate_party_level_error(characters: Array[CharacterState]) -> String:
	var campaign := _content.campaign_definition()
	if campaign == null or not campaign.guidance_authored or campaign.maximum_party_levels <= 0:
		return ""
	var current_levels := 0
	for character: CharacterState in characters:
		current_levels += character.level
	if current_levels <= campaign.maximum_party_levels:
		return ""
	return "This party's combined %d levels exceed the scenario maximum of %d." % [current_levels, campaign.maximum_party_levels]


static func _party_experience_multiplier(characters: Array[CharacterState], difficulty: int, campaign: CampaignDefinition) -> float:
	if campaign == null or not campaign.guidance_authored or campaign.recommended_party_levels <= 0:
		return 1.0
	var current_levels := 0
	for character: CharacterState in characters:
		current_levels += character.level
	var multiplier := PartySetupRules.experience_multiplier(campaign.recommended_party_levels, current_levels, difficulty)
	return 1.0 if multiplier <= 0.0 else multiplier


func _character_creation_error(spec: CharacterCreationSpec, existing_names: Dictionary) -> Dictionary:
	if spec == null:
		return {"code": &"invalid_character_spec", "message": "A character specification is required."}
	if spec.name.is_empty() or spec.name.length() > 24 or spec.gender not in [1, 2]:
		return {"code": &"invalid_character_spec", "message": "Every party member requires a valid name and gender."}
	if not CharacterRules.STARTING_LEVELS.has(spec.starting_level):
		return {"code": &"invalid_starting_level", "message": "Starting level must be one of Castle's fixed character-creation choices."}
	if existing_names.has(spec.name.to_lower()):
		return {"code": &"duplicate_character_name", "message": "Party member names must be unique."}
	var race := _content.race_by_id(spec.race_id)
	var caste := _content.caste_by_id(spec.caste_id)
	if race == null or caste == null:
		return {"code": &"unknown_character_definition", "message": "Party creation references an unavailable race or caste."}
	var restrictions := _content.campaign_definition().restrictions
	if restrictions.banned_races.has(race.id):
		return {"code": &"restricted_race", "message": "This campaign does not allow the selected race."}
	if restrictions.banned_castes.has(caste.id):
		return {"code": &"restricted_caste", "message": "This campaign does not allow the selected class."}
	if restrictions.maximum_level > 0 and spec.starting_level > restrictions.maximum_level:
		return {"code": &"restricted_starting_level", "message": "This campaign allows characters only through level %d." % restrictions.maximum_level}
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return {"code": &"incompatible_race_class", "message": "The selected race cannot use that class."}
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return {"code": &"incompatible_class_race", "message": "The selected class is not available to that race."}
	if _content.has_character_appearance_catalog():
		var appearance := _resolved_character_appearance(spec, race)
		if appearance.is_empty():
			return {"code": &"invalid_character_appearance", "message": "The selected portrait or combat icon is unavailable in this campaign package."}
	return {}


func _create_character_from_spec(spec: CharacterCreationSpec, character_id: String, add_starting_items: bool = false, party_context: Array[CharacterState] = []) -> CharacterState:
	var race := _content.race_by_id(spec.race_id)
	var character := _rules.characters.create_character(character_id, spec.name, race, _content.caste_by_id(spec.caste_id), spec.gender, _rng, false, spec.starting_level)
	if character == null:
		return null
	var appearance := _resolved_character_appearance(spec, race)
	character.portrait_id = String(appearance.get("portraitId", spec.portrait_id))
	character.combat_icon_id = String(appearance.get("combatIconId", spec.combat_icon_id))
	if add_starting_items:
		var equipment_context := party_context.duplicate()
		equipment_context.append(character)
		if not _materialize_initial_inventory(character, _content.caste_by_id(spec.caste_id), equipment_context):
			return null
	return character


func _materialize_initial_inventory(character: CharacterState, caste: CasteDefinition, party_context: Array[CharacterState]) -> bool:
	if character == null or caste == null or not character.inventory().is_empty():
		return false
	var definitions := _content.item_definitions()
	character.carried_load = _rules.inventory.calculated_load(character, definitions)
	if character.carried_load < 0 or character.carried_load > character.maximum_load:
		return false
	var added: Array[ItemInstance] = []
	for index: int in caste.start_items().size():
		var definition := _content.item_by_id(caste.start_items()[index])
		if definition == null:
			return false
		var instance := _rules.inventory.add_item(character, definition, "%s.item.%d" % [character.id, index], true)
		# Castle tests capacity before writing the item record. Its separate numitems
		# counter advances too early; the direct model keeps only records that fit.
		if instance != null:
			added.append(instance)
	var race := _content.race_by_id(character.race_id)
	for instance: ItemInstance in added:
		var definition := _content.item_by_id(instance.definition_id)
		_rules.inventory.equip_classic(character, instance, definition, race, caste, party_context, definitions)
	return _rules.inventory.calculated_load(character, definitions) == character.carried_load


static func _party_inventory_is_valid(content: RealmzContent, state: GameState, rules: RealmzRules) -> bool:
	if content == null or state == null or rules == null:
		return false
	var definitions := content.item_definitions()
	for character: CharacterState in state.party.characters():
		if rules.inventory.calculated_load(character, definitions) != character.carried_load:
			return false
		for scroll: SpellScrollState in character.scroll_case():
			if not scroll.is_empty() and content.spell_by_id(scroll.spell_id) == null:
				return false
	return true


static func _party_fast_spells_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for character: CharacterState in state.party.characters():
		for binding: FastSpellBindingState in character.fast_spells():
			if binding.is_empty():
				continue
			var spell := content.spell_by_id(binding.spell_id)
			if spell == null or not character.known_spells().has(binding.spell_id) or binding.power < 1 or binding.power > 7 or spell.cost < 0 and binding.power != 1:
				return false
	return true


static func _party_appearance_is_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	if not content.has_character_appearance_catalog():
		return true
	for character: CharacterState in state.party.characters():
		if not character.portrait_id.is_empty():
			var portrait := content.appearance_by_id(character.portrait_id)
			if portrait == null or portrait.kind != CharacterAppearanceDefinition.PORTRAIT:
				return false
		if not character.combat_icon_id.is_empty():
			var icon := content.appearance_by_id(character.combat_icon_id)
			if icon == null or icon.kind != CharacterAppearanceDefinition.COMBAT_ICON:
				return false
	return true


static func _shop_state_is_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	if not state.active_shop_id.is_empty() and content.shop_by_id(state.active_shop_id) == null:
		return false
	for shop_id: Variant in state.shop_buyback_overrides():
		if content.shop_by_id(String(shop_id)) == null:
			return false
		for item_id: Variant in state.shop_buyback_overrides()[shop_id]:
			if content.item_by_id(String(item_id)) == null:
				return false
	return true


static func _location_notes_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	var counts: Dictionary = {}
	var ordinals: Dictionary = {}
	for note: LocationNoteState in state.world.location_notes():
		var map := content.world.map_by_id(note.map_id)
		if map == null or map.level_type != note.map_kind or map.level_index != note.level_index or note.native_location_id != LocationNoteState.native_id_for(map.level_index, note.coordinate) or map.topology.cell_at(note.coordinate) == null or note.text.is_empty() or not LocationNoteState.text_is_valid(note.text):
			return false
		counts[note.map_kind] = int(counts.get(note.map_kind, 0)) + 1
		var ordinal_key := "%s:%d" % [String(note.map_kind), note.record_ordinal]
		if ordinals.has(ordinal_key):
			return false
		ordinals[ordinal_key] = true
		if int(counts[note.map_kind]) > LocationNoteState.MAX_NOTES_PER_MAP_KIND:
			return false
	return true


static func _journal_messages_are_valid(content: RealmzContent, state: GameState) -> bool:
	for message_id: int in state.journal_message_ids():
		if not GameState.journal_message_id_is_valid(message_id) or content.message_by_id(message_id) == null:
			return false
	return true


static func _acquired_player_maps_are_valid(content: RealmzContent, state: GameState) -> bool:
	if content == null or state == null:
		return false
	for player_map_id: String in state.world.acquired_map_ids():
		if content.world.player_map_by_id(player_map_id) == null:
			return false
	return true


func _resolved_character_appearance(spec: CharacterCreationSpec, race: RaceDefinition) -> Dictionary:
	if not _content.has_character_appearance_catalog():
		return {"portraitId": spec.portrait_id, "combatIconId": spec.combat_icon_id}
	var default_portrait_resource := 257 if race.default_icon_set == 0 else 251 + race.default_icon_set * 6
	var portrait := _content.appearance_by_id(spec.portrait_id) if not spec.portrait_id.is_empty() else _content.appearance_by_resource(CharacterAppearanceDefinition.PORTRAIT, default_portrait_resource)
	if portrait == null or portrait.kind != CharacterAppearanceDefinition.PORTRAIT:
		return {}
	var icon := _content.appearance_by_id(spec.combat_icon_id) if not spec.combat_icon_id.is_empty() else _content.appearance_by_resource(CharacterAppearanceDefinition.COMBAT_ICON, 9000 - 257 + portrait.classic_resource_id)
	if icon == null or icon.kind != CharacterAppearanceDefinition.COMBAT_ICON:
		return {}
	return {"portraitId": portrait.id, "combatIconId": icon.id}


func _next_party_character_id() -> String:
	var character_id := _state.next_instance_id("party.character")
	while _state.party.character_by_id(character_id) != null:
		character_id = _state.next_instance_id("party.character")
	return character_id


func _search() -> SessionStep:
	if _state.party_camping:
		return SessionStep.failed(_view_revision, &"search_while_camped", "Search is replaced by scroll scribing while camped.")
	_state.mark_searched(_state.party.map_id, _state.party.coordinate)
	var current_map := _content.world.map_by_id(_state.party.map_id)
	var discovered: Array[String] = []
	var first_roll: int = 0
	for y: int in range(_state.party.coordinate.y - 1, _state.party.coordinate.y + 2):
		for x: int in range(_state.party.coordinate.x - 1, _state.party.coordinate.x + 2):
			var cell := current_map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			for feature: MapFeature in cell.features():
				if feature.kind != &"secret" or _state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
					continue
				var roll := _rng.draw(100, StringName("exploration.search.%s" % feature.id))
				if first_roll == 0:
					first_roll = roll
				if roll <= 100:
					_state.world.discover_secret(feature.id)
					discovered.append(feature.id)
	var events: Array[DomainEvent] = [DomainEvent.new("search_completed", {"mapId": _state.party.map_id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "roll": first_roll, "discoveredSecrets": discovered})]
	events.append_array(_rules.clock.advance_minutes(_state, _content, 1))
	for secret_id: String in discovered:
		events.append(DomainEvent.new("secret_discovered", {"secretId": secret_id}))
	return _finish_with_age_updates(events, "completed")


func _move(direction: Vector2i) -> SessionStep:
	var movement := _content.world.probe_movement(_state.party.map_id, _state.party.coordinate, direction, _state.world)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return SessionStep.failed(_view_revision, &"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	if _state.bank_available and _has_pooled_wealth(_state.party):
		var banked := _state.party.pooled_wealth.to_data()
		_rules.economy.pool_to_bank(_state.party)
		_state.bank_available = false
		return _move_after_pooled_wealth(direction, [DomainEvent.new(&"pooled_wealth_banked_before_movement", {"wealth": banked, "direction": [direction.x, direction.y]})])
	if not _state.bank_available and _has_pooled_wealth(_state.party):
		_set_continuation(SessionContinuation.pooled_wealth_departure(&"warning", direction))
		_session_interaction = _pooled_wealth_departure_warning("pooled-wealth-departure:%d" % (_view_revision + 1))
		return _finish_waiting(_session_interaction, [
			DomainEvent.new(&"pooled_wealth_departure_warning", {"wealth": _state.party.pooled_wealth.to_data(), "direction": [direction.x, direction.y]}),
			DomainEvent.new(&"sound_requested", {"soundId": 20005, "waitForCompletion": false, "stopExisting": true, "source": "classic-pooled-wealth-departure-question"}),
		])
	return _move_after_pooled_wealth(direction)


func _move_after_pooled_wealth(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionStep:
	if _state.party_camping:
		return _depart_camp_and_move(direction, preceding_events)
	return _commit_move(direction, preceding_events)


func _depart_camp_and_move(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionStep:
	var movement := _content.world.probe_movement(_state.party.map_id, _state.party.coordinate, direction, _state.world)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return SessionStep.failed(_view_revision, &"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	var map := _content.world.map_by_id(_state.party.map_id)
	if map == null:
		return SessionStep.failed(_view_revision, &"unknown_map", "The current map is unavailable for camp departure.")
	_state.party_camping = false
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"camp_mode_changed", {"camping": false, "source": "classic-movement"}))
	events.append(DomainEvent.new(&"camp_departed_for_movement", {"mapId": map.id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "direction": [direction.x, direction.y], "source": "classic"}))
	var timeclicks := 2 if map.level_type == &"dungeon" else 15
	var previous_day := _state.clock.day()
	events.append_array(_rules.clock.advance_classic_field_time(_state, _content, timeclicks, _classic_time_scale(map), true))
	_set_post_time_continuation(map, "move", direction, true, _state.clock.day() if _state.clock.day() != previous_day else 0, _state.party.coordinate + direction)
	return _finish_with_age_updates(events, &"post-clock", _session_continuation.copy())


func _commit_move(direction: Vector2i, preceding_events: Array[DomainEvent] = []) -> SessionStep:
	var movement := _content.world.probe_movement(_state.party.map_id, _state.party.coordinate, direction, _state.world)
	if not movement.allowed and movement.reason == &"invalid_direction":
		return SessionStep.failed(_view_revision, &"invalid_direction", "Movement requires a cardinal direction, or a diagonal direction on a land map.")
	if not movement.allowed:
		var blocked_events: Array[DomainEvent] = []
		blocked_events.assign(preceding_events)
		blocked_events.append(DomainEvent.new(&"movement_blocked", {"reason": String(movement.reason)}))
		var attempt_cost := _blocked_land_attempt_cost(movement)
		if attempt_cost > 0:
			var previous_day := _state.clock.day()
			blocked_events.append_array(_rules.clock.advance_classic_field_time(_state, _content, attempt_cost, _classic_time_scale(movement.source_map), true))
			_set_post_time_continuation(movement.source_map, "completed", Vector2i.ZERO, true, _state.clock.day() if _state.clock.day() != previous_day else 0, movement.target_coordinate)
			return _finish_with_age_updates(blocked_events, &"post-clock", _session_continuation.copy())
		return _finish_completed(blocked_events)
	var target_map := movement.target_map
	var target_coordinate := movement.target_coordinate
	var transition := movement.transition
	var probe := movement.topology_result
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	if not probe.door_id.is_empty() and not _state.world.door_is_open(probe.door_id):
		_state.world.open_door(probe.door_id)
		events.append(DomainEvent.new("door_opened", {"doorId": probe.door_id}))
	if not probe.secret_id.is_empty() and not _state.world.secret_is_discovered(probe.secret_id):
		_state.world.discover_secret(probe.secret_id)
		events.append(DomainEvent.new("secret_discovered", {"secretId": probe.secret_id, "byMovement": true}))
	var source_map_id := _state.party.map_id
	var source_coordinate := _state.party.coordinate
	var cleared_services := not _state.active_shop_id.is_empty() or _state.temple_available or _state.bank_available
	if _state.bank_available:
		_rules.economy.pool_to_bank(_state.party)
	_state.clear_location_services()
	if cleared_services:
		events.append(DomainEvent.new(&"location_services_cleared", {"mapId": source_map_id, "x": source_coordinate.x, "y": source_coordinate.y}))
	_state.party.map_id = target_map.id
	_state.party.coordinate = target_coordinate
	_state.last_move_direction = direction
	_state.world.mark_visited(target_map.id, target_coordinate)
	events.append(DomainEvent.new("party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": target_coordinate.x, "y": target_coordinate.y}))
	var previous_day := _state.clock.day()
	events.append_array(_rules.clock.advance_classic_field_time(_state, _content, probe.target_cell.movement_cost, _classic_time_scale(target_map), true))
	if transition != null:
		events.append(DomainEvent.new("map_transitioned", {"transitionId": transition.id, "sourceMapId": source_map_id, "targetMapId": target_map.id}))
	_set_post_time_continuation(target_map, "post-move", Vector2i.ZERO, false, _state.clock.day() if _state.clock.day() != previous_day else 0, target_coordinate)
	return _finish_with_age_updates(events, &"post-clock", _session_continuation.copy())


func _classic_time_scale(map: MapDefinition) -> int:
	return 1 if map != null and map.level_type == &"dungeon" else 5


func _blocked_land_attempt_cost(movement: WorldMovementResult) -> int:
	if movement == null or movement.source_map == null or movement.source_map.level_type != &"land" or _state.party_in_boat:
		return 0
	if movement.reason not in [&"terrain_blocked", &"secret_hidden"] or movement.topology_result == null or movement.topology_result.target_cell == null:
		return 0
	return maxi(0, movement.topology_result.target_cell.movement_cost)


func _set_post_time_continuation(map: MapDefinition, resume_kind: String, direction: Vector2i = Vector2i.ZERO, check_random: bool = true, timed_day: int = 0, timed_coordinate: Vector2i = Vector2i(-1, -1)) -> void:
	var cell := map.topology.cell_at(_state.party.coordinate)
	var exploration := SessionContinuation.ExplorationBody.new()
	exploration.map_id = map.id
	exploration.coordinate = _state.party.coordinate
	exploration.timed_day = timed_day
	exploration.timed_encounter_index = 0
	exploration.active_timed_program_id = ""
	exploration.midnight_recovery_pending = timed_day > 0
	exploration.timed_check_coordinate = timed_coordinate
	exploration.check_random = check_random
	exploration.random_region_ids.assign([] if cell == null else cell.random_rect_ids())
	exploration.random_region_index = -1 if cell == null else cell.random_rect_ids().size() - 1
	exploration.active_random_program_id = ""
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	exploration.resume_kind = StringName(resume_kind)
	exploration.direction = direction
	_set_continuation(SessionContinuation.post_clock(exploration))


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
		return _commit_move(direction, events)
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
		var started := _scenario_vm.start_program(trigger.program_id, {"callingContext": "action", "triggerId": trigger.id, "mapId": map.id, "x": exploration.timed_check_coordinate.x, "y": exploration.timed_check_coordinate.y, "timedEncounterId": encounter.id})
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
	var exploration := _session_continuation.exploration()
	if exploration == null or not exploration.midnight_recovery_pending:
		return
	exploration.midnight_recovery_pending = false
	events.append_array(_rules.clock.restore_half_day_health(_state.party, _content))


func _rebase_post_time_location() -> bool:
	var exploration := _session_continuation.exploration()
	if _session_continuation.kind != &"post-clock" or exploration == null:
		return false
	var map := _content.world.map_by_id(_state.party.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(_state.party.coordinate)
	if cell == null:
		return false
	exploration.map_id = map.id
	exploration.coordinate = _state.party.coordinate
	exploration.timed_check_coordinate = _state.party.coordinate
	exploration.random_region_ids.assign(cell.random_rect_ids())
	exploration.random_region_index = cell.random_rect_ids().size() - 1
	return true


func _timed_encounter_requirements_met(encounter: TimedEncounterDefinition, map: MapDefinition) -> bool:
	if encounter.required_item_id > 0 and not _party_has_classic_item(encounter.required_item_id):
		return false
	if encounter.required_quest_id > -1 and not _state.quest_is_set(encounter.required_quest_id):
		return false
	if encounter.location_kind == TimedEncounterDefinition.LocationKind.ANY:
		return true
	if encounter.location_kind == TimedEncounterDefinition.LocationKind.LAND and map.level_type != &"land" or encounter.location_kind == TimedEncounterDefinition.LocationKind.DUNGEON and map.level_type != &"dungeon":
		return false
	if map.level_index != encounter.required_level:
		return false
	var exploration := _session_continuation.exploration()
	if exploration == null:
		return false
	var coordinate := exploration.timed_check_coordinate
	if encounter.required_random_rectangle > -1:
		var region := map.random_region_by_index(encounter.required_random_rectangle)
		if region == null or not region.bounds.has_point(coordinate):
			return false
	if encounter.required_x > -1 and coordinate.x != encounter.required_x:
		return false
	if encounter.required_y > -1 and coordinate.y != encounter.required_y:
		return false
	return true


func _party_has_classic_item(classic_item_id: int) -> bool:
	var definition := _content.item_by_classic_id(classic_item_id)
	if definition == null:
		return false
	for character: CharacterState in _state.party.characters():
		for item: ItemInstance in character.inventory():
			if item.definition_id == definition.id:
				return true
	return false


func _set_post_move_continuation(map: MapDefinition, coordinate: Vector2i, destination_depth: int = 0) -> void:
	var cell := map.topology.cell_at(coordinate)
	var exploration := SessionContinuation.ExplorationBody.new()
	exploration.map_id = map.id
	exploration.coordinate = coordinate
	exploration.trigger_ids.assign(_selected_placed_trigger_ids(_content, cell))
	exploration.trigger_index = 0
	exploration.active_trigger_id = ""
	exploration.random_region_ids.assign(cell.random_rect_ids())
	exploration.random_region_index = cell.random_rect_ids().size() - 1
	exploration.active_random_program_id = ""
	exploration.active_random_region_id = ""
	exploration.random_battle_stage = &""
	exploration.action_point_destination_depth = destination_depth
	_set_continuation(SessionContinuation.post_move(exploration))


func _normalize_age_groups(state: GameState, content: RealmzContent, rules: RealmzRules) -> void:
	for character: CharacterState in state.party.characters():
		var race := content.race_by_id(character.race_id)
		var caste := content.caste_by_id(character.caste_id)
		if race != null and caste != null:
			rules.characters.ensure_age_group(character, race, caste)


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
		var started := _scenario_vm.start_program(trigger.program_id, {"callingContext": "action", "triggerId": trigger.id, "mapId": map.id, "x": coordinate.x, "y": coordinate.y})
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
	var suspended_vm: Dictionary = body.suspended_vm.duplicate(true)
	var suspended_owner := body.suspended_owner
	var vm_handoff: Dictionary = body.vm_handoff.duplicate(true)
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
	if result == null or result.state != ScenarioVmResult.State.SUSPENDED or not result.handoff.get("runtime") is Dictionary:
		_session_continuation.clear()
		return _finish_failed(&"invalid_vm_handoff", "The Scenario VM did not provide a typed application handoff.", events)
	if _session_continuation.kind not in [&"post-clock", &"post-move"]:
		_session_continuation.clear()
		return _finish_failed(&"unsupported_vm_handoff_owner", "Total-party defeat cannot suspend this scenario caller.", events)
	var saved := _scenario_vm.snapshot()
	if not ScenarioVm.handoff_is_valid(result.handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_content, _state, result.handoff["runtime"]):
		_session_continuation.clear()
		return _finish_failed(&"invalid_party_defeat_handoff", "The Scenario VM total-party defeat handoff is invalid.", events)
	var suspended := SessionContinuation.ApplicationBody.new()
	suspended.suspended_vm = saved.to_data()
	suspended.suspended_owner = _session_continuation.copy()
	suspended.vm_handoff = result.handoff.duplicate(true)
	_scenario_vm.reset()
	return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, &"scenario-party-defeat", "", events, suspended)


func _resume_scenario_party_defeat(suspended_vm_data: Dictionary, suspended_owner: SessionContinuation, vm_handoff: Dictionary, events: Array[DomainEvent]) -> SessionStep:
	var saved := ScenarioVmSnapshot.from_data(suspended_vm_data)
	if not ScenarioVm.handoff_is_valid(vm_handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_content, _state, vm_handoff.get("runtime")) or not _valid_suspended_scenario_owner(_content, _state, suspended_owner, saved):
		return _finish_failed(&"invalid_party_defeat_handoff", "The saved scenario defeat continuation is invalid.", events)
	var restored_vm := ScenarioVm.new()
	restored_vm.configure(_content.scenario)
	if not restored_vm.restore(saved):
		return _finish_failed(&"invalid_vm_state", "The suspended scenario cannot be restored after Party Death.", events)
	var operation := _runtime_api.complete_party_defeat_handoff(vm_handoff["runtime"])
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
	var started := _scenario_vm.start_program(program_id, {
		"callingContext": "monster-death-macro",
		"battleId": combat.battle_id,
		"combatantId": combatant_id,
		"classicMonsterId": int(request.get("classicMonsterId", 0)),
		"traitor": bool(request.get("traitor", monster.traitor)),
	})
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
	var return_continuation := _state.combat.return_continuation.copy()
	var battle_outcome := _state.combat.outcome
	events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": String(battle_outcome)}))
	_state.combat = null
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionStep:
	var return_continuation := _state.combat.return_continuation.copy()
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
				var started := _scenario_vm.start_program(program_id, {"callingContext": "action", "mapId": map.id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "randomRegionId": region.id})
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


static func _pooled_wealth_departure_warning(request_id: String) -> InteractionRequest:
	return InteractionRequest.yes_no(request_id, "The party still has wealth in the shared pool. Distribute it before leaving?", "Distribute", "Leave it behind")


func _pooled_wealth_departure_distribution_request(request_id: String, selected_character_id: String = "") -> InteractionRequest:
	return _pooled_wealth_departure_distribution_request_for_state(_state, request_id, selected_character_id)


static func _pooled_wealth_departure_distribution_request_for_state(state: GameState, request_id: String, selected_character_id: String = "") -> InteractionRequest:
	var economy := EconomyRules.new()
	var characters: Array[Dictionary] = []
	for character: CharacterState in state.party.characters():
		var transfers: Array[Dictionary] = []
		for denomination: String in ["gold", "gems", "jewelry"]:
			var kind := _money_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, true)
			transfers.append({"denomination": denomination, "amount": amount, "toPool": _economy_action_payload(to_pool), "toCharacter": _economy_action_payload(to_character)})
		characters.append({"id": character.id, "name": character.name, "wealth": character.money.to_data(), "load": character.carried_load, "maximumLoad": character.maximum_load, "transfers": transfers})
	if state.party.character_by_id(selected_character_id) == null and not characters.is_empty():
		selected_character_id = characters[0]["id"]
	return InteractionRequest.from_payload(request_id, InteractionRequest.POOLED_WEALTH_DEPARTURE, {
		"mode": "departure",
		"selectedCharacterId": selected_character_id,
		"pooledWealth": state.party.pooled_wealth.to_data(),
		"bankedWealth": state.party.banked_wealth.to_data(),
		"pool": _economy_action_payload(economy.pool_probe(state.party)),
		"share": _economy_action_payload(economy.share_probe(state.party)),
		"characters": characters,
	})


static func _economy_action_payload(probe: EconomyActionProbe) -> Dictionary:
	return {"enabled": probe != null and probe.allowed, "reason": "" if probe != null and probe.allowed else "Action availability is unavailable." if probe == null else probe.reason}


static func _has_pooled_wealth(party: PartyState) -> bool:
	return party != null and (party.pooled_wealth.gold != 0 or party.pooled_wealth.gems != 0 or party.pooled_wealth.jewelry != 0)


func _respond_item_use_target(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Item use requires an ordered characterIds array.")
	var target_ids := body.character_ids.duplicate()
	var targeting := _session_continuation.targeting()
	if targeting == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The item target continuation is unavailable.")
	var character_id := targeting.character_id
	var instance_id := targeting.instance_id
	var spell_id := targeting.spell_id
	var power := targeting.power
	var expected_count := targeting.target_count
	if target_ids.size() != expected_count:
		return SessionStep.failed(_view_revision, &"invalid_item_use_target", "The item requires exactly %d target%s." % [expected_count, "" if expected_count == 1 else "s"])
	var character := _state.party.character_by_id(character_id)
	var instance := _item_instance(character, instance_id)
	if instance == null or instance.charges != targeting.starting_charges:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The item awaiting a target no longer matches its committed state.")
	var saved_continuation := _session_continuation.copy()
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _commit_field_spell_item(character_id, instance_id, spell_id, power, target_ids)
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
	if targeting == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The field-spell target continuation is unavailable.")
	var expected_count := targeting.target_count
	if target_ids.size() != expected_count:
		return SessionStep.failed(_view_revision, &"invalid_field_spell_target", "The spell requires exactly %d target%s." % [expected_count, "" if expected_count == 1 else "s"])
	var character_id := targeting.character_id
	var spell_id := targeting.spell_id
	var power := targeting.power
	var character := _state.party.character_by_id(character_id)
	if character == null or character.spell_points != targeting.starting_spell_points:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The field spell awaiting a target no longer matches its committed state.")
	var saved_continuation := _session_continuation.copy()
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _commit_field_spell(character_id, spell_id, power, target_ids)
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
	if targeting == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The scroll target continuation is unavailable.")
	var expected_count := targeting.target_count
	if target_ids.size() != expected_count:
		return SessionStep.failed(_view_revision, &"invalid_scroll_target", "The scroll requires exactly %d target%s." % [expected_count, "" if expected_count == 1 else "s"])
	var character_id := targeting.character_id
	var slot_index := targeting.scroll_slot
	var spell_id := targeting.spell_id
	var power := targeting.power
	var character := _state.party.character_by_id(character_id)
	var scroll := character.scroll_at(slot_index) if character != null else null
	if scroll == null or scroll.spell_id != spell_id or scroll.power != power:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The scroll awaiting a target no longer matches its committed state.")
	var saved_continuation := _session_continuation.copy()
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _commit_field_scroll(character_id, slot_index, spell_id, power, target_ids)
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
	if service == null or service.runtime_continuation.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The pending service has no runtime continuation.")
	var result := _runtime_api.resume_classic(service.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		service.runtime_continuation = result.continuation.duplicate(true)
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
	var updates := CharacterAgingResult.update_payloads(events)
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
	age.updates.assign(updates)
	age.index = 1
	age.resume_kind = resume_kind
	age.resume_continuation = null if resume_continuation == null else resume_continuation.copy()
	_set_continuation(SessionContinuation.age_updates(age))
	_session_interaction = InteractionRequest.age_update(_session_age_update_request_id(updates[0], 0), updates[0])
	events.append(CharacterAgingResult.sound_event(updates[0]))
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
	var acknowledged: Dictionary = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.get("characterId", "")})]
	if index < updates.size():
		var next_payload: Dictionary = updates[index]
		age.index = index + 1
		_session_interaction = InteractionRequest.age_update(_session_age_update_request_id(next_payload, index), next_payload)
		events.append(CharacterAgingResult.sound_event(next_payload))
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


func _session_age_update_request_id(payload: Dictionary, index: int) -> String:
	return "session.age-update:%s:%d:%d" % [payload.get("characterId", "character"), _view_revision + 1, index]


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
	if continuation.runtime_continuation.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The battle reward continuation is unavailable.")
	var return_continuation := _state.combat.return_continuation.copy()
	var battle_outcome := _state.combat.outcome
	var result := _runtime_api.resume_classic(continuation.runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		continuation.runtime_continuation = result.continuation.duplicate(true)
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
		_state.combat.return_continuation = _session_continuation.copy()
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


static func _valid_session_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	if continuation == null or continuation.is_empty():
		return false
	match continuation.kind:
		&"application-hook":
			var application := continuation.application()
			if application == null or vm_interaction == null or session_interaction != null or application.program_id.is_empty():
				return false
			if content.scenario.application_hook_program_id(application.hook) != application.program_id or content.scenario.program_by_id(application.program_id) == null:
				return false
			match application.resume_kind:
				&"begin-adventure":
					return application.hook == ScenarioApplicationHooks.START_GAME and application.service_id.is_empty() and state.party_setup_completed and not state.party.characters().is_empty()
				&"service":
					return application.hook in [ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE] and not application.service_id.is_empty() and ((application.service_id == state.active_shop_id and content.shop_by_id(application.service_id) != null) or (application.service_id == "realmz.service.temple" and state.temple_available))
				&"end-adventure":
					return application.hook == ScenarioApplicationHooks.END_ADVENTURE and application.service_id.is_empty()
				&"end-adventure-close":
					return application.hook == ScenarioApplicationHooks.PARTY_DEATH and application.service_id.is_empty()
				&"party-defeat":
					return application.hook == ScenarioApplicationHooks.PARTY_DEATH and application.service_id.is_empty() and state.combat != null and state.combat.completed and state.combat.outcome == &"defeat"
				&"scenario-party-defeat":
					if application.hook != ScenarioApplicationHooks.PARTY_DEATH or not application.service_id.is_empty() or application.suspended_owner == null:
						return false
					var saved := ScenarioVmSnapshot.from_data(application.suspended_vm)
					return ScenarioVm.handoff_is_valid(application.vm_handoff, saved) and RealmzRuntimeApi.party_defeat_handoff_is_valid(content, state, application.vm_handoff.get("runtime")) and _valid_suspended_scenario_owner(content, state, application.suspended_owner, saved)
			return false
		&"pooled-wealth-departure":
			var service := continuation.service()
			if service == null or vm_interaction != null or session_interaction == null or state.party == null or state.bank_available:
				return false
			var departure_probe := content.world.probe_movement(state.party.map_id, state.party.coordinate, service.direction, state.world)
			if not departure_probe.allowed and departure_probe.reason == &"invalid_direction":
				return false
			if service.stage == &"warning":
				return _has_pooled_wealth(state.party) and session_interaction.to_data() == _pooled_wealth_departure_warning(session_interaction.request_id).to_data()
			if service.stage == &"distribution":
				var bank_body := session_interaction.body as InteractionRequest.BankRequestBody
				return session_interaction.kind == InteractionRequest.POOLED_WEALTH_DEPARTURE and bank_body != null and bank_body.mode == &"departure" and state.party.character_by_id(bank_body.selected_character_id) != null and session_interaction.to_data() == _pooled_wealth_departure_distribution_request_for_state(state, session_interaction.request_id, bank_body.selected_character_id).to_data()
			return false
		&"service-interaction":
			var service := continuation.service()
			if service == null or vm_interaction != null or session_interaction == null:
				return false
			var runtime := service.runtime_continuation
			var selected_temple_character: Variant = runtime.get("selectedCharacterId")
			match StringName(runtime.get("kind", "")):
				&"classic-shop":
					return service.service_id == state.active_shop_id and not service.service_id.is_empty() and content.shop_by_id(service.service_id) != null and session_interaction.kind == InteractionRequest.SHOP
				&"classic-temple":
					var temple_body := session_interaction.body as InteractionRequest.TempleRequestBody
					return service.service_id == "realmz.service.temple" and state.temple_available and int(runtime.get("costPercent", -100_000)) == state.temple_cost_percent and bool(runtime.get("bankAvailable", false)) == state.bank_available and selected_temple_character is String and state.party.character_by_id(String(selected_temple_character)) != null and session_interaction.kind == InteractionRequest.TEMPLE and temple_body != null and temple_body.selected_character_id == selected_temple_character
				&"classic-temple-exit":
					return service.service_id == "realmz.service.temple" and state.temple_available and not state.bank_available and int(runtime.get("costPercent", -100_000)) == state.temple_cost_percent and not bool(runtime.get("bankAvailable", true)) and selected_temple_character is String and state.party.character_by_id(String(selected_temple_character)) != null and session_interaction.kind == InteractionRequest.YES_NO
				&"classic-banking":
					return service.service_id == "realmz.service.bank" and state.bank_available and session_interaction.kind == InteractionRequest.BANK
			return false
		&"drop-item-confirmation", &"item-use-target-selection", &"field-spell-target-selection", &"scroll-target-selection":
			return _valid_targeting_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"character-spell-confirmation":
			var application := continuation.application()
			if application == null or vm_interaction != null or session_interaction == null or state.party_setup_completed or state.character_draft == null or state.character_draft.generated_character == null:
				return false
			var character := state.character_draft.generated_character
			if application.character_id != character.id or application.remaining < 1:
				return false
			var rules := RealmzRules.new()
			var spent := 0
			for spell_id: String in character.known_spells():
				spent += rules.characters.spell_selection_cost(content.spell_by_id(spell_id))
			var remaining := maxi(0, rules.characters.spell_selection_total(character, content.caste_by_id(character.caste_id)) - spent)
			return remaining == application.remaining and session_interaction.to_data() == _character_spell_confirmation_request(session_interaction.request_id, remaining).to_data()
		&"character-vault-publication":
			var application := continuation.application()
			if application == null or vm_interaction != null or session_interaction == null or state.party_setup_completed:
				return false
			var character := state.party.character_by_id(application.character_id)
			return character != null and session_interaction.to_data() == _character_vault_confirmation_request(session_interaction.request_id, character.name).to_data()
		&"combat-retreat-confirmation":
			var combat := continuation.combat()
			if combat == null or combat.mode not in [&"explicit", &"edge"] or vm_interaction != null or session_interaction == null or session_interaction.to_data() != _retreat_confirmation_request(session_interaction.request_id).to_data():
				return false
			if state.combat == null or state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.active_actor_id() != combat.actor_id:
				return false
			var rules := RealmzRules.new()
			var probe: Variant = rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), combat.actor_id) if combat.mode == &"explicit" else rules.combat_flow.probe_edge_retreat(state.combat, combat.actor_id, combat.destination)
			return probe.allowed and not probe.forced
		&"age-updates":
			var age := continuation.age()
			if age == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.AGE_UPDATE or age.updates.is_empty() or age.index < 1 or age.index > age.updates.size():
				return false
			for update: Variant in age.updates:
				if not _valid_age_update_payload(state, update):
					return false
			var current_update: Dictionary = age.updates[age.index - 1]
			var expected_age_request := InteractionRequest.from_payload("validation.age-update", InteractionRequest.AGE_UPDATE, current_update)
			var actual_age_body := session_interaction.body as InteractionRequest.AgeUpdateBody
			var expected_age_body: InteractionRequest.AgeUpdateBody = null if expected_age_request == null else expected_age_request.body as InteractionRequest.AgeUpdateBody
			if actual_age_body == null or not actual_age_body.same_values(expected_age_body):
				return false
			if age.resume_kind == &"completed":
				return age.resume_continuation == null
			if age.resume_kind == &"combat-monster-turns":
				return age.resume_continuation == null and state.combat != null and not state.combat.completed and state.combat.pending_monster_attack != null
			if age.resume_kind == &"post-clock":
				return _valid_post_time_continuation(content, state, age.resume_continuation, vm_interaction, null)
			return age.resume_kind == &"post-move" and _valid_ready_post_move_continuation(content, state, age.resume_continuation)
		&"combat-death-macro":
			var combat := continuation.combat()
			if combat == null or session_interaction != null or vm_interaction == null or state.combat == null or state.combat.battle_id != combat.battle_id:
				return false
			var death_monster := state.combat.monster_by_id(combat.combatant_id)
			if death_monster == null or content.scenario.program_by_id(combat.program_id) == null:
				return false
			var queued_id := state.combat.pending_spell_death_macro_id()
			if not queued_id.is_empty():
				var definition := content.monster_by_id(death_monster.definition_id)
				return queued_id == combat.combatant_id and not combat.reset_traitor_on_complete and definition != null and combat.program_id == "xap:%d" % definition.death_macro
			return combat.reset_traitor_on_complete
		&"combat-ally-selection":
			var combat := continuation.combat()
			return combat != null and vm_interaction == null and session_interaction != null and session_interaction.kind == &"ally_selection" and state.combat != null and state.combat.completed and state.combat.battle_id == combat.battle_id
		&"combat-fumble-recovery":
			var combat := continuation.combat()
			if combat == null or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.TREASURE_DISTRIBUTION or state.combat == null or not state.combat.completed or state.combat.battle_id != combat.battle_id or state.combat.fumbled_items().is_empty():
				return false
			var expected_fumble_request := InteractionRequest.from_payload("validation.fumble-recovery", InteractionRequest.TREASURE_DISTRIBUTION, RealmzRules.new().combat_flow.fumble_recovery_payload(state, content))
			var actual_fumble_body := session_interaction.body as InteractionRequest.TreasureRequestBody
			var expected_fumble_body: InteractionRequest.TreasureRequestBody = null if expected_fumble_request == null else expected_fumble_request.body as InteractionRequest.TreasureRequestBody
			return actual_fumble_body != null and actual_fumble_body.same_fumble_values(expected_fumble_body)
		&"combat-reward":
			var reward_body := continuation.reward()
			if reward_body == null or vm_interaction != null:
				return false
			var runtime := reward_body.runtime_continuation
			var reward := ClassicRewardState.from_data(runtime.get("state")) if runtime.size() == 2 and runtime.get("kind") == "classic-reward" else null
			return reward != null and reward.origin == &"battle" and reward.source_id == reward_body.battle_id and _valid_reward_continuation(content, state, reward, session_interaction)
		&"post-clock":
			return _valid_post_time_continuation(content, state, continuation, vm_interaction, session_interaction)
		&"post-move":
			return _valid_post_move_continuation(content, state, continuation, vm_interaction, session_interaction)
	return false


static func _valid_targeting_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var targeting := continuation.targeting()
	if targeting == null or vm_interaction != null or session_interaction == null:
		return false
	var character := state.party.character_by_id(targeting.character_id)
	if continuation.kind == &"drop-item-confirmation":
		var instance := _item_instance_for_state(character, targeting.instance_id)
		var definition: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
		if character == null or instance == null or definition == null or not RealmzRules.new().inventory.classic_drop_probe(character, instance).allowed:
			return false
		var display_name := definition.name if instance.identified else definition.unidentified_name
		return session_interaction.to_data() == _drop_item_confirmation_request(session_interaction.request_id, display_name).to_data()
	if session_interaction.kind != InteractionRequest.CHARACTER_SELECTION or state.combat != null or character == null:
		return false
	var spell := content.spell_by_id(targeting.spell_id)
	if spell == null or targeting.power < 1 or targeting.power > 7:
		return false
	if continuation.kind == &"item-use-target-selection":
		var instance := _item_instance_for_state(character, targeting.instance_id)
		var definition: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
		if instance == null or definition == null or definition.special_2 != spell.classic_id or instance.charges != targeting.starting_charges:
			return false
		var authored_power := absi(definition.special_1)
		var expected_count := state.party.characters().size() if spell.target_type > 2 else mini(targeting.power, state.party.characters().size()) if spell.target_type == 0 else 1
		var probe := RealmzRules.new().inventory.classic_spell_item_probe(character, instance, definition, spell, content.race_by_id(character.race_id), content.caste_by_id(character.caste_id), false)
		var supported := spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9 or absi(spell.special) == 57
		return (authored_power == 8 or targeting.power == authored_power) and targeting.target_count == expected_count and spell.target_type not in [5, 7] and spell.target_type >= 0 and spell.target_type <= 12 and probe.allowed and supported and session_interaction.to_data() == _item_target_request(session_interaction.request_id, character, instance.id, definition, spell, expected_count, state.party.characters()).to_data()
	if continuation.kind == &"field-spell-target-selection":
		if not character.known_spells().has(spell.id) or character.spell_points != targeting.starting_spell_points or state.character_spellcasting_blocked or character.current_health < 1 or character.spell_points < absi(spell.cost * targeting.power) or not spell.in_camp or spell.cost < 0 and targeting.power != 1:
			return false
		for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
			if character.conditions.is_active(condition):
				return false
	else:
		var scroll := character.scroll_at(targeting.scroll_slot)
		if scroll == null or scroll.spell_id != spell.id or scroll.power != targeting.power or character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED) or not spell.in_camp:
			return false
		var has_case := false
		for carried: ItemInstance in character.inventory():
			var carried_definition := content.item_by_id(carried.definition_id)
			if carried.equipped and carried_definition != null and absi(carried_definition.item_type) == 13:
				has_case = true
				break
		if not has_case:
			return false
	var special := absi(spell.special)
	var supported := special == 68 or special > 0 and special < 41 or special in [48, 57, 59, 60, 61, 64, 66, 91, 92] or special > 99 or special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)
	var expected_count := mini(targeting.power, state.party.characters().size()) if spell.target_type == 0 else 1
	if targeting.target_count != expected_count or spell.target_type < 0 or spell.target_type > 2 or not supported:
		return false
	return session_interaction.to_data() == (_field_spell_target_request(session_interaction.request_id, character, spell, expected_count, state.party.characters()).to_data() if continuation.kind == &"field-spell-target-selection" else _scroll_target_request(session_interaction.request_id, character, targeting.scroll_slot, spell, expected_count, state.party.characters()).to_data())


static func _item_instance_for_state(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null:
		return null
	for carried: ItemInstance in character.inventory():
		if carried.id == instance_id:
			return carried
	return null


static func _valid_post_move_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var exploration := continuation.exploration()
	if continuation.kind != &"post-move" or exploration == null or exploration.action_point_destination_depth < 0 or exploration.action_point_destination_depth > 1:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != exploration.coordinate or exploration.trigger_ids != _selected_placed_trigger_ids(content, cell) or exploration.random_region_ids != cell.random_rect_ids():
		return false
	if exploration.random_region_index < -1 or exploration.random_region_index >= exploration.random_region_ids.size():
		return false
	if session_interaction != null:
		return vm_interaction == null and exploration.active_trigger_id.is_empty() and exploration.active_random_program_id.is_empty() and exploration.random_battle_stage == &"surprise-choice" and session_interaction.kind == &"yes_no" and exploration.random_region_index >= 0 and exploration.random_region_ids[exploration.random_region_index] == exploration.active_random_region_id and map.random_region_by_id(exploration.active_random_region_id) != null
	if vm_interaction == null or not exploration.random_battle_stage.is_empty() or not exploration.active_random_region_id.is_empty():
		return false
	if not exploration.active_random_program_id.is_empty():
		return exploration.active_trigger_id.is_empty() and content.scenario.program_by_id(exploration.active_random_program_id) != null
	return exploration.trigger_index >= 0 and exploration.trigger_index < exploration.trigger_ids.size() and not exploration.active_trigger_id.is_empty() and exploration.trigger_ids[exploration.trigger_index] == exploration.active_trigger_id and content.trigger_by_id(exploration.active_trigger_id) != null


static func _valid_suspended_scenario_owner(content: RealmzContent, state: GameState, owner: SessionContinuation, saved: ScenarioVmSnapshot) -> bool:
	# The full handoff shape is validated by the caller. This guard proves the
	# detached VM can resume and that its owner is an exploration continuation
	# which would ordinarily be validated beside a live VM interaction.
	if owner == null or owner.kind not in [&"post-clock", &"post-move"] or saved == null or saved.halted or saved.frames.is_empty() or saved.pending_request != null or not saved.pending_continuation.is_empty():
		return false
	var test_vm := ScenarioVm.new()
	test_vm.configure(content.scenario)
	if not test_vm.restore(saved):
		return false
	var sentinel := InteractionRequest.acknowledge("internal.suspended-scenario", "Suspended scenario validation")
	return _valid_session_continuation(content, state, owner, sentinel, null)


static func _valid_post_time_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	if continuation == null or continuation.kind != &"post-clock":
		return false
	var exploration := continuation.exploration()
	if exploration == null or exploration.timed_day < 0 or exploration.timed_encounter_index < 0 or exploration.timed_encounter_index > content.timed_encounters().size() or exploration.resume_kind not in [&"completed", &"move", &"post-move"]:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != exploration.coordinate or exploration.random_region_ids != cell.random_rect_ids() or exploration.random_region_index < -1 or exploration.random_region_index >= exploration.random_region_ids.size() or exploration.direction.x < -1 or exploration.direction.x > 1 or exploration.direction.y < -1 or exploration.direction.y > 1:
		return false
	if exploration.resume_kind in [&"completed", &"post-move"] and exploration.direction != Vector2i.ZERO or exploration.resume_kind == &"move" and exploration.direction == Vector2i.ZERO:
		return false
	if session_interaction != null:
		return vm_interaction == null and exploration.active_random_program_id.is_empty() and exploration.random_battle_stage == &"surprise-choice" and session_interaction.kind == InteractionRequest.YES_NO and exploration.random_region_index >= 0 and exploration.random_region_ids[exploration.random_region_index] == exploration.active_random_region_id and map.random_region_by_id(exploration.active_random_region_id) != null
	if vm_interaction != null:
		if not exploration.active_timed_program_id.is_empty():
			return exploration.active_random_program_id.is_empty() and content.scenario.program_by_id(exploration.active_timed_program_id) != null
		return exploration.random_battle_stage.is_empty() and exploration.active_random_region_id.is_empty() and not exploration.active_random_program_id.is_empty() and content.scenario.program_by_id(exploration.active_random_program_id) != null
	return exploration.random_battle_stage.is_empty() and exploration.active_random_region_id.is_empty() and exploration.active_random_program_id.is_empty() and exploration.active_timed_program_id.is_empty()


static func _valid_vm_reward_continuation(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation.is_empty():
		return true
	var runtime: Variant = snapshot.pending_continuation.get("runtime")
	if not runtime is Dictionary or runtime.get("kind") != "classic-reward":
		return true
	var reward := ClassicRewardState.from_data(runtime.get("state"))
	return reward != null and _valid_reward_continuation(content, state, reward, vm.pending_request())


static func _valid_player_map_vm_continuation(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation.is_empty():
		return true
	var runtime: Variant = snapshot.pending_continuation.get("runtime")
	if not runtime is Dictionary or runtime.get("kind") != "classic-player-map":
		return true
	var request := vm.pending_request()
	var player_map_id := String(runtime.get("playerMapId", ""))
	var body: InteractionRequest.AcknowledgeBody = null
	if request != null:
		body = request.body as InteractionRequest.AcknowledgeBody
	return request != null and request.kind == InteractionRequest.ACKNOWLEDGE and body != null and body.presentation == &"player-map" and body.player_map_id == player_map_id and body.has_presentation and body.has_player_map_id and not body.has_message_id and not body.has_journal_state and not body.has_sound_id and content.world.player_map_by_id(player_map_id) != null and state.world.has_map(player_map_id)


static func _valid_reward_continuation(content: RealmzContent, state: GameState, reward: ClassicRewardState, request: InteractionRequest) -> bool:
	if reward == null or request == null or reward.source_id.is_empty() or reward.origin not in [&"scenario", &"battle"]:
		return false
	if reward.origin == &"battle" and (state.combat == null or not state.combat.completed or not state.combat.rewards_started or state.combat.rewards_completed or state.combat.battle_id != reward.source_id):
		return false
	for item: ItemInstance in reward.items():
		if content.item_by_id(item.definition_id) == null:
			return false
	var character_ids: Dictionary = {}
	for character_id: Variant in reward.experience_awards():
		character_ids[String(character_id)] = true
	for character_id: String in reward.level_character_ids():
		character_ids[character_id] = true
	for character_id: String in reward.spell_character_ids():
		character_ids[character_id] = true
	if not reward.pending_level_result.is_empty():
		character_ids[String(reward.pending_level_result.get("characterId", ""))] = true
	for character_id: Variant in character_ids:
		if String(character_id).is_empty() or state.party.character_by_id(String(character_id)) == null:
			return false
	if reward.phase == ClassicRewardState.ITEM_PHASE:
		var treasure_body := request.body as InteractionRequest.TreasureRequestBody
		if request.kind != InteractionRequest.TREASURE_DISTRIBUTION or treasure_body == null:
			return false
		var expected_mode := &"completion-confirmation" if reward.completion_pending else &"ordinary"
		if treasure_body.mode != expected_mode:
			return false
		var pending := reward.first_item()
		return treasure_body.item == null if pending == null else treasure_body.item != null and treasure_body.item.instance_id == pending.id
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		var level_body := request.body as InteractionRequest.LevelUpRequestBody
		return not reward.pending_level_result.is_empty() and request.kind == InteractionRequest.LEVEL_UP and level_body != null and level_body.mode == &"result" and level_body.character_id == reward.pending_level_result.get("characterId")
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		var spell_ids := reward.spell_character_ids()
		var level_body := request.body as InteractionRequest.LevelUpRequestBody
		return reward.spell_index < spell_ids.size() and request.kind == InteractionRequest.LEVEL_UP and level_body != null and level_body.mode == &"spell-selection" and level_body.character_id == spell_ids[reward.spell_index]
	return false


static func _valid_age_update_payload(state: GameState, value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var character_id: Variant = value.get("characterId")
	var changes: Variant = value.get("changes")
	return character_id is String and not character_id.is_empty() and state.party.character_by_id(character_id) != null \
		and value.get("presentation") == "classic-age-update" and value.get("soundId") is int \
		and value.get("ageGroup") is int and int(value.get("ageGroup")) >= 1 and int(value.get("ageGroup")) <= 5 \
		and value.get("transition") is int and int(value.get("transition")) in [-1, 1] \
		and changes is Array and changes.size() == 15 and changes.all(func(change: Variant) -> bool: return change is int)


static func _valid_ready_post_move_continuation(content: RealmzContent, state: GameState, continuation: SessionContinuation) -> bool:
	if continuation == null or continuation.kind != &"post-move":
		return false
	var exploration := continuation.exploration()
	if exploration == null or exploration.trigger_index != 0 or not exploration.active_trigger_id.is_empty() or not exploration.active_random_program_id.is_empty() or not exploration.active_random_region_id.is_empty() or not exploration.random_battle_stage.is_empty() or exploration.action_point_destination_depth < 0 or exploration.action_point_destination_depth > 1:
		return false
	var map := content.world.map_by_id(exploration.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(exploration.coordinate)
	return cell != null and state.party.map_id == map.id and state.party.coordinate == exploration.coordinate \
		and exploration.trigger_ids == _selected_placed_trigger_ids(content, cell) \
		and exploration.random_region_ids == cell.random_rect_ids() \
		and exploration.random_region_index == exploration.random_region_ids.size() - 1


static func _selected_placed_trigger_ids(content: RealmzContent, cell: MapCell) -> Array[String]:
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
