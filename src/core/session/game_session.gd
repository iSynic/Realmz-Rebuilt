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


func restore(content: RealmzContent, save_envelope: SaveEnvelope) -> SessionStep:
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
	if replacement_state.combat != null:
		for item: ItemInstance in replacement_state.combat.fumbled_items():
			if content.item_by_id(item.definition_id) == null:
				return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved fumble queue references unavailable item content.")
	var replacement_rules := RealmzRules.new()
	_normalize_age_groups(replacement_state, content, replacement_rules)
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(save_envelope.scenario_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM state is invalid.")
	var replacement_continuation := save_envelope.session_continuation.duplicate(true)
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


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	if _pending_interaction() != null or _scenario_vm.is_active():
		return SessionStep.failed(_view_revision, &"interaction_pending", "Respond to the pending interaction first.")
	if intent == null:
		return SessionStep.failed(_view_revision, &"invalid_intent", "A typed player intent is required.")
	if not _state.party_setup_completed and intent.kind not in [PlayerIntent.Kind.CREATE_PARTY, PlayerIntent.Kind.BEGIN_ADVENTURE, PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, PlayerIntent.Kind.FINALIZE_CHARACTER, PlayerIntent.Kind.REMOVE_PARTY_MEMBER]:
		return SessionStep.failed(_view_revision, &"party_setup_incomplete", "Finish party setup before beginning the adventure.")
	if _state.combat != null and not _state.combat.completed and intent.kind not in [PlayerIntent.Kind.CAST_SPELL, PlayerIntent.Kind.CHOOSE_COMBAT_ACTION, PlayerIntent.Kind.COMBAT_MOVE]:
		return SessionStep.failed(_view_revision, &"battle_in_progress", "Resolve the active battle before returning to exploration.")
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			return _move(intent.direction)
		PlayerIntent.Kind.SEARCH:
			return _search()
		PlayerIntent.Kind.CAMP:
			return _camp()
		PlayerIntent.Kind.USE_ITEM:
			return _use_item(intent.target_id)
		PlayerIntent.Kind.CAST_SPELL:
			return _cast_spell(intent)
		PlayerIntent.Kind.CHOOSE_COMBAT_ACTION:
			return _combat_action(intent)
		PlayerIntent.Kind.COMBAT_MOVE:
			return _combat_move(intent)
		PlayerIntent.Kind.CREATE_PARTY:
			return _create_party(intent.party_members)
		PlayerIntent.Kind.BEGIN_ADVENTURE:
			return _begin_adventure()
		PlayerIntent.Kind.IMPORT_VAULT_CHARACTER:
			return _import_vault_character(intent)
		PlayerIntent.Kind.FINALIZE_CHARACTER:
			return _finalize_character(intent)
		PlayerIntent.Kind.REMOVE_PARTY_MEMBER:
			return _remove_party_member(intent.target_id)
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
	if _session_interaction != null:
		return _respond_session_interaction(response)
	var result := _scenario_vm.resume(response, _runtime_api)
	var events: Array[DomainEvent] = []
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if not _session_continuation.is_empty():
		if _session_continuation.get("kind") == "combat-death-macro":
			return _continue_session_death_macro(events)
		return _continue_post_move(events)
	return _finish_completed(events)


func view() -> GameView:
	if not _started:
		return GameView.new(_view_revision, false, null)
	var members: Array[CharacterView] = []
	for character: CharacterState in _state.party.characters():
		members.append(CharacterView.new(character, _content))
	var current_combat := CombatView.new(_state.combat, _state.party.characters(), _content, _rules.inventory, _rules.battlefield, _rules.combat_flow) if _state.combat != null else null
	var result := GameView.new(_view_revision, true, _pending_interaction(), _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour(), _build_map_view(), members, _state.party.fatigue, _state.party.pooled_wealth.gold, current_combat)
	result.campaign_id = _content.campaign_id
	result.rules_version = _content.rules_version
	result.party_setup_available = not _state.party_setup_completed and _pending_interaction() == null
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
	result.campaign_summary.banned_races = campaign.restrictions.banned_races.duplicate()
	result.campaign_summary.banned_castes = campaign.restrictions.banned_castes.duplicate()
	result.campaign_summary.package_hash = _content.package_hash
	result.party_summary = PartySummaryView.new()
	for character: CharacterState in _state.party.characters():
		result.party_summary.character_ids.append(character.id)
	for ally: MonsterState in _state.party.allies():
		result.party_summary.ally_ids.append(ally.id)
	result.party_summary.pooled_gold = _state.party.pooled_wealth.gold
	result.party_summary.banked_gold = _state.party.banked_wealth.gold
	result.party_summary.fatigue = _state.party.fatigue
	result.party_summary.acquired_map_ids = _state.world.acquired_map_ids()
	for race: RaceDefinition in _content.race_definitions():
		result.race_options.append(DefinitionOptionView.new(race.id, race.name, race.description, race.eligible_caste_ids))
	for caste: CasteDefinition in _content.caste_definitions():
		result.caste_options.append(DefinitionOptionView.new(caste.id, caste.name, caste.description, caste.eligible_race_ids))
	_populate_action_availability(result)
	return result


func _populate_action_availability(result: GameView) -> void:
	var blocked_by_interaction := result.pending_interaction != null
	var party_setup := result.party_setup_available
	var setup_member_count := _state.party.characters().size()
	var setup_member_limit := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var battle_active := result.combat_view != null and result.combat_view.outcome == &""
	var ordinary_reason := "Resolve the current interaction first." if blocked_by_interaction else "Complete party setup first." if party_setup else ""
	result.set_action_availability(&"move", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Movement is unavailable during battle." if battle_active else "")
	result.set_action_availability(&"search", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Search is unavailable during battle." if battle_active else "")
	result.set_action_availability(&"camp", ordinary_reason.is_empty() and not battle_active and _state.camping_allowed, ordinary_reason if not ordinary_reason.is_empty() else "Camping is unavailable during battle." if battle_active else "Camping is unavailable here." if not _state.camping_allowed else "")
	result.set_action_availability(&"use_item", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Use the battle action flow during combat." if battle_active else "")
	var cast_reason := ordinary_reason
	if cast_reason.is_empty():
		cast_reason = "Combat spell selection is not wired into the battle interaction yet." if battle_active else "Field spell casting is not implemented in the current gameplay slice."
	result.set_action_availability(&"cast_spell", false, cast_reason)
	result.set_action_availability(&"choose_combat_action", battle_active and not blocked_by_interaction, "No battle action is currently available." if not battle_active else "Resolve the current interaction first." if blocked_by_interaction else "")
	result.set_action_availability(&"create_party", party_setup and not blocked_by_interaction, "Resolve the current interaction first." if blocked_by_interaction else "Party creation is available only before beginning a campaign." if not party_setup else "")
	result.set_action_availability(&"begin_adventure", party_setup and not blocked_by_interaction and setup_member_count > 0, "Resolve the current interaction first." if blocked_by_interaction else "The adventure has already begun." if not party_setup else "Add or import at least one character first.")
	result.set_action_availability(&"import_vault_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit, "Resolve the current interaction first." if blocked_by_interaction else "Vault imports are available only during party setup." if not party_setup else "The party is full.")
	result.set_action_availability(&"finalize_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "The party is full.")
	result.set_action_availability(&"remove_party_member", party_setup and not blocked_by_interaction and setup_member_count > 0, "Resolve the current interaction first." if blocked_by_interaction else "Party members can be removed only during party setup." if not party_setup else "The party is empty.")
	for action_id: StringName in [
		&"equip_item", &"unequip_item", &"use_item_on_target",
		&"drop_item", &"identify_item", &"split_item", &"join_item", &"trade_item", &"store_item",
		&"money_action", &"service_action", &"select_spell_power", &"select_spell_target", &"combat_move",
		&"loot_assignment", &"treasure_complete", &"level_up", &"open_journal", &"open_maps",
	]:
		result.set_action_availability(action_id, false, "Not implemented in the current gameplay slice.")


func snapshot() -> SaveEnvelope:
	if not _started or (_scenario_vm.is_active() and _scenario_vm.pending_request() == null):
		return null
	var envelope := SaveEnvelope.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, _state, _rng.snapshot(), _scenario_vm.snapshot(), _scenario_action_state, _session_continuation, _session_interaction)
	return SaveEnvelope.from_data(envelope.to_data())


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _scenario_vm == null else _scenario_vm.trace()


func _camp() -> SessionStep:
	if _state.combat != null and not _state.combat.completed:
		return SessionStep.failed(_view_revision, &"camp_during_battle", "The party cannot camp during battle.")
	if not _state.camping_allowed:
		return SessionStep.failed(_view_revision, &"camping_disabled", "Camping is not allowed at this location.")
	return _finish_with_age_updates(_rules.clock.camp(_state, _content), "completed")


func _use_item(instance_id: String) -> SessionStep:
	if instance_id.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_item", "Use Item requires a stable item instance ID.")
	for character: CharacterState in _state.party.characters():
		for instance: ItemInstance in character.inventory():
			if instance.id != instance_id:
				continue
			var definition := _content.item_by_id(instance.definition_id)
			if definition == null:
				return SessionStep.failed(_view_revision, &"unknown_item", "The item definition is unavailable.")
			if not _rules.inventory.use_charge(character, instance.id, definition):
				return SessionStep.failed(_view_revision, &"item_unusable", "The item has no usable charge.")
			return _finish_completed([DomainEvent.new(&"item_used", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "remainingCharges": maxi(0, instance.charges)})])
	return SessionStep.failed(_view_revision, &"unknown_item_instance", "The party does not possess item instance '%s'." % instance_id)


func _cast_spell(intent: PlayerIntent) -> SessionStep:
	var result := _rules.combat_flow.cast_spell(_state, _content, intent.actor_id, intent.secondary_target_id, intent.target_id, intent.power_level, _rng, intent.target_coordinate, intent.rotation)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _combat_action(intent: PlayerIntent) -> SessionStep:
	if intent.action == &"retreat":
		var retreat_probe: Variant = _rules.combat_flow.probe_character_retreat(_state.combat, _state.party.characters(), intent.actor_id)
		if not retreat_probe.allowed:
			return SessionStep.failed(_view_revision, retreat_probe.reason, retreat_probe.reason_text)
		return _request_session_retreat(intent.actor_id, &"explicit", Vector2i(-100_000, -100_000))
	var result := _rules.combat_flow.submit_action(_state, _content, intent.actor_id, intent.action, intent.target_id, _rng)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	if not CharacterAgingResult.update_payloads(result.events).is_empty():
		return _finish_with_age_updates(result.events, "combat-monster-turns")
	if not _event_payload(result.events, &"monster_death_macro_requested").is_empty():
		return _start_session_death_macro(result.events)
	if result.completed:
		return _finish_direct_battle(result.events)
	return _finish_completed(result.events)


func _combat_move(intent: PlayerIntent) -> SessionStep:
	var edge_probe: Variant = _rules.combat_flow.probe_edge_retreat(_state.combat, intent.actor_id, intent.direction)
	if edge_probe.allowed:
		if not edge_probe.forced:
			return _request_session_retreat(intent.actor_id, &"edge", intent.direction)
		var forced_result := _rules.combat_flow.retreat_character(_state, _content, intent.actor_id, &"edge", intent.direction, _rng)
		return _finish_combat_result(forced_result)
	var result := _rules.combat_flow.move_character(_state, _content, intent.actor_id, intent.direction, _rng)
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


func _create_party(specs: Array[CharacterCreationSpec]) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party creation is available only during party setup.")
	var maximum_party_size := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	if specs.is_empty() or specs.size() > maximum_party_size:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "This campaign allows one through %d characters." % maximum_party_size)
	var created: Array[CharacterState] = []
	var names: Dictionary = {}
	for index: int in specs.size():
		var spec: CharacterCreationSpec = specs[index]
		var validation := _character_creation_error(spec, names)
		if not validation.is_empty():
			return SessionStep.failed(_view_revision, StringName(validation["code"]), String(validation["message"]))
		var character := _create_character_from_spec(spec, "party.character.%d" % (index + 1))
		if character == null:
			return SessionStep.failed(_view_revision, &"character_creation_failed", "Realmz rules rejected a party member.")
		names[spec.name.to_lower()] = true
		created.append(character)
	var replacement := PartyState.new(_state.party.map_id, _state.party.coordinate, created)
	_state.party = replacement
	_state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in created:
		character_ids.append(character.id)
	return _finish_completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


func _begin_adventure() -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party setup is no longer active.")
	var characters := _state.party.characters()
	if characters.is_empty():
		return SessionStep.failed(_view_revision, &"empty_party", "Add or import at least one character before beginning.")
	_state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in characters:
		character_ids.append(character.id)
	return _finish_completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


func _import_vault_character(intent: PlayerIntent) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Vault import is available only during party setup.")
	if intent.target_id.is_empty() or intent.revision_hash.is_empty() or intent.vault_state_data.is_empty():
		return SessionStep.failed(_view_revision, &"invalid_vault_import", "A validated vault character revision is required.")
	var imported := CharacterState.from_data(intent.vault_state_data)
	if imported == null or imported.id != intent.target_id:
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
	for spell_id: String in imported.known_spells():
		if _content.spell_by_id(spell_id) == null:
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character knows a spell unavailable in this campaign.")
	for current: CharacterState in current_characters:
		if current.id == imported.id or current.name.to_lower() == imported.name.to_lower():
			return SessionStep.failed(_view_revision, &"duplicate_party_member", "That vault character is already represented in the party.")
	if not _state.party.add_character(imported):
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The validated vault character could not be added to the party.")
	return _finish_completed([DomainEvent.new(&"vault_character_imported", {"characterId": imported.id, "revisionHash": intent.revision_hash, "sourceCampaignId": intent.vault_source_campaign_id})])


func _finalize_character(intent: PlayerIntent) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Character creation is available only during party setup.")
	if intent.party_members.size() != 1:
		return SessionStep.failed(_view_revision, &"invalid_character_spec", "Finalize Character requires exactly one character draft.")
	var maximum_party_size := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var current_characters := _state.party.characters()
	if current_characters.size() >= maximum_party_size:
		return SessionStep.failed(_view_revision, &"invalid_party_size", "This campaign allows no more than %d characters." % maximum_party_size)
	var names: Dictionary = {}
	for current: CharacterState in current_characters:
		names[current.name.to_lower()] = true
	var spec := intent.party_members[0]
	var validation := _character_creation_error(spec, names)
	if not validation.is_empty():
		return SessionStep.failed(_view_revision, StringName(validation["code"]), String(validation["message"]))
	var character := _create_character_from_spec(spec, _next_party_character_id())
	if character == null or not _state.party.add_character(character):
		return SessionStep.failed(_view_revision, &"character_creation_failed", "Realmz rules rejected the character draft.")
	return _finish_completed([DomainEvent.new(&"character_finalized", {"characterId": character.id})])


func _remove_party_member(character_id: String) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party members can be removed only during party setup.")
	if character_id.is_empty() or not _state.party.remove_character(character_id):
		return SessionStep.failed(_view_revision, &"unknown_party_member", "The selected character is not in the setup party.")
	_state.set_selected_character_ids([])
	return _finish_completed([DomainEvent.new(&"party_member_removed", {"characterId": character_id})])


func _character_creation_error(spec: CharacterCreationSpec, existing_names: Dictionary) -> Dictionary:
	if spec == null or spec.name.is_empty() or spec.name.length() > 24 or spec.gender not in [1, 2]:
		return {"code": &"invalid_character_spec", "message": "Every party member requires a valid name and gender."}
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
	if not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(caste.id):
		return {"code": &"incompatible_race_class", "message": "The selected race cannot use that class."}
	if not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(race.id):
		return {"code": &"incompatible_class_race", "message": "The selected class is not available to that race."}
	return {}


func _create_character_from_spec(spec: CharacterCreationSpec, character_id: String) -> CharacterState:
	var character := _rules.characters.create_character(character_id, spec.name, _content.race_by_id(spec.race_id), _content.caste_by_id(spec.caste_id), spec.gender, _rng)
	if character == null:
		return null
	character.portrait_id = spec.portrait_id
	character.combat_icon_id = spec.combat_icon_id
	return character


func _next_party_character_id() -> String:
	var character_id := _state.next_instance_id("party.character")
	while _state.party.character_by_id(character_id) != null:
		character_id = _state.next_instance_id("party.character")
	return character_id


func _search() -> SessionStep:
	_state.mark_searched(_state.party.map_id, _state.party.coordinate)
	var current_map := _content.world.map_by_id(_state.party.map_id)
	var discovered: Array[String] = []
	var first_roll: int = 0
	for cell: MapCell in current_map.topology.cells():
		if absi(cell.coordinate.x - _state.party.coordinate.x) > 1 or absi(cell.coordinate.y - _state.party.coordinate.y) > 1:
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
	if not movement.allowed:
		return _movement_blocked(movement.reason)
	var target_map := movement.target_map
	var target_coordinate := movement.target_coordinate
	var transition := movement.transition
	var probe := movement.topology_result
	var events: Array[DomainEvent] = []
	if not probe.door_id.is_empty() and not _state.world.door_is_open(probe.door_id):
		_state.world.open_door(probe.door_id)
		events.append(DomainEvent.new("door_opened", {"doorId": probe.door_id}))
	if not probe.secret_id.is_empty() and not _state.world.secret_is_discovered(probe.secret_id):
		_state.world.discover_secret(probe.secret_id)
		events.append(DomainEvent.new("secret_discovered", {"secretId": probe.secret_id, "byMovement": true}))
	var source_map_id := _state.party.map_id
	var source_coordinate := _state.party.coordinate
	_state.party.map_id = target_map.id
	_state.party.coordinate = target_coordinate
	_state.last_move_direction = direction
	_state.world.mark_visited(target_map.id, target_coordinate)
	events.append(DomainEvent.new("party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": target_coordinate.x, "y": target_coordinate.y}))
	events.append_array(_rules.clock.advance_minutes(_state, _content, probe.target_cell.movement_cost))
	if transition != null:
		events.append(DomainEvent.new("map_transitioned", {"transitionId": transition.id, "sourceMapId": source_map_id, "targetMapId": target_map.id}))
	_set_post_move_continuation(target_map, target_coordinate)
	return _finish_with_age_updates(events, "post-move", _session_continuation)


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


func _movement_blocked(reason: StringName) -> SessionStep:
	return _finish_completed([DomainEvent.new("movement_blocked", {"reason": String(reason)})])


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
	var payload := _rules.combat_flow.ally_selection_payload(_state, _content)
	if not payload.is_empty():
		var request_id := "session.ally-selection.%d" % (_view_revision + 1)
		_session_continuation = {"kind": "combat-ally-selection", "battleId": _state.combat.battle_id}
		_session_interaction = InteractionRequest.new(request_id, &"ally_selection", payload)
		return _finish_waiting(_session_interaction, events)
	return _finish_direct_battle_recovery(events)


func _finish_direct_battle_recovery(events: Array[DomainEvent]) -> SessionStep:
	var payload := _rules.combat_flow.fumble_recovery_payload(_state, _content)
	if not payload.is_empty():
		var request_id := "session.fumble-recovery.%d" % (_view_revision + 1)
		_session_continuation = {"kind": "combat-fumble-recovery", "battleId": _state.combat.battle_id}
		_session_interaction = InteractionRequest.new(request_id, InteractionRequest.TREASURE_DISTRIBUTION, payload)
		return _finish_waiting(_session_interaction, events)
	_append_session_battle_after_message(_state.combat.battle_id, events)
	return _finish_completed(events)


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
				_session_continuation.clear()
				return _finish_completed(events)
			if effective.battle_minimum != 0 and not _state.party.conditions.is_active(7):
				var good_surprise_roll := _rng.draw(100, StringName("random-region.%s.good-surprise" % region.id))
				if good_surprise_roll < region.option:
					var message := _content.message_by_id(absi(region.text_id))
					var prompt := message.text if message != null else "Take the advantage and enter battle?"
					_session_continuation["activeRandomRegionId"] = region.id
					_session_continuation["randomBattleStage"] = "surprise-choice"
					var request_id := "random-surprise:%s:%d" % [region.id, _rng.snapshot().draw_count]
					_session_interaction = InteractionRequest.new(request_id, &"yes_no", {"prompt": prompt, "yesLabel": "Enter battle", "noLabel": "Avoid battle", "regionId": region.id})
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
	if _session_continuation.get("kind") == "age-updates":
		return _respond_session_age_update(response)
	if _session_continuation.get("kind") == "combat-ally-selection":
		return _respond_session_ally_selection(response)
	if _session_continuation.get("kind") == "combat-fumble-recovery":
		return _respond_session_fumble_recovery(response)
	if _session_continuation.get("kind") == "combat-retreat-confirmation":
		return _respond_session_retreat(response)
	if response.kind != &"yes_no" or not response.payload.has("accepted") or not response.payload["accepted"] is bool:
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
	var events: Array[DomainEvent] = [DomainEvent.new(&"random_surprise_chosen", {"regionId": region.id, "accepted": response.payload["accepted"]})]
	if response.payload["accepted"]:
		return _start_random_battle(region, 1, events)
	_session_continuation["randomRegionIndex"] = int(_session_continuation["randomRegionIndex"]) - 1
	if region.only:
		_session_continuation.clear()
		return _finish_completed(events)
	var next_step := _continue_random_regions(map, events)
	if next_step != null:
		return next_step
	_session_continuation.clear()
	return _finish_completed(events)


func _respond_session_retreat(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.YES_NO or response.payload.get("accepted") is not bool:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Escape confirmation requires a yes/no response.")
	if _state.combat == null or _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId") or _state.combat.active_actor_id() != _session_continuation.get("actorId"):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting Escape confirmation is unavailable.")
	var continuation := _session_continuation.duplicate(true)
	_session_interaction = null
	_session_continuation.clear()
	if not response.payload["accepted"]:
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
	if response.kind != InteractionRequest.AGE_UPDATE or not response.payload.is_empty():
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
	if response.kind != &"ally_selection" or not response.payload.has("selectedIds"):
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Ally selection requires selectedIds.")
	if _state.combat == null or not _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId"):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for ally selection.")
	var result := _rules.combat_flow.apply_ally_selection(_state, _content, response.payload["selectedIds"])
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	_session_interaction = null
	_session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _finish_direct_battle_recovery(events)


func _respond_session_fumble_recovery(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.TREASURE_DISTRIBUTION:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Fumbled-weapon recovery requires a treasure-distribution response.")
	if _state.combat == null or not _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId"):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for fumbled-weapon recovery.")
	var result := _rules.combat_flow.apply_fumble_recovery(_state, _content, response.payload)
	if not result.ok:
		return SessionStep.failed(_view_revision, result.error_code, result.error_message)
	_session_interaction = null
	_session_continuation.clear()
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	return _finish_direct_battle_recovery(events)


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
		if session_interaction.payload != current_update:
			return false
		var resume_kind: Variant = continuation["resumeKind"]
		var resume_continuation: Variant = continuation["resumeContinuation"]
		if resume_kind == "completed":
			return resume_continuation is Dictionary and resume_continuation.is_empty()
		if resume_kind == "combat-monster-turns":
			return resume_continuation is Dictionary and resume_continuation.is_empty() and state.combat != null and not state.combat.completed and state.combat.pending_monster_attack != null
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
		return session_interaction.payload == RealmzRules.new().combat_flow.fumble_recovery_payload(state, content)
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
	var first_x := maxi(0, _state.party.coordinate.x - MAP_VIEW_RADIUS)
	var first_y := maxi(0, _state.party.coordinate.y - MAP_VIEW_RADIUS)
	var last_x := mini(map.topology.width, _state.party.coordinate.x + MAP_VIEW_RADIUS + 1)
	var last_y := mini(map.topology.height, _state.party.coordinate.y + MAP_VIEW_RADIUS + 1)
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
	return MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, _state.party.coordinate, cells, _state.world.map_is_dark(map), _state.world.visited_coordinates(map.id), movement_options)


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
