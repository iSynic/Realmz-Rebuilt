class_name GameSession
extends RefCounted

const MAP_VIEW_RADIUS: int = 12

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _rules: RealmzRules
var _scenario_vm: ScenarioVm
var _scenario_action_state: ScenarioActionState
var _runtime_api: RealmzRuntimeApi
var _session_continuation: Dictionary = {}
var _session_interaction: InteractionRequest
var _started: bool = false
var _view_revision: int = 0


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
			var battle_return: Dictionary = replacement_state.combat.return_continuation
			if battle_return.get("kind") != "post-clock" or battle_return.get("resumeKind") != "move" or not _valid_post_time_continuation(content, replacement_state, battle_return, null, null):
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
	var replacement_continuation := {} if save_envelope.continuation == null else save_envelope.continuation.to_legacy_data()
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
			return _set_fast_spell(intent)
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
			return _remove_party_member((intent.payload as PlayerIntent.CharacterPayload).character_id)
		PlayerIntent.Kind.SET_PARTY_SETUP_OPTIONS:
			var setup := intent.payload as PlayerIntent.PartySetupOptionsPayload
			return _set_party_setup_options(setup.difficulty, setup.monster_set)
		PlayerIntent.Kind.REORDER_PARTY:
			return _reorder_party((intent.payload as PlayerIntent.StringListPayload).values)
		PlayerIntent.Kind.CHANGE_CHARACTER_APPEARANCE:
			return _change_character_appearance(intent)
		PlayerIntent.Kind.EQUIP_ITEM:
			return _equip_item(intent)
		PlayerIntent.Kind.UNEQUIP_ITEM:
			return _unequip_item(intent)
		PlayerIntent.Kind.DROP_ITEM:
			return _request_drop_item(intent)
		PlayerIntent.Kind.TRADE_ITEM:
			return _trade_item(intent)
		PlayerIntent.Kind.MONEY_ACTION:
			return _money_action(intent)
		PlayerIntent.Kind.SERVICE_ACTION:
			return _service_action(intent)
		PlayerIntent.Kind.SET_LOCATION_NOTE:
			return _set_location_note((intent.payload as PlayerIntent.LocationNotePayload).text)
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
	if _session_continuation.get("kind") == "application-hook" and _events_have(result.events, &"party_revived"):
		_session_continuation["partyRevived"] = true
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.WAITING:
		if _session_continuation.get("kind") == "post-clock" and not String(_session_continuation.get("activeTimedProgramId", "")).is_empty() and not _rebase_post_time_location():
			_session_continuation.clear()
			return _finish_failed(&"invalid_timed_encounter_location", "The timed encounter moved the party to an unavailable location.", events)
		return _finish_waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if not _session_continuation.is_empty():
		if _session_continuation.get("kind") == "combat-death-macro":
			return _continue_session_death_macro(events)
		return _continue_exploration_continuation(events)
	return _finish_completed(events)


func view() -> GameView:
	if not _started:
		return GameView.new(_view_revision, false, null)
	var members: Array[CharacterView] = []
	for character: CharacterState in _state.party.characters():
		var member_view := CharacterView.new(character, _content)
		member_view.apply_equipment(_rules.inventory.combat_equipment(character, _content.item_definitions()))
		members.append(member_view)
	var current_combat := CombatView.new(_state.combat, _state.party.characters(), _content, _rules.inventory, _rules.battlefield, _rules.combat_flow, _state) if _state.combat != null else null
	var result := GameView.new(_view_revision, true, _pending_interaction(), _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour(), _state.clock.minute(), _build_map_view(), members, _state.party.fatigue, _state.party.pooled_wealth.gold, current_combat)
	result.campaign_id = _content.campaign_id
	result.rules_version = _content.rules_version
	result.party_setup_available = not _state.party_setup_completed
	if _state.character_draft != null and _state.character_draft.generated_character != null:
		result.character_draft = CharacterView.new(_state.character_draft.generated_character, _content)
		_populate_character_draft_spells(result)
	result.campaign_summary = CampaignSummaryView.new()
	result.campaign_summary.campaign_id = _content.campaign_id
	var campaign := _content.campaign_definition()
	result.campaign_summary.title = campaign.title if not campaign.title.is_empty() else _content.campaign_id.replace("-", " ").capitalize()
	result.campaign_summary.version = campaign.version if not campaign.version.is_empty() else _content.rules_version
	result.campaign_summary.author = campaign.author
	result.campaign_summary.contact = campaign.contact.duplicate(true)
	result.campaign_summary.description = campaign.description
	result.campaign_summary.splash_asset_id = campaign.splash_asset_id
	result.campaign_summary.restriction_description = campaign.restrictions.description
	result.campaign_summary.maximum_party_size = campaign.restrictions.maximum_party_size
	result.campaign_summary.maximum_level = campaign.restrictions.maximum_level
	result.campaign_summary.recommended_party_levels = campaign.recommended_party_levels
	result.campaign_summary.maximum_party_levels = campaign.maximum_party_levels
	result.campaign_summary.guidance_authored = campaign.guidance_authored
	result.campaign_summary.banned_races = campaign.restrictions.banned_races.duplicate()
	result.campaign_summary.banned_castes = campaign.restrictions.banned_castes.duplicate()
	result.campaign_summary.package_hash = _content.package_hash
	result.party_setup = PartySetupView.new()
	result.party_setup.difficulty = _state.difficulty
	result.party_setup.monster_set = _state.monster_set
	result.party_setup.available_monster_sets = _content.available_monster_sets()
	for character: CharacterState in _state.party.characters():
		result.party_setup.current_party_levels += character.level
	result.party_setup.experience_percent = PartySetupRules.experience_percent(campaign.recommended_party_levels, result.party_setup.current_party_levels, _state.difficulty)
	result.party_summary = PartySummaryView.new()
	for character: CharacterState in _state.party.characters():
		result.party_summary.character_ids.append(character.id)
	for ally: MonsterState in _state.party.allies():
		result.party_summary.ally_ids.append(ally.id)
	result.party_summary.pooled_gold = _state.party.pooled_wealth.gold
	result.party_summary.banked_gold = _state.party.banked_wealth.gold
	result.party_summary.fatigue = _state.party.fatigue
	result.party_summary.light_remaining = _state.party.conditions.value(0)
	result.party_summary.camping = _state.party_camping
	result.party_summary.acquired_map_ids = _state.world.acquired_map_ids()
	for definition: PlayerMapDefinition in _content.world.player_maps():
		var acquired := _state.world.has_map(definition.id)
		var player_map_view := _build_player_map_view(definition) if acquired else PlayerMapView.new(definition, [], false, Vector2i.ZERO, false)
		result.player_map_menu_entries.append(player_map_view)
		if acquired:
			result.acquired_player_maps.append(player_map_view)
	for message_id: int in _state.journal_message_ids():
		var journal_message := _content.message_by_id(message_id)
		if journal_message != null:
			result.journal_entries.append(JournalEntryView.new(message_id, journal_message.text))
	var current_map := _content.world.map_by_id(_state.party.map_id)
	if current_map != null:
		var current_note := _state.world.location_note_at(current_map.id, _state.party.coordinate)
		result.current_location_note = LocationNoteView.new(current_map.id, current_map.name, current_map.level_type, current_map.level_index, _state.party.coordinate, current_note.text if current_note != null else "", current_note.darkness_value if current_note != null else _current_location_note_darkness(current_map), current_note.record_ordinal if current_note != null else -1, true)
		for note: LocationNoteState in _state.world.location_notes_for_kind(current_map.level_type):
			var note_map := _content.world.map_by_id(note.map_id)
			if note_map != null:
				result.location_notes.append(LocationNoteView.new(note.map_id, note_map.name, note.map_kind, note.level_index, note.coordinate, note.text, note.darkness_value, note.record_ordinal, note.map_id == _state.party.map_id and note.coordinate == _state.party.coordinate))
	if result.party_setup_available:
		for race: RaceDefinition in _content.race_definitions():
			result.race_options.append(DefinitionOptionView.new(race.id, race.name, race.description, race.eligible_caste_ids))
		for caste: CasteDefinition in _content.caste_definitions():
			result.caste_options.append(DefinitionOptionView.new(caste.id, caste.name, caste.description, caste.eligible_race_ids))
	for portrait: CharacterAppearanceDefinition in _content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT):
		result.portrait_options.append(CharacterAppearanceOptionView.new(portrait))
	for icon: CharacterAppearanceDefinition in _content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON):
		result.combat_icon_options.append(CharacterAppearanceOptionView.new(icon))
	_populate_inventory_item_actions(result)
	_populate_spell_actions(result)
	_populate_money_workspace(result)
	_populate_services(result)
	_populate_action_availability(result)
	return result


func _populate_services(result: GameView) -> void:
	if not _state.active_shop_id.is_empty():
		var shop := _content.shop_by_id(_state.active_shop_id)
		if shop != null:
			var shop_view := ServiceView.new()
			shop_view.service_id = shop.id
			shop_view.service_kind = &"shop"
			shop_view.title = "Shop %d" % shop.classic_id
			shop_view.actions = [&"enter"]
			result.services.append(shop_view)
	if _state.temple_available:
		var temple_view := ServiceView.new()
		temple_view.service_id = "realmz.service.temple"
		temple_view.service_kind = &"temple"
		temple_view.title = "Temple"
		temple_view.actions = [&"enter"]
		result.services.append(temple_view)
	if _state.bank_available:
		var bank_view := ServiceView.new()
		bank_view.service_id = "realmz.service.bank"
		bank_view.service_kind = &"bank"
		bank_view.title = "Bank"
		bank_view.actions = [&"enter"]
		result.services.append(bank_view)


func _populate_money_workspace(result: GameView) -> void:
	if _state.party_setup_completed == false:
		return
	var workspace := MoneyWorkspaceView.new()
	workspace.pooled_gold = _state.party.pooled_wealth.gold
	workspace.pooled_gems = _state.party.pooled_wealth.gems
	workspace.pooled_jewelry = _state.party.pooled_wealth.jewelry
	workspace.banked_gold = _state.party.banked_wealth.gold
	workspace.banked_gems = _state.party.banked_wealth.gems
	workspace.banked_jewelry = _state.party.banked_wealth.jewelry
	var pool_probe := _rules.economy.pool_probe(_state.party)
	workspace.pool = ActionAvailabilityView.new(&"money_action", pool_probe.allowed, pool_probe.reason)
	var share_probe := _rules.economy.share_probe(_state.party)
	workspace.share = ActionAvailabilityView.new(&"money_action", share_probe.allowed, share_probe.reason)
	for character: CharacterState in _state.party.characters():
		var character_view := MoneyCharacterView.new(character)
		for denomination: StringName in [&"gold", &"gems", &"jewelry"]:
			var kind := _money_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := _rules.economy.transfer_probe(_state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := _rules.economy.transfer_probe(_state.party, character, kind as WealthState.Kind, amount, true)
			character_view.transfers.append(MoneyTransferView.new(denomination, amount, ActionAvailabilityView.new(&"money_action", to_pool.allowed, to_pool.reason), ActionAvailabilityView.new(&"money_action", to_character.allowed, to_character.reason)))
		workspace.characters.append(character_view)
	result.money_workspace = workspace


func _populate_action_availability(result: GameView) -> void:
	var blocked_by_interaction := result.pending_interaction != null
	var party_setup := result.party_setup_available
	var setup_member_count := _state.party.characters().size()
	var setup_member_limit := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var draft_active := _state.character_draft != null and _state.character_draft.generated_character != null
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	var ordinary_reason := "Resolve the current interaction first." if blocked_by_interaction else "Complete party setup first." if party_setup else ""
	var field_item_available := false
	for member: CharacterView in result.party_members:
		if member.items.any(func(item: ItemView) -> bool: return item.actions != null and item.actions.use.enabled):
			field_item_available = true
			break
	var combat_item_available := battle_active and not _rules.combat_flow.character_item_spell_options(_state, _content, result.combat_view.active_actor_id).is_empty()
	result.set_action_availability(&"move", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Movement is unavailable during battle." if battle_active else "")
	result.set_action_availability(&"search", ordinary_reason.is_empty() and not battle_active and not _state.party_camping, ordinary_reason if not ordinary_reason.is_empty() else "Search is unavailable during battle." if battle_active else "Search is replaced by scroll scribing while camped." if _state.party_camping else "")
	result.set_action_availability(&"camp", ordinary_reason.is_empty() and not battle_active and (_state.camping_allowed or _state.party_camping), ordinary_reason if not ordinary_reason.is_empty() else "Camping is unavailable during battle." if battle_active else "Camping is unavailable here." if not _state.camping_allowed and not _state.party_camping else "")
	result.set_action_availability(&"rest", ordinary_reason.is_empty() and not battle_active and _state.party_camping, ordinary_reason if not ordinary_reason.is_empty() else "Rest is unavailable during battle." if battle_active else "Make camp before resting.")
	result.set_action_availability(&"use_item", not blocked_by_interaction and (combat_item_available or not battle_active and field_item_available), "Resolve the current interaction first." if blocked_by_interaction else _rules.combat_flow.character_item_spell_unavailable_reason(_state, _content, result.combat_view.active_actor_id) if battle_active else "No carried item has a supported Classic field use.")
	result.set_action_availability(&"use_item_on_target", not blocked_by_interaction and combat_item_available, "Resolve the current interaction first." if blocked_by_interaction else _rules.combat_flow.character_item_spell_unavailable_reason(_state, _content, result.combat_view.active_actor_id) if battle_active else "Targeted combat item use is available only during battle.")
	var field_spell_available := false
	var field_spell_reason := "No known spell has a supported Classic field use."
	for member: CharacterView in result.party_members:
		for spell: SpellView in member.spells:
			if spell.field_cast.enabled:
				field_spell_available = true
				break
			if not spell.field_cast.reason.is_empty():
				field_spell_reason = spell.field_cast.reason
		if field_spell_available:
			break
	var combat_spell_available := battle_active and not _rules.combat_flow.character_spell_options(_state, _content, result.combat_view.active_actor_id).is_empty()
	var cast_enabled := not blocked_by_interaction and (combat_spell_available or not battle_active and field_spell_available)
	var cast_reason := ordinary_reason
	if cast_reason.is_empty() and battle_active:
		cast_reason = _rules.combat_flow.character_spell_unavailable_reason(_state, _content, result.combat_view.active_actor_id)
		if cast_reason.is_empty():
			cast_reason = "No legal Classic combat spell is available."
	elif cast_reason.is_empty():
		cast_reason = field_spell_reason
	result.set_action_availability(&"cast_spell", cast_enabled, "" if cast_enabled else cast_reason)
	result.set_action_availability(&"set_fast_spell", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Fast Spell bindings cannot be changed during battle." if battle_active else "")
	result.set_action_availability(&"choose_combat_action", battle_active and not blocked_by_interaction, "No battle action is currently available." if not battle_active else "Resolve the current interaction first." if blocked_by_interaction else "")
	result.set_action_availability(&"create_party", party_setup and not blocked_by_interaction, "Resolve the current interaction first." if blocked_by_interaction else "Party creation is available only before beginning a campaign." if not party_setup else "")
	result.set_action_availability(&"begin_adventure", party_setup and not blocked_by_interaction and setup_member_count > 0 and not draft_active, "Resolve the current interaction first." if blocked_by_interaction else "The adventure has already begun." if not party_setup else "Finish or cancel the character currently being created." if draft_active else "Add or import at least one character first.")
	result.set_action_availability(&"import_vault_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit and not draft_active, "Resolve the current interaction first." if blocked_by_interaction else "Vault imports are available only during party setup." if not party_setup else "Finish or cancel the character currently being created." if draft_active else "The party is full.")
	result.set_action_availability(&"generate_character_draft", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "The party is full.")
	result.set_action_availability(&"cancel_character_draft", party_setup and not blocked_by_interaction and draft_active, "There is no generated character to cancel." if not draft_active else "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup.")
	result.set_action_availability(&"set_character_draft_spells", party_setup and not blocked_by_interaction and draft_active, "Generate the character before choosing spells." if not draft_active else "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup.")
	result.set_action_availability(&"finalize_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit and draft_active, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "Generate and review the character first." if not draft_active else "The party is full.")
	result.set_action_availability(&"remove_party_member", party_setup and not blocked_by_interaction and setup_member_count > 0, "Resolve the current interaction first." if blocked_by_interaction else "Party members can be removed only during party setup." if not party_setup else "The party is empty.")
	result.set_action_availability(&"reorder_party", not party_setup and not blocked_by_interaction and not battle_active and setup_member_count > 1, "Resolve the current interaction first." if blocked_by_interaction else "Begin the adventure before changing party order." if party_setup else "Party order is unavailable during battle." if battle_active else "At least two party members are required.")
	var appearance_available := not party_setup and not blocked_by_interaction and not battle_active and setup_member_count > 0 and _content.has_character_appearance_catalog()
	var appearance_reason := "Resolve the current interaction first." if blocked_by_interaction else "Begin the adventure before changing appearance." if party_setup else "Appearance changes are unavailable during battle." if battle_active else "No party member is available." if setup_member_count == 0 else "This package does not contain the complete Classic portrait and combat-icon catalogs." if not _content.has_character_appearance_catalog() else ""
	result.set_action_availability(&"change_character_appearance", appearance_available, appearance_reason)
	for action_id: StringName in [&"equip_item", &"unequip_item", &"drop_item", &"trade_item"]:
		result.set_action_availability(action_id, ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"identify_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Identification is available only from a shop, temple, or the Identify spell.")
	result.set_action_availability(&"split_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Classic split-stack load behavior requires a fidelity decision.")
	result.set_action_availability(&"join_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Classic join-stack load behavior requires a fidelity decision.")
	result.set_action_availability(&"store_item", false, "Classic has no ordinary player-stash workflow; opcode 36 equipment escrow remains scenario-owned.")
	result.set_action_availability(&"service_action", ordinary_reason.is_empty() and not battle_active and not result.services.is_empty(), ordinary_reason if not ordinary_reason.is_empty() else "Services are unavailable during battle." if battle_active else "No shop, temple, or bank is available at this location.")
	result.set_action_availability(&"money_action", ordinary_reason.is_empty() and not battle_active and result.money_workspace != null, ordinary_reason if not ordinary_reason.is_empty() else "Money management is unavailable during battle." if battle_active else "No party money workspace is available.")
	result.set_action_availability(&"set_location_note", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Location notes are unavailable during battle." if battle_active else "")
	var combat_move_enabled := false
	var combat_move_reason := "No active battle."
	if battle_active:
		var combat_request_open := result.pending_interaction == null or result.pending_interaction.kind == InteractionRequest.COMBAT
		if not combat_request_open:
			combat_move_reason = "Resolve the current interaction first."
		elif result.combat_view.movement_options.is_empty():
			combat_move_reason = "The active combatant is not available for player-controlled movement."
		else:
			for option: CombatMoveOptionView in result.combat_view.movement_options:
				if option.enabled:
					combat_move_enabled = true
					combat_move_reason = ""
					break
			if not combat_move_enabled:
				combat_move_reason = "The active character has no legal tactical step."
	result.set_action_availability(&"combat_move", combat_move_enabled, combat_move_reason)
	for action_id: StringName in [
		&"select_spell_power", &"select_spell_target",
		&"open_journal",
	]:
		result.set_action_availability(action_id, false, "Not implemented in the current gameplay slice.")
	result.set_action_availability(&"open_maps", not result.player_map_menu_entries.is_empty(), "This campaign supplies no player-map records." if result.player_map_menu_entries.is_empty() else "")


func _populate_spell_actions(result: GameView) -> void:
	var blocked_reason := "Resolve the current interaction first." if result.pending_interaction != null else "Complete party setup first." if result.party_setup_available else ""
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	for member_view: CharacterView in result.party_members:
		var character := _state.party.character_by_id(member_view.id)
		for spell_view: SpellView in member_view.spells:
			var spell := _content.spell_by_id(spell_view.id)
			if not blocked_reason.is_empty():
				spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				continue
			if battle_active:
				spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, "Use the tactical spell action during battle.")
				spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", false, "Scroll scribing is unavailable during battle.")
				continue
			var first_reason := ""
			for power: int in range(1, 8):
				var probe := _field_spell_probe(character, spell, power)
				if probe.allowed:
					spell_view.power_levels.append(power)
				elif first_reason.is_empty():
					first_reason = probe.reason
				if spell != null and spell.cost < 0:
					break
			spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", not spell_view.power_levels.is_empty(), first_reason)
			var make_reason := ""
			for power: int in range(1, 8):
				var make_probe := _make_scroll_probe(character, spell, power)
				if make_probe.allowed:
					spell_view.scroll_power_levels.append(power)
				elif make_reason.is_empty():
					make_reason = make_probe.reason
				if spell != null and spell.cost < 0:
					break
			spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", not spell_view.scroll_power_levels.is_empty(), make_reason)
		for scroll_view: SpellScrollView in member_view.scrolls:
			if not blocked_reason.is_empty():
				scroll_view.use = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				continue
			if battle_active:
				var combat_scroll := character.scroll_at(scroll_view.slot_index)
				var combat_scroll_spell := _content.spell_by_id(combat_scroll.spell_id) if combat_scroll != null and not combat_scroll.is_empty() else null
				var combat_target_id := character.id if combat_scroll_spell != null and combat_scroll_spell.target_type == 5 else ""
				var combat_probe := _rules.combat_flow.probe_character_scroll_cast(_state, _content, character.id, scroll_view.slot_index, combat_target_id)
				scroll_view.use = ActionAvailabilityView.new(&"cast_spell", combat_probe.allowed, combat_probe.reason_text)
				continue
			var scroll := character.scroll_at(scroll_view.slot_index)
			var scroll_spell := _content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
			var scroll_probe := _scroll_use_probe(character, scroll_view.slot_index, scroll_spell)
			scroll_view.use = ActionAvailabilityView.new(&"cast_spell", scroll_probe.allowed, scroll_probe.reason)
		for fast_spell: FastSpellBindingView in member_view.fast_spells:
			if fast_spell.spell_id.is_empty():
				continue
			var bound_spell := _content.spell_by_id(fast_spell.spell_id)
			if bound_spell == null or not character.known_spells().has(fast_spell.spell_id):
				fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", false, "The stored spell is unavailable to this character.")
				continue
			if battle_active:
				var option_available := false
				for option: CombatSpellOptionView in _rules.combat_flow.character_spell_options(_state, _content, character.id):
					if option.spell_id == bound_spell.id and option.power == fast_spell.power:
						option_available = true
						break
				fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", option_available, "No legal target or casting action is currently available." if not option_available else "")
			else:
				var field_probe := _field_spell_probe(character, bound_spell, fast_spell.power)
				fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", field_probe.allowed, field_probe.reason)


func _set_fast_spell(intent: PlayerIntent) -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"fast_spell_binding_in_battle", "Fast Spell bindings cannot be changed during battle.")
	var payload := intent.payload as PlayerIntent.SpellPayload
	var character := _state.party.character_by_id(payload.caster_id)
	if character == null or payload.scroll_slot < 0 or payload.scroll_slot >= 10:
		return SessionStep.failed(_view_revision, &"invalid_fast_spell_slot", "The selected Fast Spell slot is unavailable.")
	if payload.spell_id.is_empty():
		if not character.clear_fast_spell(payload.scroll_slot):
			return SessionStep.failed(_view_revision, &"fast_spell_binding_failed", "The Fast Spell slot could not be cleared.")
		return _finish_completed([DomainEvent.new(&"fast_spell_changed", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": "", "power": 0, "source": "classic"})])
	var spell := _content.spell_by_id(payload.spell_id)
	if spell == null or not character.known_spells().has(spell.id):
		return SessionStep.failed(_view_revision, &"invalid_fast_spell", "Fast Spells must reference a spell known by this character.")
	if payload.power < 1 or payload.power > 7 or spell.cost < 0 and payload.power != 1:
		return SessionStep.failed(_view_revision, &"invalid_fast_spell_power", "The selected spell does not support that Fast Spell power.")
	if not character.bind_fast_spell(payload.scroll_slot, spell.id, payload.power):
		return SessionStep.failed(_view_revision, &"fast_spell_binding_failed", "The Fast Spell binding could not be committed.")
	return _finish_completed([DomainEvent.new(&"fast_spell_changed", {"characterId": character.id, "slot": payload.scroll_slot, "spellId": spell.id, "power": payload.power, "source": "classic"})])


func _populate_inventory_item_actions(result: GameView) -> void:
	var context_reason := ""
	if result.pending_interaction != null:
		context_reason = "Resolve the current interaction first."
	elif result.party_setup_available:
		context_reason = "Begin the adventure before changing carried equipment."
	elif result.combat_view != null and result.combat_view.outcome == &"active":
		context_reason = "Use the battle action flow during combat."
	var party := _state.party.characters()
	var definitions := _content.item_definitions()
	for member_view: CharacterView in result.party_members:
		var character := _state.party.character_by_id(member_view.id)
		if character == null:
			continue
		var race := _content.race_by_id(character.race_id)
		var caste := _content.caste_by_id(character.caste_id)
		for item_view: ItemView in member_view.items:
			var instance := _item_instance(character, item_view.instance_id)
			var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
			var actions := InventoryItemActionsView.new()
			if not context_reason.is_empty():
				actions.block_all(context_reason)
				item_view.actions = actions
				continue
			var equip_probe := _rules.inventory.classic_equip_probe(character, instance, definition, race, caste, party, definitions)
			var unequip_probe := _rules.inventory.classic_unequip_probe(character, instance, definition, definitions)
			var drop_probe := _rules.inventory.classic_drop_probe(character, instance)
			var use_probe := _field_spell_item_probe(character, instance, definition, _content.spell_by_classic_id(definition.special_2) if definition != null else null)
			actions.equip = ActionAvailabilityView.new(&"equip_item", equip_probe.allowed, equip_probe.reason)
			actions.unequip = ActionAvailabilityView.new(&"unequip_item", unequip_probe.allowed, unequip_probe.reason)
			actions.drop = ActionAvailabilityView.new(&"drop_item", drop_probe.allowed, drop_probe.reason)
			actions.use = ActionAvailabilityView.new(&"use_item", use_probe.allowed, use_probe.reason)
			for destination: CharacterState in party:
				if destination == character:
					continue
				var trade_probe := _rules.inventory.classic_trade_probe(character, destination, instance, definition)
				actions.trade_targets.append(ItemTransferTargetView.new(destination.id, destination.name, trade_probe.allowed, trade_probe.reason))
			var enabled_targets := actions.trade_targets.filter(func(target: ItemTransferTargetView) -> bool: return target.enabled)
			var trade_reason := "Choose another party member." if actions.trade_targets.is_empty() else actions.trade_targets[0].reason if enabled_targets.is_empty() else ""
			actions.trade = ActionAvailabilityView.new(&"trade_item", not enabled_targets.is_empty(), trade_reason)
			item_view.actions = actions


func _populate_character_draft_spells(result: GameView) -> void:
	var character := _state.character_draft.generated_character
	var caste := _content.caste_by_id(character.caste_id)
	result.character_draft_spell_points_total = _rules.characters.spell_selection_total(character, caste)
	var spent := 0
	for spell: SpellDefinition in _character_spell_candidates(character, caste):
		result.character_draft_spell_options.append(CharacterSpellOptionView.new(spell, _rules.characters.spell_selection_cost(spell), character.known_spells().has(spell.id)))
	for spell_id: String in character.known_spells():
		spent += _rules.characters.spell_selection_cost(_content.spell_by_id(spell_id))
	result.character_draft_spell_points_remaining = maxi(0, result.character_draft_spell_points_total - spent)


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
	var continuation := SessionContinuation.from_legacy_data(_session_continuation)
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
		return _finish_with_age_updates(events, "post-clock", _session_continuation)
	_set_post_time_continuation(map, "completed", Vector2i.ZERO, true, _state.clock.day() if _state.clock.day() != previous_day else 0, _state.party.coordinate)
	return _finish_with_age_updates(events, "post-clock", _session_continuation)


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
	return _finish_with_age_updates(events, "post-clock", _session_continuation)


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
	_session_continuation = {"kind": "item-use-target-selection", "characterId": character.id, "instanceId": instance.id, "spellId": spell.id, "power": power, "targetCount": required_count, "startingCharges": instance.charges}
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


func _equip_item(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ItemActionPayload
	var character := _state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _rules.inventory.equip_classic(character, instance, definition, _content.race_by_id(character.race_id), _content.caste_by_id(character.caste_id), _state.party.characters(), _content.item_definitions())
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_equip", probe.reason)
	return _finish_completed([DomainEvent.new(&"item_equipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "identified": instance.identified})])


func _unequip_item(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ItemActionPayload
	var character := _state.party.character_by_id(payload.actor_id)
	var instance := _item_instance(character, payload.item_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _rules.inventory.unequip_classic(character, instance, definition, _content.item_definitions())
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_unequip", probe.reason)
	return _finish_completed([DomainEvent.new(&"item_unequipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})])


func _trade_item(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.ItemActionPayload
	var source := _state.party.character_by_id(payload.actor_id)
	var destination := _state.party.character_by_id(payload.destination_character_id)
	var instance := _item_instance(source, payload.item_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if source == null or destination == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"invalid_item_trade", "Trade requires a carried item and two current party members.")
	var probe := _rules.inventory.trade_classic(source, destination, instance, definition)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_trade", probe.reason)
	return _finish_completed([DomainEvent.new(&"item_traded", {"fromCharacterId": source.id, "toCharacterId": destination.id, "instanceId": instance.id, "itemId": definition.id})])


func _set_location_note(text: String) -> SessionStep:
	var map := _content.world.map_by_id(_state.party.map_id)
	if map == null or map.topology.cell_at(_state.party.coordinate) == null:
		return SessionStep.failed(_view_revision, &"location_note_unavailable", "The current map location is unavailable.")
	if not LocationNoteState.text_is_valid(text):
		return SessionStep.failed(_view_revision, &"location_note_too_long", "Classic location notes are limited to 255 encoded bytes.")
	var existing := _state.world.location_note_at(map.id, _state.party.coordinate)
	var darkness_value := _current_location_note_darkness(map)
	if existing == null and not text.is_empty() and _state.world.next_location_note_ordinal(map.level_type) < 0:
		return SessionStep.failed(_view_revision, &"location_note_capacity", "The Classic location-note file for this map type is full.")
	if existing != null and existing.text == text and existing.darkness_value == darkness_value or existing == null and text.is_empty():
		return SessionStep.failed(_view_revision, &"location_note_unchanged", "Change or clear the current location note before saving.")
	var committed := false
	if text.is_empty():
		committed = _state.world.remove_location_note(map.id, _state.party.coordinate)
	else:
		var ordinal := existing.record_ordinal if existing != null else _state.world.next_location_note_ordinal(map.level_type)
		committed = _state.world.upsert_location_note(LocationNoteState.new(map.id, map.level_type, map.level_index, _state.party.coordinate, text, darkness_value, ordinal))
	if not committed:
		return SessionStep.failed(_view_revision, &"invalid_location_note", "The location note could not be committed.")
	var event_kind: StringName = &"location_note_removed" if text.is_empty() else &"location_note_updated"
	return _finish_completed([DomainEvent.new(event_kind, {
		"mapId": map.id,
		"x": _state.party.coordinate.x,
		"y": _state.party.coordinate.y,
		"textBytes": text.to_utf8_buffer().size(),
		"source": "classic",
	})])


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
	_session_continuation = {"kind": "drop-item-confirmation", "characterId": character.id, "instanceId": instance.id}
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
	_session_continuation = {"kind": "scroll-target-selection", "characterId": character.id, "scrollSlot": payload.scroll_slot, "spellId": spell.id, "power": scroll.power, "targetCount": required_count}
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
	_session_continuation = {"kind": "field-spell-target-selection", "characterId": character.id, "spellId": spell.id, "power": payload.power, "targetCount": required_count, "startingSpellPoints": character.spell_points}
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
	var result := _rules.combat_flow.submit_action(_state, _content, payload.actor_id, payload.action, payload.target_id, _rng)
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
	var state_checkpoint := _state.to_data()
	var rng_checkpoint := _rng.checkpoint()
	if not _state.set_combat_auto(payload.character_id, payload.enabled):
		return SessionStep.failed(_view_revision, &"invalid_combat_auto_character", "Persistent Auto could not be changed for this character.")
	var toggle_sound := 147 if payload.enabled else 139
	var events: Array[DomainEvent] = [
		DomainEvent.new(&"sound_requested", {"soundId": toggle_sound, "waitForCompletion": false, "source": "classic-combat-auto-toggle"}),
		DomainEvent.new(&"combat_auto_changed", {"characterId": payload.character_id, "enabled": payload.enabled, "source": "classic"}),
	]
	if payload.enabled and _state.combat.active_actor_id() == payload.character_id:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": 141, "waitForCompletion": false, "source": "classic-combat-auto-button"}))
		var result := _rules.combat_flow.run_persistent_auto_characters(_state, _content, _rng)
		if not result.ok:
			if not _state.restore_from_data(state_checkpoint) or not _rng.rollback(rng_checkpoint):
				return SessionStep.failed(_view_revision, &"combat_auto_rollback_failed", "Persistent Auto failed and could not restore its toggle transaction.")
			return SessionStep.failed(_view_revision, result.error_code, result.error_message)
		events.append_array(result.events)
		if not CharacterAgingResult.update_payloads(events).is_empty():
			return _finish_with_age_updates(events, "combat-monster-turns")
		if not _event_payload(events, &"monster_death_macro_requested").is_empty():
			return _start_session_death_macro(events)
		if result.completed:
			return _finish_direct_battle(events)
	return _finish_completed(events)


func _combat_move(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.CombatMovePayload
	var edge_probe: Variant = _rules.combat_flow.probe_edge_retreat(_state.combat, payload.actor_id, payload.destination)
	if edge_probe.allowed:
		if not edge_probe.forced:
			return _request_session_retreat(payload.actor_id, &"edge", payload.destination)
		var forced_result := _rules.combat_flow.retreat_character(_state, _content, payload.actor_id, &"edge", payload.destination, _rng)
		return _finish_combat_result(forced_result)
	var result := _rules.combat_flow.move_character(_state, _content, payload.actor_id, payload.destination, _rng)
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
	_session_continuation = {"kind": "combat-retreat-confirmation", "battleId": _state.combat.battle_id, "actorId": actor_id, "mode": String(mode), "destination": [destination.x, destination.y]}
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


func _set_party_setup_options(difficulty: int, monster_set: int) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party setup options are no longer available.")
	if difficulty < -2 or difficulty > 2:
		return SessionStep.failed(_view_revision, &"invalid_difficulty", "Classic difficulty must be between Novice and Veteran.")
	if not _content.available_monster_sets().has(monster_set):
		return SessionStep.failed(_view_revision, &"unavailable_monster_set", "That Classic monster set is not present in this campaign package.")
	_state.difficulty = difficulty
	_state.monster_set = monster_set
	return _finish_completed([DomainEvent.new(&"party_setup_options_changed", {"difficulty": difficulty, "monsterSet": monster_set})])


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
		_session_continuation = {"kind": "character-spell-confirmation", "characterId": draft.generated_character.id, "remaining": remaining}
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
	_session_continuation = {"kind": "character-vault-publication", "characterId": character.id}
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


func _remove_party_member(character_id: String) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party members can be removed only during party setup.")
	_state.set_combat_auto(character_id, false)
	if character_id.is_empty() or not _state.party.remove_character(character_id):
		return SessionStep.failed(_view_revision, &"unknown_party_member", "The selected character is not in the setup party.")
	_state.set_selected_character_ids([])
	return _finish_completed([DomainEvent.new(&"party_member_removed", {"characterId": character_id})])


func _reorder_party(character_ids: Array[String]) -> SessionStep:
	var current := _state.party.characters()
	if current.size() < 2:
		return SessionStep.failed(_view_revision, &"party_order_unavailable", "At least two party members are required to change party order.")
	var previous_ids: Array[String] = []
	for character: CharacterState in current:
		previous_ids.append(character.id)
	if not _state.party.reorder_characters(character_ids):
		return SessionStep.failed(_view_revision, &"invalid_party_order", "Party Order requires every current character exactly once.")
	return _finish_completed([DomainEvent.new(&"party_reordered", {"previousCharacterIds": previous_ids, "characterIds": character_ids.duplicate(), "source": "classic"})])


func _change_character_appearance(intent: PlayerIntent) -> SessionStep:
	var payload := intent.payload as PlayerIntent.AppearancePayload
	if not _state.party_setup_completed:
		return SessionStep.failed(_view_revision, &"appearance_change_unavailable", "Begin the adventure before changing appearance.")
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"appearance_change_unavailable", "Appearance changes are unavailable during battle.")
	if not _content.has_character_appearance_catalog():
		return SessionStep.failed(_view_revision, &"appearance_change_unavailable", "This package does not contain the complete Classic portrait and combat-icon catalogs.")
	var character := _state.party.character_by_id(payload.character_id)
	if character == null:
		return SessionStep.failed(_view_revision, &"unknown_party_member", "The selected character is not in the active party.")
	if payload.appearance_kind not in [CharacterAppearanceDefinition.PORTRAIT, CharacterAppearanceDefinition.COMBAT_ICON]:
		return SessionStep.failed(_view_revision, &"invalid_appearance_kind", "Choose either a portrait or a combat icon.")
	var appearance := _content.appearance_by_id(payload.appearance_id)
	if appearance == null or appearance.kind != payload.appearance_kind:
		return SessionStep.failed(_view_revision, &"invalid_character_appearance", "The selected appearance is unavailable for that role.")
	var previous_id := character.portrait_id if payload.appearance_kind == CharacterAppearanceDefinition.PORTRAIT else character.combat_icon_id
	if previous_id == appearance.id:
		return SessionStep.failed(_view_revision, &"appearance_unchanged", "Choose a different appearance before applying the change.")
	if payload.appearance_kind == CharacterAppearanceDefinition.PORTRAIT:
		character.portrait_id = appearance.id
	else:
		character.combat_icon_id = appearance.id
	return _finish_completed([DomainEvent.new(&"character_appearance_changed", {
		"characterId": character.id,
		"appearanceKind": String(payload.appearance_kind),
		"previousAppearanceId": previous_id,
		"appearanceId": appearance.id,
		"source": "classic-character-menu",
	})])


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


func _current_location_note_darkness(map: MapDefinition) -> int:
	if map == null or map.level_type == &"dungeon" or not _state.world.map_is_dark(map):
		return 0
	return clampi(int(_state.party.conditions.value(0) / 30) + 1, 1, 255)


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
		_session_continuation = {"kind": "pooled-wealth-departure", "stage": "warning", "directionX": direction.x, "directionY": direction.y}
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
	return _finish_with_age_updates(events, "post-clock", _session_continuation)


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
			return _finish_with_age_updates(blocked_events, "post-clock", _session_continuation)
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
	return _finish_with_age_updates(events, "post-clock", _session_continuation)


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
	_session_continuation = {
		"kind": "post-clock",
		"mapId": map.id,
		"x": _state.party.coordinate.x,
		"y": _state.party.coordinate.y,
		"timedDay": timed_day,
		"timedEncounterIndex": 0,
		"activeTimedProgramId": "",
		"midnightRecoveryPending": timed_day > 0,
		"timedCheckX": timed_coordinate.x,
		"timedCheckY": timed_coordinate.y,
		"checkRandom": check_random,
		"randomRegionIds": [] if cell == null else cell.random_rect_ids(),
		"randomRegionIndex": -1 if cell == null else cell.random_rect_ids().size() - 1,
		"activeRandomProgramId": "",
		"activeRandomRegionId": "",
		"randomBattleStage": "",
		"resumeKind": resume_kind,
		"directionX": direction.x,
		"directionY": direction.y,
	}


func _continue_post_time(events: Array[DomainEvent]) -> SessionStep:
	var active_timed_program_id := String(_session_continuation.get("activeTimedProgramId", ""))
	if not active_timed_program_id.is_empty() and not _rebase_post_time_location():
		_session_continuation.clear()
		return _finish_failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	var map := _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	if map == null or _state.party.map_id != map.id or _state.party.coordinate != Vector2i(int(_session_continuation.get("x", -1)), int(_session_continuation.get("y", -1))):
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation is unavailable.", events)
	if not active_timed_program_id.is_empty():
		_session_continuation["activeTimedProgramId"] = ""
	var timed_step := _continue_timed_encounters(events)
	if timed_step != null:
		return timed_step
	map = _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	if map == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_timed_encounter_location", "Timed encounter continuation references an unavailable map.", events)
	var active_program_id := String(_session_continuation.get("activeRandomProgramId", ""))
	if not active_program_id.is_empty():
		_session_continuation["activeRandomProgramId"] = ""
		return _complete_post_time(events)
	if bool(_session_continuation.get("checkRandom", false)) and _session_continuation.get("resumeKind") != "post-move":
		var random_step := _continue_random_regions(map, events)
		if random_step != null:
			return random_step
	return _complete_post_time(events)


func _complete_post_time(events: Array[DomainEvent]) -> SessionStep:
	var resume_kind := String(_session_continuation.get("resumeKind", ""))
	var direction := Vector2i(int(_session_continuation.get("directionX", 0)), int(_session_continuation.get("directionY", 0)))
	_session_continuation.clear()
	if resume_kind == "move":
		return _commit_move(direction, events)
	if resume_kind == "post-move":
		var map := _content.world.map_by_id(_state.party.map_id)
		_set_post_move_continuation(map, _state.party.coordinate)
		return _continue_post_move(events)
	if resume_kind == "completed":
		return _finish_completed(events)
	return _finish_failed(&"invalid_session_continuation", "Post-clock exploration continuation has no valid completion path.", events)


func _continue_timed_encounters(events: Array[DomainEvent]) -> SessionStep:
	var timed_day := int(_session_continuation.get("timedDay", 0))
	if timed_day <= 0:
		return null
	var encounters := _content.timed_encounters()
	while int(_session_continuation.get("timedEncounterIndex", 0)) < encounters.size():
		var index := int(_session_continuation["timedEncounterIndex"])
		var encounter := encounters[index]
		_session_continuation["timedEncounterIndex"] = index + 1
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
		_session_continuation["activeTimedProgramId"] = trigger.program_id
		events.append(DomainEvent.new(&"timed_encounter_triggered", {"encounterId": encounter.id, "triggerId": trigger.id, "programId": trigger.program_id}))
		var started := _scenario_vm.start_program(trigger.program_id, {"callingContext": "action", "triggerId": trigger.id, "mapId": map.id, "x": _session_continuation["timedCheckX"], "y": _session_continuation["timedCheckY"], "timedEncounterId": encounter.id})
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
		_session_continuation["activeTimedProgramId"] = ""
		if not _rebase_post_time_location():
			_session_continuation.clear()
			return _finish_failed(&"invalid_timed_encounter_location", "The completed timed encounter left the party at an unavailable location.", events)
	_apply_pending_midnight_recovery(events)
	_session_continuation["timedDay"] = 0
	return null


func _apply_pending_midnight_recovery(events: Array[DomainEvent]) -> void:
	if not bool(_session_continuation.get("midnightRecoveryPending", false)):
		return
	_session_continuation["midnightRecoveryPending"] = false
	events.append_array(_rules.clock.restore_half_day_health(_state.party, _content))


func _rebase_post_time_location() -> bool:
	var map := _content.world.map_by_id(_state.party.map_id)
	var cell: MapCell = null if map == null else map.topology.cell_at(_state.party.coordinate)
	if cell == null:
		return false
	_session_continuation["mapId"] = map.id
	_session_continuation["x"] = _state.party.coordinate.x
	_session_continuation["y"] = _state.party.coordinate.y
	_session_continuation["timedCheckX"] = _state.party.coordinate.x
	_session_continuation["timedCheckY"] = _state.party.coordinate.y
	_session_continuation["randomRegionIds"] = cell.random_rect_ids()
	_session_continuation["randomRegionIndex"] = cell.random_rect_ids().size() - 1
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
	var coordinate := Vector2i(int(_session_continuation.get("timedCheckX", -1)), int(_session_continuation.get("timedCheckY", -1)))
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
	_session_continuation = {
		"kind": "post-move",
		"mapId": map.id,
		"x": coordinate.x,
		"y": coordinate.y,
		"triggerIds": _selected_placed_trigger_ids(_content, cell),
		"triggerIndex": 0,
		"activeTriggerId": "",
		"randomRegionIds": cell.random_rect_ids(),
		"randomRegionIndex": cell.random_rect_ids().size() - 1,
		"activeRandomProgramId": "",
		"activeRandomRegionId": "",
		"randomBattleStage": "",
		"actionPointDestinationDepth": destination_depth,
	}


func _normalize_age_groups(state: GameState, content: RealmzContent, rules: RealmzRules) -> void:
	for character: CharacterState in state.party.characters():
		var race := content.race_by_id(character.race_id)
		var caste := content.caste_by_id(character.caste_id)
		if race != null and caste != null:
			rules.characters.ensure_age_group(character, race, caste)


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	if _events_have(events, &"destination_trigger_recheck_requested") and int(_session_continuation.get("actionPointDestinationDepth", 0)) == 0:
		var requested_map := _content.world.map_by_id(_state.party.map_id)
		if requested_map == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
		_set_post_move_continuation(requested_map, _state.party.coordinate, 1)
	var map := _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	var coordinate := Vector2i(int(_session_continuation.get("x", -1)), int(_session_continuation.get("y", -1)))
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	var active_random_program_id := String(_session_continuation.get("activeRandomProgramId", ""))
	if not active_random_program_id.is_empty():
		_session_continuation.clear()
		return _finish_completed(events)
	var active_trigger_id := String(_session_continuation.get("activeTriggerId", ""))
	if not active_trigger_id.is_empty():
		var completed_trigger := _content.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		_finalize_completed_trigger(completed_trigger, events)
		if _apply_trigger_destination(completed_trigger, events, int(_session_continuation.get("actionPointDestinationDepth", 0)) == 0):
			var destination_map := _content.world.map_by_id(_state.party.map_id)
			_set_post_move_continuation(destination_map, _state.party.coordinate, 1)
			return _continue_post_move(events)
		_session_continuation["activeTriggerId"] = ""
		_session_continuation["triggerIndex"] = _session_continuation["triggerIds"].size()
	var trigger_ids: Array = _session_continuation["triggerIds"]
	while int(_session_continuation["triggerIndex"]) < trigger_ids.size():
		var trigger_index: int = int(_session_continuation["triggerIndex"])
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger := _content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _state.world.trigger_is_disabled(trigger_id):
			_session_continuation["triggerIndex"] = trigger_ids.size()
			break
		var trigger_chance := _state.world.trigger_chance(trigger.id, trigger.chance_percent)
		if trigger_chance < 1:
			_session_continuation["triggerIndex"] = trigger_ids.size()
			break
		if trigger_chance < 100:
			var chance_roll := _rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger_chance:
				_session_continuation["triggerIndex"] = trigger_ids.size()
				break
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		_session_continuation["activeTriggerId"] = trigger.id
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
		if _apply_trigger_destination(trigger, events, int(_session_continuation.get("actionPointDestinationDepth", 0)) == 0):
			var destination_map := _content.world.map_by_id(_state.party.map_id)
			_set_post_move_continuation(destination_map, _state.party.coordinate, 1)
			return _continue_post_move(events)
		_session_continuation["activeTriggerId"] = ""
		_session_continuation["triggerIndex"] = trigger_ids.size()
	var random_step := _continue_random_regions(map, events)
	if random_step != null:
		return random_step
	_session_continuation.clear()
	return _finish_completed(events)


func _continue_exploration_continuation(events: Array[DomainEvent]) -> SessionStep:
	if _session_continuation.get("kind") == "application-hook":
		return _continue_application_hook(events)
	if _session_continuation.get("kind") == "post-clock":
		return _continue_post_time(events)
	if _session_continuation.get("kind") == "post-move":
		return _continue_post_move(events)
	return _finish_failed(&"invalid_session_continuation", "The completed scenario has no valid exploration continuation.", events)


func _start_application_hook(hook: StringName, resume_kind: String, service_id: String, preceding_events: Array[DomainEvent], suspended_context: Dictionary = {}) -> SessionStep:
	var program_id := _content.scenario.application_hook_program_id(hook)
	_session_continuation = {
		"kind": "application-hook",
		"hook": String(hook),
		"programId": program_id,
		"resumeKind": resume_kind,
		"serviceId": service_id,
		"partyRevived": false,
	}
	for key: Variant in suspended_context:
		_session_continuation[key] = suspended_context[key]
	if program_id.is_empty():
		return _continue_application_hook(preceding_events)
	var started := _scenario_vm.start_program(program_id, {
		"callingContext": "lifecycle",
		"applicationHook": String(hook),
		"serviceId": service_id,
	})
	if started.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(started.error_code, started.error_message, preceding_events)
	var result := _scenario_vm.run(_runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"application_hook_started", {"hook": String(hook), "programId": program_id}))
	events.append_array(result.events)
	if _events_have(result.events, &"party_revived"):
		_session_continuation["partyRevived"] = true
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _finish_failed(&"nested_party_defeat_handoff", "An application hook cannot suspend another total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(result.interaction, events)
	return _continue_application_hook(events)


func _continue_application_hook(events: Array[DomainEvent]) -> SessionStep:
	var hook := StringName(_session_continuation.get("hook", ""))
	var program_id := String(_session_continuation.get("programId", ""))
	var resume_kind := String(_session_continuation.get("resumeKind", ""))
	var service_id := String(_session_continuation.get("serviceId", ""))
	var party_revived := bool(_session_continuation.get("partyRevived", false))
	var suspended_vm: Dictionary = _session_continuation.get("suspendedVm", {}).duplicate(true)
	var suspended_owner: Dictionary = _session_continuation.get("suspendedOwner", {}).duplicate(true)
	var vm_handoff: Dictionary = _session_continuation.get("vmHandoff", {}).duplicate(true)
	_session_continuation.clear()
	if not program_id.is_empty():
		events.append(DomainEvent.new(&"application_hook_completed", {"hook": String(hook), "programId": program_id}))
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
	if _session_continuation.get("kind") not in ["post-clock", "post-move"]:
		_session_continuation.clear()
		return _finish_failed(&"unsupported_vm_handoff_owner", "Total-party defeat cannot suspend this scenario caller.", events)
	var saved := _scenario_vm.snapshot()
	if not ScenarioVm.handoff_is_valid(result.handoff, saved) or not RealmzRuntimeApi.party_defeat_handoff_is_valid(_content, _state, result.handoff["runtime"]):
		_session_continuation.clear()
		return _finish_failed(&"invalid_party_defeat_handoff", "The Scenario VM total-party defeat handoff is invalid.", events)
	var suspended_context := {
		"suspendedVm": saved.to_data(),
		"suspendedOwner": _session_continuation.duplicate(true),
		"vmHandoff": result.handoff.duplicate(true),
	}
	_scenario_vm.reset()
	return _start_application_hook(ScenarioApplicationHooks.PARTY_DEATH, "scenario-party-defeat", "", events, suspended_context)


func _resume_scenario_party_defeat(suspended_vm_data: Dictionary, suspended_owner: Dictionary, vm_handoff: Dictionary, events: Array[DomainEvent]) -> SessionStep:
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
	_session_continuation = suspended_owner.duplicate(true)
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
	_session_continuation = {
		"kind": "combat-death-macro",
		"battleId": combat.battle_id,
		"combatantId": combatant_id,
		"programId": program_id,
		"resetTraitorOnComplete": bool(request.get("resetTraitorOnComplete", true)),
	}
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
	var battle_id := str(_session_continuation.get("battleId", ""))
	var combatant_id := str(_session_continuation.get("combatantId", ""))
	var program_id := str(_session_continuation.get("programId", ""))
	if combat == null or combat.battle_id != battle_id:
		_session_continuation.clear()
		return _finish_failed(&"invalid_battle_continuation", "Monster death-macro completion lost its battle.", events)
	var monster := combat.monster_by_id(combatant_id)
	if monster != null and bool(_session_continuation.get("resetTraitorOnComplete", true)):
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
		_session_continuation = {"kind": "combat-ally-selection", "battleId": _state.combat.battle_id}
		_session_interaction = InteractionRequest.from_payload(request_id, &"ally_selection", payload)
		return _finish_waiting(_session_interaction, events)
	return _finish_direct_battle_recovery(events)


func _finish_direct_battle_recovery(events: Array[DomainEvent]) -> SessionStep:
	var payload := _rules.combat_flow.fumble_recovery_payload(_state, _content)
	if not payload.is_empty():
		var request_id := "session.fumble-recovery.%d" % (_view_revision + 1)
		_session_continuation = {"kind": "combat-fumble-recovery", "battleId": _state.combat.battle_id}
		_session_interaction = InteractionRequest.from_payload(request_id, InteractionRequest.TREASURE_DISTRIBUTION, payload)
		return _finish_waiting(_session_interaction, events)
	return _begin_direct_battle_reward(events)


func _finish_direct_battle_without_rewards(events: Array[DomainEvent]) -> SessionStep:
	if _state.combat == null or not _state.combat.completed:
		return _finish_failed(&"invalid_battle_continuation", "Suppressed battle rewards require a completed battle.", events)
	var battle_id := _state.combat.battle_id
	var return_continuation: Dictionary = _state.combat.return_continuation.duplicate(true)
	var battle_outcome := _state.combat.outcome
	events.append(DomainEvent.new(&"battle_returned", {"battleId": battle_id, "outcome": String(battle_outcome)}))
	_state.combat = null
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionStep:
	var return_continuation: Dictionary = _state.combat.return_continuation.duplicate(true)
	var battle_outcome := _state.combat.outcome
	var request_id := "session.battle-reward.%d" % (_view_revision + 1)
	var operation := _runtime_api.begin_completed_battle_reward(request_id)
	events.append_array(operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(operation.error_code, operation.error_message, events)
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		_session_continuation = {"kind": "combat-reward", "battleId": _state.combat.battle_id, "runtimeContinuation": operation.continuation.duplicate(true)}
		_session_interaction = operation.interaction
		return _finish_waiting(_session_interaction, events)
	_session_interaction = null
	_session_continuation.clear()
	return _finish_after_direct_battle(events, return_continuation, battle_outcome)


func _finish_after_direct_battle(events: Array[DomainEvent], return_continuation: Dictionary, battle_outcome: StringName) -> SessionStep:
	if return_continuation.is_empty() or battle_outcome == &"defeat" or not _events_have(events, &"battle_returned"):
		return _finish_completed(events)
	_session_continuation = return_continuation.duplicate(true)
	return _continue_post_time(events)


func _continue_random_regions(map: MapDefinition, events: Array[DomainEvent]) -> SessionStep:
	if not _state.random_encounters_enabled:
		return null
	var region_ids: Array = _session_continuation["randomRegionIds"]
	while int(_session_continuation["randomRegionIndex"]) >= 0:
		var region_index: int = int(_session_continuation["randomRegionIndex"])
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
				_session_continuation["activeRandomProgramId"] = program_id
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
					_session_continuation["activeRandomRegionId"] = region.id
					_session_continuation["randomBattleStage"] = "surprise-choice"
					var request_id := "random-surprise:%s:%d" % [region.id, _rng.snapshot().draw_count]
					_session_interaction = InteractionRequest.from_payload(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
					if region.sound_id > 0:
						events.append(DomainEvent.new(&"audio_requested", {"soundId": region.sound_id}))
					return _finish_waiting(_session_interaction, events)
				var bad_surprise_roll := _rng.draw(100, StringName("random-region.%s.bad-surprise" % region.id))
				var surprise := -1 if bad_surprise_roll < 10 else 0
				return _start_random_battle(region, surprise, events)
		_session_continuation["randomRegionIndex"] = region_index - 1
		if region.only:
			break
	return null


func _complete_random_program(events: Array[DomainEvent]) -> SessionStep:
	if _session_continuation.get("kind") == "post-clock":
		_session_continuation["activeRandomProgramId"] = ""
		return _complete_post_time(events)
	_session_continuation.clear()
	return _finish_completed(events)


func _finish_completed(events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.completed(_view_revision, events)


func _finish_waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.waiting(_view_revision, request, events)


func _finish_failed(code: StringName, message: String, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.failed(_view_revision, code, message, events)


func _pending_interaction() -> InteractionRequest:
	return _session_interaction if _session_interaction != null else _scenario_vm.pending_request()


func _respond_session_interaction(response: InteractionResponse) -> SessionStep:
	if _session_continuation.get("kind") == "pooled-wealth-departure":
		return _respond_pooled_wealth_departure(response)
	if _session_continuation.get("kind") == "service-interaction":
		return _respond_runtime_service(response)
	if _session_continuation.get("kind") == "drop-item-confirmation":
		return _respond_drop_item(response)
	if _session_continuation.get("kind") == "item-use-target-selection":
		return _respond_item_use_target(response)
	if _session_continuation.get("kind") == "field-spell-target-selection":
		return _respond_field_spell_target(response)
	if _session_continuation.get("kind") == "scroll-target-selection":
		return _respond_scroll_target(response)
	if _session_continuation.get("kind") == "character-spell-confirmation":
		return _respond_character_spell_confirmation(response)
	if _session_continuation.get("kind") == "character-vault-publication":
		return _respond_character_vault_publication(response)
	if _session_continuation.get("kind") == "age-updates":
		return _respond_session_age_update(response)
	if _session_continuation.get("kind") == "combat-ally-selection":
		return _respond_session_ally_selection(response)
	if _session_continuation.get("kind") == "combat-fumble-recovery":
		return _respond_session_fumble_recovery(response)
	if _session_continuation.get("kind") == "combat-reward":
		return _respond_session_battle_reward(response)
	if _session_continuation.get("kind") == "combat-retreat-confirmation":
		return _respond_session_retreat(response)
	var surprise_body := response.body as InteractionResponse.YesNoBody
	if response.kind != &"yes_no" or surprise_body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "The random encounter response must be a yes/no choice.")
	if _session_continuation.get("randomBattleStage", "") != "surprise-choice":
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The random encounter choice has no matching continuation.")
	var map := _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	var region_id := String(_session_continuation.get("activeRandomRegionId", ""))
	var region: RandomEncounterRegion = null if map == null else map.random_region_by_id(region_id)
	if region == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The random encounter choice references unavailable content.")
	_session_interaction = null
	_session_continuation["activeRandomRegionId"] = ""
	_session_continuation["randomBattleStage"] = ""
	var events: Array[DomainEvent] = [DomainEvent.new(&"random_surprise_chosen", {"regionId": region.id, "accepted": surprise_body.accepted})]
	if surprise_body.accepted:
		return _start_random_battle(region, 1, events)
	_session_continuation["randomRegionIndex"] = int(_session_continuation["randomRegionIndex"]) - 1
	if region.only:
		if _session_continuation.get("kind") == "post-clock":
			return _complete_post_time(events)
		_session_continuation.clear()
		return _finish_completed(events)
	var next_step := _continue_random_regions(map, events)
	if next_step != null:
		return next_step
	if _session_continuation.get("kind") == "post-clock":
		return _complete_post_time(events)
	_session_continuation.clear()
	return _finish_completed(events)


func _respond_pooled_wealth_departure(response: InteractionResponse) -> SessionStep:
	var stage := String(_session_continuation.get("stage", ""))
	var direction := Vector2i(int(_session_continuation.get("directionX", 0)), int(_session_continuation.get("directionY", 0)))
	if stage == "warning":
		var warning_body := response.body as InteractionResponse.YesNoBody
		if response.kind != InteractionRequest.YES_NO or warning_body == null:
			return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Pooled-wealth departure requires a yes/no response.")
		if warning_body.accepted:
			_session_continuation["stage"] = "distribution"
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
	if stage != "distribution" or response.kind != InteractionRequest.POOLED_WEALTH_DEPARTURE or body == null:
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
	var character_id := String(_session_continuation.get("characterId", ""))
	var instance_id := String(_session_continuation.get("instanceId", ""))
	var spell_id := String(_session_continuation.get("spellId", ""))
	var power := int(_session_continuation.get("power", 0))
	var expected_count := int(_session_continuation.get("targetCount", 0))
	if target_ids.size() != expected_count:
		return SessionStep.failed(_view_revision, &"invalid_item_use_target", "The item requires exactly %d target%s." % [expected_count, "" if expected_count == 1 else "s"])
	var character := _state.party.character_by_id(character_id)
	var instance := _item_instance(character, instance_id)
	if instance == null or instance.charges != int(_session_continuation.get("startingCharges", -100_000)):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The item awaiting a target no longer matches its committed state.")
	var saved_continuation := _session_continuation.duplicate(true)
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _commit_field_spell_item(character_id, instance_id, spell_id, power, target_ids)
	if completed.state == SessionStep.State.FAILED:
		_session_continuation = saved_continuation
		_session_interaction = saved_interaction
	return completed


func _respond_field_spell_target(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Field casting requires an ordered characterIds array.")
	var target_ids := body.character_ids.duplicate()
	var expected_count := int(_session_continuation.get("targetCount", 0))
	if target_ids.size() != expected_count:
		return SessionStep.failed(_view_revision, &"invalid_field_spell_target", "The spell requires exactly %d target%s." % [expected_count, "" if expected_count == 1 else "s"])
	var character_id := String(_session_continuation.get("characterId", ""))
	var spell_id := String(_session_continuation.get("spellId", ""))
	var power := int(_session_continuation.get("power", 0))
	var character := _state.party.character_by_id(character_id)
	if character == null or character.spell_points != int(_session_continuation.get("startingSpellPoints", -100_000)):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The field spell awaiting a target no longer matches its committed state.")
	var saved_continuation := _session_continuation.duplicate(true)
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _commit_field_spell(character_id, spell_id, power, target_ids)
	if completed.state == SessionStep.State.FAILED:
		_session_continuation = saved_continuation
		_session_interaction = saved_interaction
	return completed


func _respond_scroll_target(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.SelectionBody
	if response.kind != InteractionRequest.CHARACTER_SELECTION or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Scroll use requires an ordered characterIds array.")
	var target_ids := body.character_ids.duplicate()
	var expected_count := int(_session_continuation.get("targetCount", 0))
	if target_ids.size() != expected_count:
		return SessionStep.failed(_view_revision, &"invalid_scroll_target", "The scroll requires exactly %d target%s." % [expected_count, "" if expected_count == 1 else "s"])
	var character_id := String(_session_continuation.get("characterId", ""))
	var slot_index := int(_session_continuation.get("scrollSlot", -1))
	var spell_id := String(_session_continuation.get("spellId", ""))
	var power := int(_session_continuation.get("power", 0))
	var character := _state.party.character_by_id(character_id)
	var scroll := character.scroll_at(slot_index) if character != null else null
	if scroll == null or scroll.spell_id != spell_id or scroll.power != power:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The scroll awaiting a target no longer matches its committed state.")
	var saved_continuation := _session_continuation.duplicate(true)
	var saved_interaction := _session_interaction
	_session_continuation.clear()
	_session_interaction = null
	var completed := _commit_field_scroll(character_id, slot_index, spell_id, power, target_ids)
	if completed.state == SessionStep.State.FAILED:
		_session_continuation = saved_continuation
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
	_session_continuation = {"kind": "service-interaction", "serviceId": service_id, "runtimeContinuation": operation.continuation.duplicate(true)}
	_session_interaction = operation.interaction
	return _finish_waiting(_session_interaction, operation.events)


func _respond_runtime_service(response: InteractionResponse) -> SessionStep:
	var runtime_continuation: Variant = _session_continuation.get("runtimeContinuation")
	if not runtime_continuation is Dictionary:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The pending service has no runtime continuation.")
	var result := _runtime_api.resume_classic(runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		_session_continuation["runtimeContinuation"] = result.continuation.duplicate(true)
		_session_interaction = result.interaction
		return _finish_waiting(_session_interaction, result.events)
	_session_interaction = null
	_session_continuation.clear()
	return _finish_completed(result.events)


func _respond_drop_item(response: InteractionResponse) -> SessionStep:
	var body := response.body as InteractionResponse.YesNoBody
	if response.kind != InteractionRequest.YES_NO or body == null:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Dropping an item requires a yes/no response.")
	var character_id := String(_session_continuation.get("characterId", ""))
	var instance_id := String(_session_continuation.get("instanceId", ""))
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
	var character_id := String(_session_continuation.get("characterId", ""))
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
	var character_id := String(_session_continuation.get("characterId", ""))
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
	if _state.combat == null or _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId") or _state.combat.active_actor_id() != _session_continuation.get("actorId"):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting Escape confirmation is unavailable.")
	var continuation := _session_continuation.duplicate(true)
	_session_interaction = null
	_session_continuation.clear()
	if not body.accepted:
		return _finish_completed([DomainEvent.new(&"combat_retreat_declined", {"actorId": continuation["actorId"], "mode": continuation["mode"], "source": "classic"})])
	var destination := _combat_retreat_destination(continuation["destination"])
	if destination == Vector2i(-100_000, -100_000) and continuation["mode"] == "edge":
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The saved battlefield-edge Escape destination is invalid.")
	var result := _rules.combat_flow.retreat_character(_state, _content, continuation["actorId"], StringName(continuation["mode"]), destination, _rng)
	return _finish_combat_result(result)


static func _combat_retreat_destination(value: Variant) -> Vector2i:
	if not value is Array or value.size() != 2 or not value[0] is int or not value[1] is int:
		return Vector2i(-100_000, -100_000)
	return Vector2i(value[0], value[1])


func _finish_with_age_updates(events: Array[DomainEvent], resume_kind: String, resume_continuation: Dictionary = {}) -> SessionStep:
	var updates := CharacterAgingResult.update_payloads(events)
	if updates.is_empty():
		if resume_kind == "post-move":
			_session_continuation = resume_continuation.duplicate(true)
			return _continue_post_move(events)
		if resume_kind == "post-clock":
			_session_continuation = resume_continuation.duplicate(true)
			return _continue_post_time(events)
		if resume_kind == "combat-monster-turns":
			return _continue_after_session_combat_age_update(events)
		return _finish_completed(events)
	_session_continuation = {
		"kind": "age-updates",
		"updates": updates,
		"index": 1,
		"resumeKind": resume_kind,
		"resumeContinuation": resume_continuation.duplicate(true),
	}
	_session_interaction = InteractionRequest.age_update(_session_age_update_request_id(updates[0], 0), updates[0])
	events.append(CharacterAgingResult.sound_event(updates[0]))
	return _finish_waiting(_session_interaction, events)


func _respond_session_age_update(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.AGE_UPDATE or response.body is not InteractionResponse.EmptyBody:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Classic age updates require an empty age-update acknowledgement.")
	var updates: Variant = _session_continuation.get("updates", [])
	var index := int(_session_continuation.get("index", -1))
	if not updates is Array or updates.is_empty() or index < 1 or index > updates.size():
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The age-update queue is unavailable.")
	var acknowledged: Dictionary = updates[index - 1]
	var events: Array[DomainEvent] = [DomainEvent.new(&"character_age_update_acknowledged", {"characterId": acknowledged.get("characterId", "")})]
	if index < updates.size():
		var next_payload: Dictionary = updates[index]
		_session_continuation["index"] = index + 1
		_session_interaction = InteractionRequest.age_update(_session_age_update_request_id(next_payload, index), next_payload)
		events.append(CharacterAgingResult.sound_event(next_payload))
		return _finish_waiting(_session_interaction, events)
	var resume_kind := String(_session_continuation.get("resumeKind", ""))
	var resume_continuation: Dictionary = _session_continuation.get("resumeContinuation", {}).duplicate(true)
	_session_interaction = null
	_session_continuation.clear()
	if resume_kind == "post-move":
		_session_continuation = resume_continuation
		return _continue_post_move(events)
	if resume_kind == "post-clock":
		_session_continuation = resume_continuation
		return _continue_post_time(events)
	if resume_kind == "combat-monster-turns":
		return _continue_after_session_combat_age_update(events)
	if resume_kind == "completed":
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
	if _state.combat == null or not _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId"):
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
	if _state.combat == null or not _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId"):
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
	if _state.combat == null or not _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId"):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for reward distribution.")
	var runtime_continuation: Variant = _session_continuation.get("runtimeContinuation")
	if not runtime_continuation is Dictionary:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The battle reward continuation is unavailable.")
	var return_continuation: Dictionary = _state.combat.return_continuation.duplicate(true)
	var battle_outcome := _state.combat.outcome
	var result := _runtime_api.resume_classic(runtime_continuation, response, response.request_id)
	if result.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _finish_failed(result.error_code, result.error_message, result.events)
	if result.state == ScenarioRuntimeOperationResult.State.WAITING:
		_session_continuation["runtimeContinuation"] = result.continuation.duplicate(true)
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
	if _state.combat != null and _session_continuation.get("kind") == "post-clock":
		_session_continuation["randomRegionIndex"] = -1 if region.only else int(_session_continuation.get("randomRegionIndex", 0)) - 1
		_state.combat.return_continuation = _session_continuation.duplicate(true)
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


static func _valid_session_continuation(content: RealmzContent, state: GameState, continuation: Dictionary, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	if continuation.get("kind") == "application-hook":
		var hook_fields: Array[String] = ["kind", "hook", "programId", "resumeKind", "serviceId", "partyRevived"]
		var scenario_defeat: bool = continuation.get("resumeKind") == "scenario-party-defeat"
		if scenario_defeat:
			hook_fields.append_array(["suspendedVm", "suspendedOwner", "vmHandoff"])
		if continuation.size() != hook_fields.size() or vm_interaction == null or session_interaction != null:
			return false
		for field: String in hook_fields:
			if not continuation.has(field):
				return false
		if not continuation["hook"] is String or not continuation["programId"] is String or continuation["programId"].is_empty() or not continuation["resumeKind"] is String or not continuation["serviceId"] is String or not continuation["partyRevived"] is bool:
			return false
		var hook := StringName(continuation["hook"])
		if content.scenario.application_hook_program_id(hook) != continuation["programId"] or content.scenario.program_by_id(continuation["programId"]) == null:
			return false
		var resume_kind: String = continuation["resumeKind"]
		var service_id: String = continuation["serviceId"]
		match resume_kind:
			"begin-adventure":
				return hook == ScenarioApplicationHooks.START_GAME and service_id.is_empty() and state.party_setup_completed and not state.party.characters().is_empty()
			"service":
				return hook in [ScenarioApplicationHooks.SHOP, ScenarioApplicationHooks.TEMPLE] and not service_id.is_empty() and ((service_id == state.active_shop_id and content.shop_by_id(service_id) != null) or (service_id == "realmz.service.temple" and state.temple_available))
			"end-adventure":
				return hook == ScenarioApplicationHooks.END_ADVENTURE and service_id.is_empty()
			"end-adventure-close":
				return hook == ScenarioApplicationHooks.PARTY_DEATH and service_id.is_empty()
			"party-defeat":
				return hook == ScenarioApplicationHooks.PARTY_DEATH and service_id.is_empty() and state.combat != null and state.combat.completed and state.combat.outcome == &"defeat"
			"scenario-party-defeat":
				if hook != ScenarioApplicationHooks.PARTY_DEATH or not service_id.is_empty() or not continuation.get("suspendedVm") is Dictionary or not continuation.get("suspendedOwner") is Dictionary or not continuation.get("vmHandoff") is Dictionary:
					return false
				var saved := ScenarioVmSnapshot.from_data(continuation["suspendedVm"])
				var vm_handoff: Dictionary = continuation["vmHandoff"]
				return ScenarioVm.handoff_is_valid(vm_handoff, saved) and RealmzRuntimeApi.party_defeat_handoff_is_valid(content, state, vm_handoff.get("runtime")) and _valid_suspended_scenario_owner(content, state, continuation["suspendedOwner"], saved)
		return false
	if continuation.get("kind") == "pooled-wealth-departure":
		var departure_fields: Array[String] = ["kind", "stage", "directionX", "directionY"]
		if continuation.size() != departure_fields.size() or vm_interaction != null or session_interaction == null or state.party == null or state.bank_available:
			return false
		for field: String in departure_fields:
			if not continuation.has(field):
				return false
		if not continuation["stage"] is String or not continuation["directionX"] is int or not continuation["directionY"] is int:
			return false
		var departure_direction := Vector2i(continuation["directionX"], continuation["directionY"])
		var departure_probe := content.world.probe_movement(state.party.map_id, state.party.coordinate, departure_direction, state.world)
		if not departure_probe.allowed and departure_probe.reason == &"invalid_direction":
			return false
		match String(continuation["stage"]):
			"warning":
				return _has_pooled_wealth(state.party) and session_interaction.to_data() == _pooled_wealth_departure_warning(session_interaction.request_id).to_data()
			"distribution":
				var bank_body := session_interaction.body as InteractionRequest.BankRequestBody
				if session_interaction.kind != InteractionRequest.POOLED_WEALTH_DEPARTURE or bank_body == null or bank_body.mode != &"departure":
					return false
				var selected_character_id := bank_body.selected_character_id
				if state.party.character_by_id(selected_character_id) == null:
					return false
				return session_interaction.to_data() == _pooled_wealth_departure_distribution_request_for_state(state, session_interaction.request_id, selected_character_id).to_data()
		return false
	if continuation.get("kind") == "service-interaction":
		if continuation.size() != 3 or vm_interaction != null or session_interaction == null or not continuation.get("serviceId") is String or not continuation.get("runtimeContinuation") is Dictionary:
			return false
		var service_id: String = continuation["serviceId"]
		var runtime: Dictionary = continuation["runtimeContinuation"]
		var selected_temple_character: Variant = runtime.get("selectedCharacterId")
		match String(runtime.get("kind", "")):
			"classic-shop":
				return service_id == state.active_shop_id and not service_id.is_empty() and content.shop_by_id(service_id) != null and session_interaction.kind == InteractionRequest.SHOP
			"classic-temple":
				var temple_body := session_interaction.body as InteractionRequest.TempleRequestBody
				return service_id == "realmz.service.temple" and state.temple_available and int(runtime.get("costPercent", -100_000)) == state.temple_cost_percent and bool(runtime.get("bankAvailable", false)) == state.bank_available and selected_temple_character is String and state.party.character_by_id(String(selected_temple_character)) != null and session_interaction.kind == InteractionRequest.TEMPLE and temple_body != null and temple_body.selected_character_id == selected_temple_character
			"classic-temple-exit":
				return service_id == "realmz.service.temple" and state.temple_available and not state.bank_available and int(runtime.get("costPercent", -100_000)) == state.temple_cost_percent and not bool(runtime.get("bankAvailable", true)) and selected_temple_character is String and state.party.character_by_id(String(selected_temple_character)) != null and session_interaction.kind == InteractionRequest.YES_NO
			"classic-banking":
				return service_id == "realmz.service.bank" and state.bank_available and session_interaction.kind == InteractionRequest.BANK
		return false
	if continuation.get("kind") == "drop-item-confirmation":
		var drop_fields: Array[String] = ["kind", "characterId", "instanceId"]
		if continuation.size() != drop_fields.size() or vm_interaction != null or session_interaction == null:
			return false
		for field: String in drop_fields:
			if not continuation.has(field) or not continuation[field] is String or continuation[field].is_empty():
				return false
		var character := state.party.character_by_id(continuation["characterId"])
		if character == null:
			return false
		var instance: ItemInstance = null
		for carried: ItemInstance in character.inventory():
			if carried.id == continuation["instanceId"]:
				instance = carried
				break
		var definition: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
		if instance == null or definition == null or not RealmzRules.new().inventory.classic_drop_probe(character, instance).allowed:
			return false
		var display_name := definition.name if instance.identified else definition.unidentified_name
		return session_interaction.to_data() == _drop_item_confirmation_request(session_interaction.request_id, display_name).to_data()
	if continuation.get("kind") == "item-use-target-selection":
		var item_fields: Array[String] = ["kind", "characterId", "instanceId", "spellId", "power", "targetCount", "startingCharges"]
		if continuation.size() != item_fields.size() or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.CHARACTER_SELECTION or state.combat != null:
			return false
		for field: String in item_fields:
			if not continuation.has(field):
				return false
		if not continuation["characterId"] is String or not continuation["instanceId"] is String or not continuation["spellId"] is String or not continuation["power"] is int or not continuation["targetCount"] is int or not continuation["startingCharges"] is int:
			return false
		var item_character := state.party.character_by_id(continuation["characterId"])
		var item_instance: ItemInstance = null
		if item_character != null:
			for carried: ItemInstance in item_character.inventory():
				if carried.id == continuation["instanceId"]:
					item_instance = carried
					break
		var item_definition: ItemDefinition = null if item_instance == null else content.item_by_id(item_instance.definition_id)
		var item_spell := content.spell_by_id(continuation["spellId"])
		if item_character == null or item_instance == null or item_definition == null or item_spell == null or item_definition.special_2 != item_spell.classic_id or item_instance.charges != continuation["startingCharges"]:
			return false
		var item_power: int = continuation["power"]
		if item_power < 1 or item_power > 7:
			return false
		var authored_power := absi(item_definition.special_1)
		if authored_power != 8 and item_power != authored_power:
			return false
		var expected_count := state.party.characters().size() if item_spell.target_type > 2 else mini(item_power, state.party.characters().size()) if item_spell.target_type == 0 else 1
		if continuation["targetCount"] != expected_count or item_spell.target_type in [5, 7] or item_spell.target_type < 0 or item_spell.target_type > 12:
			return false
		var item_probe := RealmzRules.new().inventory.classic_spell_item_probe(item_character, item_instance, item_definition, item_spell, content.race_by_id(item_character.race_id), content.caste_by_id(item_character.caste_id), false)
		var item_effect_supported := item_spell.special == 0 and absi(item_spell.damage_type) >= 1 and absi(item_spell.damage_type) <= 6 and absi(item_spell.spell_class) != 9 or absi(item_spell.special) == 57
		return item_probe.allowed and item_effect_supported and session_interaction.to_data() == _item_target_request(session_interaction.request_id, item_character, item_instance.id, item_definition, item_spell, expected_count, state.party.characters()).to_data()
	if continuation.get("kind") == "field-spell-target-selection":
		var field_spell_fields: Array[String] = ["kind", "characterId", "spellId", "power", "targetCount", "startingSpellPoints"]
		if continuation.size() != field_spell_fields.size() or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.CHARACTER_SELECTION or state.combat != null:
			return false
		for field: String in field_spell_fields:
			if not continuation.has(field):
				return false
		if not continuation["characterId"] is String or not continuation["spellId"] is String or not continuation["power"] is int or not continuation["targetCount"] is int or not continuation["startingSpellPoints"] is int:
			return false
		var field_character := state.party.character_by_id(continuation["characterId"])
		var field_spell := content.spell_by_id(continuation["spellId"])
		var field_power: int = continuation["power"]
		if field_character == null or field_spell == null or not field_character.known_spells().has(field_spell.id) or field_character.spell_points != continuation["startingSpellPoints"] or field_power < 1 or field_power > 7:
			return false
		if state.character_spellcasting_blocked or field_character.current_health < 1 or field_character.spell_points < absi(field_spell.cost * field_power) or not field_spell.in_camp or field_spell.cost < 0 and field_power != 1:
			return false
		for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
			if field_character.conditions.is_active(condition):
				return false
		var field_special := absi(field_spell.special)
		var supported := field_special == 68 or field_special > 0 and field_special < 41 or field_special in [48, 57, 59, 60, 61, 64, 66, 91, 92] or field_special > 99 or field_special == 0 and absi(field_spell.damage_type) >= 1 and absi(field_spell.damage_type) < 8 and (field_spell.damage_min != 0 or field_spell.damage_max != 0 or field_spell.power_damage_min != 0 or field_spell.power_damage_max != 0)
		var expected_field_count := mini(field_power, state.party.characters().size()) if field_spell.target_type == 0 else 1
		if continuation["targetCount"] != expected_field_count or field_spell.target_type < 0 or field_spell.target_type > 2 or not supported:
			return false
		return session_interaction.to_data() == _field_spell_target_request(session_interaction.request_id, field_character, field_spell, expected_field_count, state.party.characters()).to_data()
	if continuation.get("kind") == "scroll-target-selection":
		var scroll_fields: Array[String] = ["kind", "characterId", "scrollSlot", "spellId", "power", "targetCount"]
		if continuation.size() != scroll_fields.size() or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.CHARACTER_SELECTION or state.combat != null:
			return false
		for field: String in scroll_fields:
			if not continuation.has(field):
				return false
		if not continuation["characterId"] is String or not continuation["scrollSlot"] is int or not continuation["spellId"] is String or not continuation["power"] is int or not continuation["targetCount"] is int:
			return false
		var scroll_character := state.party.character_by_id(continuation["characterId"])
		var scroll_slot: int = continuation["scrollSlot"]
		var scroll_spell := content.spell_by_id(continuation["spellId"])
		var scroll_power: int = continuation["power"]
		var scroll_state := scroll_character.scroll_at(scroll_slot) if scroll_character != null else null
		if scroll_character == null or scroll_state == null or scroll_spell == null or scroll_state.spell_id != scroll_spell.id or scroll_state.power != scroll_power or scroll_power < 1 or scroll_power > 7:
			return false
		if scroll_character.current_health < 1 or scroll_character.conditions.is_active(ConditionRules.ANIMATED) or not scroll_spell.in_camp:
			return false
		var has_case := false
		for carried: ItemInstance in scroll_character.inventory():
			var carried_definition := content.item_by_id(carried.definition_id)
			if carried.equipped and carried_definition != null and absi(carried_definition.item_type) == 13:
				has_case = true
				break
		if not has_case:
			return false
		var scroll_special := absi(scroll_spell.special)
		var scroll_supported := scroll_special == 68 or scroll_special > 0 and scroll_special < 41 or scroll_special in [48, 57, 59, 60, 61, 64, 66, 91, 92] or scroll_special > 99 or scroll_special == 0 and absi(scroll_spell.damage_type) >= 1 and absi(scroll_spell.damage_type) < 8 and (scroll_spell.damage_min != 0 or scroll_spell.damage_max != 0 or scroll_spell.power_damage_min != 0 or scroll_spell.power_damage_max != 0)
		var expected_scroll_count := mini(scroll_power, state.party.characters().size()) if scroll_spell.target_type == 0 else 1
		if continuation["targetCount"] != expected_scroll_count or scroll_spell.target_type < 0 or scroll_spell.target_type > 2 or not scroll_supported:
			return false
		return session_interaction.to_data() == _scroll_target_request(session_interaction.request_id, scroll_character, scroll_slot, scroll_spell, expected_scroll_count, state.party.characters()).to_data()
	if continuation.get("kind") == "character-spell-confirmation":
		var spell_fields: Array[String] = ["kind", "characterId", "remaining"]
		if continuation.size() != spell_fields.size() or vm_interaction != null or session_interaction == null:
			return false
		for field: String in spell_fields:
			if not continuation.has(field):
				return false
		if state.party_setup_completed or state.character_draft == null or state.character_draft.generated_character == null:
			return false
		var character := state.character_draft.generated_character
		if not continuation["characterId"] is String or continuation["characterId"] != character.id or not continuation["remaining"] is int or continuation["remaining"] < 1:
			return false
		var rules := RealmzRules.new()
		var caste := content.caste_by_id(character.caste_id)
		var spent := 0
		for spell_id: String in character.known_spells():
			spent += rules.characters.spell_selection_cost(content.spell_by_id(spell_id))
		var remaining := maxi(0, rules.characters.spell_selection_total(character, caste) - spent)
		return remaining == continuation["remaining"] and session_interaction.to_data() == _character_spell_confirmation_request(session_interaction.request_id, remaining).to_data()
	if continuation.get("kind") == "character-vault-publication":
		if continuation.size() != 2 or vm_interaction != null or session_interaction == null or state.party_setup_completed:
			return false
		var character_id: Variant = continuation.get("characterId")
		if not character_id is String or character_id.is_empty():
			return false
		var character := state.party.character_by_id(character_id)
		return character != null and session_interaction.to_data() == _character_vault_confirmation_request(session_interaction.request_id, character.name).to_data()
	if continuation.get("kind") == "combat-retreat-confirmation":
		var retreat_fields: Array[String] = ["kind", "battleId", "actorId", "mode", "destination"]
		if continuation.size() != retreat_fields.size():
			return false
		for field: String in retreat_fields:
			if not continuation.has(field):
				return false
		if not continuation["battleId"] is String or continuation["battleId"].is_empty() or not continuation["actorId"] is String or continuation["actorId"].is_empty() or continuation["mode"] not in ["explicit", "edge"]:
			return false
		var destination := _combat_retreat_destination(continuation["destination"])
		if destination == Vector2i(-100_000, -100_000) and continuation["mode"] == "edge":
			return false
		if vm_interaction != null or session_interaction == null or session_interaction.to_data() != _retreat_confirmation_request(session_interaction.request_id).to_data():
			return false
		if state.combat == null or state.combat.completed or state.combat.battle_id != continuation["battleId"] or state.combat.active_actor_id() != continuation["actorId"]:
			return false
		var rules := RealmzRules.new()
		var probe: Variant = rules.combat_flow.probe_character_retreat(state.combat, state.party.characters(), continuation["actorId"]) if continuation["mode"] == "explicit" else rules.combat_flow.probe_edge_retreat(state.combat, continuation["actorId"], destination)
		return probe.allowed and not probe.forced
	if continuation.get("kind") == "age-updates":
		var age_fields: Array[String] = ["kind", "updates", "index", "resumeKind", "resumeContinuation"]
		if continuation.size() != age_fields.size() or vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.AGE_UPDATE:
			return false
		for field: String in age_fields:
			if not continuation.has(field):
				return false
		var updates: Variant = continuation["updates"]
		var age_index: Variant = continuation["index"]
		if not updates is Array or updates.is_empty() or not age_index is int or age_index < 1 or age_index > updates.size():
			return false
		for update: Variant in updates:
			if not _valid_age_update_payload(state, update):
				return false
		var current_update: Dictionary = updates[age_index - 1]
		var expected_age_request := InteractionRequest.from_payload("validation.age-update", InteractionRequest.AGE_UPDATE, current_update)
		var actual_age_body := session_interaction.body as InteractionRequest.AgeUpdateBody
		var expected_age_body: InteractionRequest.AgeUpdateBody = null if expected_age_request == null else expected_age_request.body as InteractionRequest.AgeUpdateBody
		if actual_age_body == null or not actual_age_body.same_values(expected_age_body):
			return false
		var resume_kind: Variant = continuation["resumeKind"]
		var resume_continuation: Variant = continuation["resumeContinuation"]
		if resume_kind == "completed":
			return resume_continuation is Dictionary and resume_continuation.is_empty()
		if resume_kind == "combat-monster-turns":
			return resume_continuation is Dictionary and resume_continuation.is_empty() and state.combat != null and not state.combat.completed and state.combat.pending_monster_attack != null
		if resume_kind == "post-clock":
			return resume_continuation is Dictionary and _valid_post_time_continuation(content, state, resume_continuation, vm_interaction, null)
		return resume_kind == "post-move" and resume_continuation is Dictionary and _valid_ready_post_move_continuation(content, state, resume_continuation)
	if continuation.get("kind") == "combat-death-macro":
		var death_fields: Array[String] = ["kind", "battleId", "combatantId", "programId"]
		if continuation.size() not in [death_fields.size(), death_fields.size() + 1]:
			return false
		for field: String in death_fields:
			if not continuation.has(field) or not continuation[field] is String or continuation[field].is_empty():
				return false
		if continuation.has("resetTraitorOnComplete") and not continuation["resetTraitorOnComplete"] is bool:
			return false
		if session_interaction != null or vm_interaction == null or state.combat == null or state.combat.battle_id != continuation["battleId"]:
			return false
		var death_monster := state.combat.monster_by_id(continuation["combatantId"])
		if death_monster == null or content.scenario.program_by_id(continuation["programId"]) == null:
			return false
		var queued_id := state.combat.pending_spell_death_macro_id()
		if not queued_id.is_empty():
			var definition := content.monster_by_id(death_monster.definition_id)
			return queued_id == continuation["combatantId"] and not bool(continuation.get("resetTraitorOnComplete", true)) and definition != null and continuation["programId"] == "xap:%d" % definition.death_macro
		return bool(continuation.get("resetTraitorOnComplete", true))
	if continuation.get("kind") == "combat-ally-selection":
		var ally_fields: Array[String] = ["kind", "battleId"]
		if continuation.size() != ally_fields.size() or not continuation.get("battleId") is String or continuation["battleId"].is_empty():
			return false
		return vm_interaction == null and session_interaction != null and session_interaction.kind == &"ally_selection" and state.combat != null and state.combat.completed and state.combat.battle_id == continuation["battleId"]
	if continuation.get("kind") == "combat-fumble-recovery":
		var recovery_fields: Array[String] = ["kind", "battleId"]
		if continuation.size() != recovery_fields.size() or not continuation.get("battleId") is String or continuation["battleId"].is_empty():
			return false
		if vm_interaction != null or session_interaction == null or session_interaction.kind != InteractionRequest.TREASURE_DISTRIBUTION or state.combat == null or not state.combat.completed or state.combat.battle_id != continuation["battleId"] or state.combat.fumbled_items().is_empty():
			return false
		var expected_fumble_request := InteractionRequest.from_payload("validation.fumble-recovery", InteractionRequest.TREASURE_DISTRIBUTION, RealmzRules.new().combat_flow.fumble_recovery_payload(state, content))
		var actual_fumble_body := session_interaction.body as InteractionRequest.TreasureRequestBody
		var expected_fumble_body: InteractionRequest.TreasureRequestBody = null if expected_fumble_request == null else expected_fumble_request.body as InteractionRequest.TreasureRequestBody
		return actual_fumble_body != null and actual_fumble_body.same_fumble_values(expected_fumble_body)
	if continuation.get("kind") == "combat-reward":
		if continuation.size() != 3 or not continuation.get("battleId") is String or continuation["battleId"].is_empty() or not continuation.get("runtimeContinuation") is Dictionary:
			return false
		var runtime: Dictionary = continuation["runtimeContinuation"]
		var reward := ClassicRewardState.from_data(runtime.get("state")) if runtime.size() == 2 and runtime.get("kind") == "classic-reward" else null
		if vm_interaction != null or reward == null or reward.origin != &"battle" or reward.source_id != continuation["battleId"]:
			return false
		return _valid_reward_continuation(content, state, reward, session_interaction)
	if continuation.get("kind") == "post-clock":
		return _valid_post_time_continuation(content, state, continuation, vm_interaction, session_interaction)
	var fields: Array[String] = ["kind", "mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "actionPointDestinationDepth"]
	if continuation.size() != fields.size():
		return false
	for field: String in fields:
		if not continuation.has(field):
			return false
	if continuation["kind"] != "post-move" or not continuation["mapId"] is String or not continuation["x"] is int or not continuation["y"] is int or not continuation["triggerIds"] is Array or not continuation["triggerIndex"] is int or not continuation["activeTriggerId"] is String or not continuation["randomRegionIds"] is Array or not continuation["randomRegionIndex"] is int or not continuation["activeRandomProgramId"] is String or not continuation["activeRandomRegionId"] is String or not continuation["randomBattleStage"] is String or not continuation["actionPointDestinationDepth"] is int or int(continuation["actionPointDestinationDepth"]) < 0 or int(continuation["actionPointDestinationDepth"]) > 1:
		return false
	var map := content.world.map_by_id(continuation["mapId"])
	var coordinate := Vector2i(continuation["x"], continuation["y"])
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != coordinate or continuation["triggerIds"] != _selected_placed_trigger_ids(content, cell) or continuation["randomRegionIds"] != cell.random_rect_ids():
		return false
	var random_index: int = continuation["randomRegionIndex"]
	if random_index < -1 or random_index >= continuation["randomRegionIds"].size():
		return false
	if session_interaction != null:
		if vm_interaction != null or continuation["activeTriggerId"] != "" or continuation["activeRandomProgramId"] != "" or continuation["randomBattleStage"] != "surprise-choice" or session_interaction.kind != &"yes_no":
			return false
		var active_region_id: String = continuation["activeRandomRegionId"]
		return random_index >= 0 and continuation["randomRegionIds"][random_index] == active_region_id and map.random_region_by_id(active_region_id) != null
	if vm_interaction == null or continuation["randomBattleStage"] != "" or continuation["activeRandomRegionId"] != "":
		return false
	if not continuation["activeRandomProgramId"].is_empty():
		return continuation["activeTriggerId"].is_empty() and content.scenario.program_by_id(continuation["activeRandomProgramId"]) != null
	var index: int = continuation["triggerIndex"]
	if index < 0 or index >= continuation["triggerIds"].size() or continuation["activeTriggerId"].is_empty() or continuation["triggerIds"][index] != continuation["activeTriggerId"]:
		return false
	return content.trigger_by_id(continuation["activeTriggerId"]) != null


static func _valid_suspended_scenario_owner(content: RealmzContent, state: GameState, owner: Dictionary, saved: ScenarioVmSnapshot) -> bool:
	# The full handoff shape is validated by the caller. This guard proves the
	# detached VM can resume and that its owner is an exploration continuation
	# which would ordinarily be validated beside a live VM interaction.
	if owner.get("kind") not in ["post-clock", "post-move"] or saved == null or saved.halted or saved.frames.is_empty() or saved.pending_request != null or not saved.pending_continuation.is_empty():
		return false
	var test_vm := ScenarioVm.new()
	test_vm.configure(content.scenario)
	if not test_vm.restore(saved):
		return false
	var sentinel := InteractionRequest.acknowledge("internal.suspended-scenario", "Suspended scenario validation")
	return _valid_session_continuation(content, state, owner, sentinel, null)


static func _valid_post_time_continuation(content: RealmzContent, state: GameState, continuation: Dictionary, vm_interaction: InteractionRequest, session_interaction: InteractionRequest) -> bool:
	var fields: Array[String] = ["kind", "mapId", "x", "y", "timedDay", "timedEncounterIndex", "activeTimedProgramId", "midnightRecoveryPending", "timedCheckX", "timedCheckY", "checkRandom", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "resumeKind", "directionX", "directionY"]
	if continuation.size() != fields.size():
		return false
	for field: String in fields:
		if not continuation.has(field):
			return false
	if not continuation["mapId"] is String or not continuation["x"] is int or not continuation["y"] is int or not continuation["timedDay"] is int or continuation["timedDay"] < 0 or not continuation["timedEncounterIndex"] is int or continuation["timedEncounterIndex"] < 0 or continuation["timedEncounterIndex"] > content.timed_encounters().size() or not continuation["activeTimedProgramId"] is String or not continuation["midnightRecoveryPending"] is bool or not continuation["timedCheckX"] is int or not continuation["timedCheckY"] is int or not continuation["checkRandom"] is bool or not continuation["randomRegionIds"] is Array or not continuation["randomRegionIndex"] is int or not continuation["activeRandomProgramId"] is String or not continuation["activeRandomRegionId"] is String or not continuation["randomBattleStage"] is String or not continuation["resumeKind"] is String or continuation["resumeKind"] not in ["completed", "move", "post-move"] or not continuation["directionX"] is int or not continuation["directionY"] is int:
		return false
	var map := content.world.map_by_id(continuation["mapId"])
	var coordinate := Vector2i(continuation["x"], continuation["y"])
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	var direction := Vector2i(continuation["directionX"], continuation["directionY"])
	if cell == null or state.party.map_id != map.id or state.party.coordinate != coordinate or continuation["randomRegionIds"] != cell.random_rect_ids() or continuation["randomRegionIndex"] < -1 or continuation["randomRegionIndex"] >= continuation["randomRegionIds"].size() or direction.x < -1 or direction.x > 1 or direction.y < -1 or direction.y > 1:
		return false
	if continuation["resumeKind"] in ["completed", "post-move"] and direction != Vector2i.ZERO:
		return false
	if continuation["resumeKind"] == "move" and direction == Vector2i.ZERO:
		return false
	if session_interaction != null:
		if vm_interaction != null or continuation["activeRandomProgramId"] != "" or continuation["randomBattleStage"] != "surprise-choice" or session_interaction.kind != InteractionRequest.YES_NO:
			return false
		var active_region_id: String = continuation["activeRandomRegionId"]
		var random_index: int = continuation["randomRegionIndex"]
		return random_index >= 0 and continuation["randomRegionIds"][random_index] == active_region_id and map.random_region_by_id(active_region_id) != null
	if vm_interaction != null:
		if not continuation["activeTimedProgramId"].is_empty():
			return continuation["activeRandomProgramId"].is_empty() and content.scenario.program_by_id(continuation["activeTimedProgramId"]) != null
		return continuation["randomBattleStage"] == "" and continuation["activeRandomRegionId"] == "" and not continuation["activeRandomProgramId"].is_empty() and content.scenario.program_by_id(continuation["activeRandomProgramId"]) != null
	return continuation["randomBattleStage"] == "" and continuation["activeRandomRegionId"] == "" and continuation["activeRandomProgramId"] == "" and continuation["activeTimedProgramId"] == ""


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


static func _valid_ready_post_move_continuation(content: RealmzContent, state: GameState, continuation: Dictionary) -> bool:
	var fields: Array[String] = ["kind", "mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId", "randomRegionIds", "randomRegionIndex", "activeRandomProgramId", "activeRandomRegionId", "randomBattleStage", "actionPointDestinationDepth"]
	if continuation.size() != fields.size():
		return false
	for field: String in fields:
		if not continuation.has(field):
			return false
	if continuation["kind"] != "post-move" or not continuation["mapId"] is String or not continuation["x"] is int or not continuation["y"] is int or not continuation["triggerIds"] is Array or continuation["triggerIndex"] != 0 or not continuation["activeTriggerId"] is String or not continuation["activeTriggerId"].is_empty() or not continuation["randomRegionIds"] is Array or not continuation["randomRegionIndex"] is int or not continuation["activeRandomProgramId"] is String or not continuation["activeRandomProgramId"].is_empty() or not continuation["activeRandomRegionId"] is String or not continuation["activeRandomRegionId"].is_empty() or not continuation["randomBattleStage"] is String or not continuation["randomBattleStage"].is_empty() or not continuation["actionPointDestinationDepth"] is int or int(continuation["actionPointDestinationDepth"]) < 0 or int(continuation["actionPointDestinationDepth"]) > 1:
		return false
	var map := content.world.map_by_id(continuation["mapId"])
	var coordinate := Vector2i(continuation["x"], continuation["y"])
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	return cell != null and state.party.map_id == map.id and state.party.coordinate == coordinate \
		and continuation["triggerIds"] == _selected_placed_trigger_ids(content, cell) \
		and continuation["randomRegionIds"] == cell.random_rect_ids() \
		and int(continuation["randomRegionIndex"]) == continuation["randomRegionIds"].size() - 1


static func _selected_placed_trigger_ids(content: RealmzContent, cell: MapCell) -> Array[String]:
	var selected_id := ""
	var selected_record_index := 2_147_483_647
	for trigger_id: String in cell.trigger_ids():
		var trigger := content.trigger_by_id(trigger_id)
		if trigger != null and trigger.classic_record_index < selected_record_index:
			selected_id = trigger.id
			selected_record_index = trigger.classic_record_index
	return [] if selected_id.is_empty() else [selected_id]


func _build_map_view() -> MapView:
	var map := _content.world.map_by_id(_state.party.map_id)
	var visible: Dictionary = {}
	if map.uses_los:
		for coordinate: Vector2i in map.topology.visible_cells(_state.party.coordinate, 8, _state.world, true):
			visible[coordinate] = true
	var cells: Array[MapCellView] = []
	var projection_diameter := MAP_VIEW_RADIUS * 2 + 1
	var projection_width := mini(map.topology.width, projection_diameter)
	var projection_height := mini(map.topology.height, projection_diameter)
	var first_x := clampi(_state.party.coordinate.x - MAP_VIEW_RADIUS, 0, map.topology.width - projection_width)
	var first_y := clampi(_state.party.coordinate.y - MAP_VIEW_RADIUS, 0, map.topology.height - projection_height)
	var last_x := first_x + projection_width
	var last_y := first_y + projection_height
	for y: int in range(first_y, last_y):
		for x: int in range(first_x, last_x):
			var cell := map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			cells.append(_build_cell_view(map, cell, not map.uses_los or visible.has(cell.coordinate)))
	var movement_options: Dictionary = {}
	var directions := MapTopology.land_directions() if map.level_type == &"land" else MapTopology.cardinal_directions()
	for direction: Vector2i in directions:
		var direction_name := MapTopology.direction_name(direction)
		var probe := _probe_movement(direction)
		movement_options[direction_name] = {"allowed": probe.allowed, "reason": String(probe.reason)}
	return MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, _state.party.coordinate, cells, _state.world.map_is_dark(map), _state.world.visited_coordinates(map.id), movement_options, _state.last_move_direction)


func _build_player_map_view(definition: PlayerMapDefinition) -> PlayerMapView:
	var cells: Array[MapCellView] = []
	var source_map: MapDefinition = _content.world.map_by_id(definition.map_id) if not definition.map_id.is_empty() else null
	if definition.mode in [PlayerMapDefinition.LAND_CROP, PlayerMapDefinition.DUNGEON_CROP] and source_map != null:
		var tile_count := ceili(320.0 / float(definition.icon_size))
		for y: int in range(definition.start.y, definition.start.y + tile_count):
			for x: int in range(definition.start.x, definition.start.x + tile_count):
				var cell := source_map.topology.cell_at(Vector2i(x, y))
				if cell != null:
					cells.append(_build_cell_view(source_map, cell, true))
	var show_party := false
	if source_map != null and source_map.id == _state.party.map_id and definition.mode != PlayerMapDefinition.SCROLLING_TEXT:
		var visible_tiles := 320 / definition.icon_size
		var marker_bounds := Rect2i(definition.start - Vector2i.ONE, Vector2i(visible_tiles + 1, visible_tiles + 1))
		show_party = marker_bounds.has_point(_state.party.coordinate)
	return PlayerMapView.new(definition, cells, show_party, _state.party.coordinate, true)


func _build_cell_view(map: MapDefinition, cell: MapCell, is_visible: bool) -> MapCellView:
	var feature_kinds: Array[StringName] = []
	var feature_orientations: Dictionary = {}
	var edge_kinds: Dictionary = {}
	var edge_passability: Dictionary = {}
	for direction: StringName in [&"north", &"east", &"south", &"west"]:
		var edge := cell.edge(direction)
		edge_kinds[direction] = edge.kind
		edge_passability[direction] = edge.passable
	var hidden_secret := false
	for feature: MapFeature in cell.features():
		if feature.kind == &"secret" and not _state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			hidden_secret = true
			continue
		if not feature_kinds.has(feature.kind):
			feature_kinds.append(feature.kind)
			feature_orientations[feature.kind] = feature.orientation
	var can_enter := cell.passable and not hidden_secret
	return MapCellView.new(cell.coordinate, _state.world.terrain_for(map.id, cell), cell.render_tile, cell.tileset_id, can_enter, cell.blocks_los, is_visible, _state.world.was_visited(map.id, cell.coordinate), not hidden_secret and not cell.trigger_ids().is_empty(), not cell.random_rect_ids().is_empty(), feature_kinds, feature_orientations, edge_kinds, edge_passability, cell.overlay_asset_id)


func _probe_movement(direction: Vector2i) -> WorldMovementResult:
	return _content.world.probe_movement(_state.party.map_id, _state.party.coordinate, direction, _state.world)
