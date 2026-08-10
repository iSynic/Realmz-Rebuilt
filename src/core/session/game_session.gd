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
		for monster: MonsterState in replacement_state.combat.monsters():
			for item_id: String in monster.loot_item_ids():
				if not item_id.is_empty() and content.item_by_id(item_id) == null:
					return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved monster loot references unavailable item content.")
	var replacement_rules := RealmzRules.new()
	_normalize_age_groups(replacement_state, content, replacement_rules)
	if not _party_inventory_is_valid(content, replacement_state, replacement_rules):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved party inventory or carried load is invalid for this package.")
	if not _shop_state_is_valid(content, replacement_state):
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved shop state references unavailable package content.")
	if not _character_draft_is_valid(content, replacement_state, replacement_rules):
		return SessionStep.failed(_view_revision, &"invalid_character_draft", "The saved character-creation draft is invalid for this campaign.")
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(save_envelope.scenario_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM state is invalid.")
	if not _valid_vm_reward_continuation(content, replacement_state, replacement_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM reward continuation is invalid.")
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
	if not _state.party_setup_completed and intent.kind not in [PlayerIntent.Kind.CREATE_PARTY, PlayerIntent.Kind.BEGIN_ADVENTURE, PlayerIntent.Kind.IMPORT_VAULT_CHARACTER, PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT, PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT, PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS, PlayerIntent.Kind.FINALIZE_CHARACTER, PlayerIntent.Kind.REMOVE_PARTY_MEMBER]:
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
		PlayerIntent.Kind.GENERATE_CHARACTER_DRAFT:
			return _generate_character_draft(intent)
		PlayerIntent.Kind.CANCEL_CHARACTER_DRAFT:
			return _cancel_character_draft()
		PlayerIntent.Kind.SET_CHARACTER_DRAFT_SPELLS:
			return _set_character_draft_spells(intent.selected_ids)
		PlayerIntent.Kind.FINALIZE_CHARACTER:
			return _finalize_character(intent)
		PlayerIntent.Kind.REMOVE_PARTY_MEMBER:
			return _remove_party_member(intent.target_id)
		PlayerIntent.Kind.EQUIP_ITEM:
			return _equip_item(intent)
		PlayerIntent.Kind.UNEQUIP_ITEM:
			return _unequip_item(intent)
		PlayerIntent.Kind.DROP_ITEM:
			return _request_drop_item(intent)
		PlayerIntent.Kind.TRADE_ITEM:
			return _trade_item(intent)
		PlayerIntent.Kind.SERVICE_ACTION:
			return _service_action(intent)
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
		var member_view := CharacterView.new(character, _content)
		member_view.apply_equipment(_rules.inventory.combat_equipment(character, _content.item_definitions()))
		members.append(member_view)
	var current_combat := CombatView.new(_state.combat, _state.party.characters(), _content, _rules.inventory, _rules.battlefield, _rules.combat_flow) if _state.combat != null else null
	var result := GameView.new(_view_revision, true, _pending_interaction(), _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour(), _build_map_view(), members, _state.party.fatigue, _state.party.pooled_wealth.gold, current_combat)
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


func _populate_action_availability(result: GameView) -> void:
	var blocked_by_interaction := result.pending_interaction != null
	var party_setup := result.party_setup_available
	var setup_member_count := _state.party.characters().size()
	var setup_member_limit := clampi(_content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var draft_active := _state.character_draft != null and _state.character_draft.generated_character != null
	var battle_active := result.combat_view != null and result.combat_view.outcome == &""
	var ordinary_reason := "Resolve the current interaction first." if blocked_by_interaction else "Complete party setup first." if party_setup else ""
	result.set_action_availability(&"move", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Movement is unavailable during battle." if battle_active else "")
	result.set_action_availability(&"search", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Search is unavailable during battle." if battle_active else "")
	result.set_action_availability(&"camp", ordinary_reason.is_empty() and not battle_active and _state.camping_allowed, ordinary_reason if not ordinary_reason.is_empty() else "Camping is unavailable during battle." if battle_active else "Camping is unavailable here." if not _state.camping_allowed else "")
	result.set_action_availability(&"use_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Item effects require their source-backed use workflow before charges can be consumed.")
	var cast_reason := ordinary_reason
	if cast_reason.is_empty():
		cast_reason = "Combat spell selection is not wired into the battle interaction yet." if battle_active else "Field spell casting is not implemented in the current gameplay slice."
	result.set_action_availability(&"cast_spell", false, cast_reason)
	result.set_action_availability(&"choose_combat_action", battle_active and not blocked_by_interaction, "No battle action is currently available." if not battle_active else "Resolve the current interaction first." if blocked_by_interaction else "")
	result.set_action_availability(&"create_party", party_setup and not blocked_by_interaction, "Resolve the current interaction first." if blocked_by_interaction else "Party creation is available only before beginning a campaign." if not party_setup else "")
	result.set_action_availability(&"begin_adventure", party_setup and not blocked_by_interaction and setup_member_count > 0 and not draft_active, "Resolve the current interaction first." if blocked_by_interaction else "The adventure has already begun." if not party_setup else "Finish or cancel the character currently being created." if draft_active else "Add or import at least one character first.")
	result.set_action_availability(&"import_vault_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit and not draft_active, "Resolve the current interaction first." if blocked_by_interaction else "Vault imports are available only during party setup." if not party_setup else "Finish or cancel the character currently being created." if draft_active else "The party is full.")
	result.set_action_availability(&"generate_character_draft", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "The party is full.")
	result.set_action_availability(&"cancel_character_draft", party_setup and not blocked_by_interaction and draft_active, "There is no generated character to cancel." if not draft_active else "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup.")
	result.set_action_availability(&"set_character_draft_spells", party_setup and not blocked_by_interaction and draft_active, "Generate the character before choosing spells." if not draft_active else "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup.")
	result.set_action_availability(&"finalize_character", party_setup and not blocked_by_interaction and setup_member_count < setup_member_limit and draft_active, "Resolve the current interaction first." if blocked_by_interaction else "Character creation is available only during party setup." if not party_setup else "Generate and review the character first." if not draft_active else "The party is full.")
	result.set_action_availability(&"remove_party_member", party_setup and not blocked_by_interaction and setup_member_count > 0, "Resolve the current interaction first." if blocked_by_interaction else "Party members can be removed only during party setup." if not party_setup else "The party is empty.")
	for action_id: StringName in [&"equip_item", &"unequip_item", &"drop_item", &"trade_item"]:
		result.set_action_availability(action_id, ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"identify_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Identification is available only from a shop, temple, or the Identify spell.")
	result.set_action_availability(&"split_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Classic split-stack load behavior requires a fidelity decision.")
	result.set_action_availability(&"join_item", false, ordinary_reason if not ordinary_reason.is_empty() else "Classic join-stack load behavior requires a fidelity decision.")
	result.set_action_availability(&"store_item", false, "Classic has no ordinary player-stash workflow; opcode 36 equipment escrow remains scenario-owned.")
	result.set_action_availability(&"service_action", ordinary_reason.is_empty() and not battle_active and not result.services.is_empty(), ordinary_reason if not ordinary_reason.is_empty() else "Services are unavailable during battle." if battle_active else "No shop, temple, or bank is available at this location.")
	for action_id: StringName in [
		&"use_item_on_target",
		&"money_action", &"select_spell_power", &"select_spell_target", &"combat_move",
		&"open_journal", &"open_maps",
	]:
		result.set_action_availability(action_id, false, "Not implemented in the current gameplay slice.")


func _populate_inventory_item_actions(result: GameView) -> void:
	var context_reason := ""
	if result.pending_interaction != null:
		context_reason = "Resolve the current interaction first."
	elif result.party_setup_available:
		context_reason = "Begin the adventure before changing carried equipment."
	elif result.combat_view != null and result.combat_view.outcome == &"":
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
			actions.equip = ActionAvailabilityView.new(&"equip_item", equip_probe.allowed, equip_probe.reason)
			actions.unequip = ActionAvailabilityView.new(&"unequip_item", unequip_probe.allowed, unequip_probe.reason)
			actions.drop = ActionAvailabilityView.new(&"drop_item", drop_probe.allowed, drop_probe.reason)
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
			return SessionStep.failed(_view_revision, &"item_effect_unimplemented", "The Classic effect for '%s' is not implemented, so no charge was consumed." % (definition.name if instance.identified else definition.unidentified_name))
	return SessionStep.failed(_view_revision, &"unknown_item_instance", "The party does not possess item instance '%s'." % instance_id)


func _equip_item(intent: PlayerIntent) -> SessionStep:
	var character := _state.party.character_by_id(intent.actor_id)
	var instance := _item_instance(character, intent.target_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _rules.inventory.equip_classic(character, instance, definition, _content.race_by_id(character.race_id), _content.caste_by_id(character.caste_id), _state.party.characters(), _content.item_definitions())
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_equip", probe.reason)
	return _finish_completed([DomainEvent.new(&"item_equipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id, "identified": instance.identified})])


func _unequip_item(intent: PlayerIntent) -> SessionStep:
	var character := _state.party.character_by_id(intent.actor_id)
	var instance := _item_instance(character, intent.target_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if character == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"unknown_item_instance", "The selected character does not carry that item instance.")
	var probe := _rules.inventory.unequip_classic(character, instance, definition, _content.item_definitions())
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_unequip", probe.reason)
	return _finish_completed([DomainEvent.new(&"item_unequipped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})])


func _trade_item(intent: PlayerIntent) -> SessionStep:
	var source := _state.party.character_by_id(intent.actor_id)
	var destination := _state.party.character_by_id(intent.secondary_target_id)
	var instance := _item_instance(source, intent.target_id)
	var definition: ItemDefinition = null if instance == null else _content.item_by_id(instance.definition_id)
	if source == null or destination == null or instance == null or definition == null:
		return SessionStep.failed(_view_revision, &"invalid_item_trade", "Trade requires a carried item and two current party members.")
	var probe := _rules.inventory.trade_classic(source, destination, instance, definition)
	if not probe.allowed:
		return SessionStep.failed(_view_revision, &"item_cannot_trade", probe.reason)
	return _finish_completed([DomainEvent.new(&"item_traded", {"fromCharacterId": source.id, "toCharacterId": destination.id, "instanceId": instance.id, "itemId": definition.id})])


func _request_drop_item(intent: PlayerIntent) -> SessionStep:
	var character := _state.party.character_by_id(intent.actor_id)
	var instance := _item_instance(character, intent.target_id)
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
	var result := _rules.combat_flow.cast_spell(_state, _content, intent.actor_id, intent.secondary_target_id, intent.target_id, intent.power_level, _rng, intent.target_coordinate, intent.rotation, intent.selected_ids)
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
	_state.party_setup_completed = true
	var character_ids: Array[String] = []
	for character: CharacterState in characters:
		character_ids.append(character.id)
	return _finish_completed([DomainEvent.new(&"party_created", {"characterIds": character_ids})])


func _import_vault_character(intent: PlayerIntent) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Vault import is available only during party setup.")
	if _state.character_draft != null:
		return SessionStep.failed(_view_revision, &"character_draft_active", "Finish or cancel the character currently being created before importing from the vault.")
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
	var imported_load := _rules.inventory.calculated_load(imported, _content.item_definitions())
	if imported_load < 0 or imported_load > imported.maximum_load:
		return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character's carried wealth and items exceed this character's load limit.")
	# Vault revisions preserve item identity and equipment state, but load is derived
	# again from the target package so stale local revisions cannot bypass capacity.
	imported.carried_load = imported_load
	for spell_id: String in imported.known_spells():
		if _content.spell_by_id(spell_id) == null:
			return SessionStep.failed(_view_revision, &"vault_character_ineligible", "The vault character knows a spell unavailable in this campaign.")
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
	return _finish_completed([DomainEvent.new(&"vault_character_imported", {"characterId": imported.id, "revisionHash": intent.revision_hash, "sourceCampaignId": intent.vault_source_campaign_id})])


func _generate_character_draft(intent: PlayerIntent) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Character creation is available only during party setup.")
	if intent.party_members.size() != 1:
		return SessionStep.failed(_view_revision, &"invalid_character_spec", "Generate Character requires exactly one typed specification.")
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
	if not _materialize_initial_inventory(character, _content.caste_by_id(character.caste_id), party_context) or not _state.party.add_character(character):
		return _finish_failed(&"character_creation_failed", "Realmz rules rejected the generated character.", events)
	_state.character_draft = null
	events.append(DomainEvent.new(&"character_finalized", {"characterId": character.id}))
	var request_id := "character-vault:%s:%d" % [character.id, _view_revision + 1]
	_session_continuation = {"kind": "character-vault-publication", "characterId": character.id}
	_session_interaction = _character_vault_confirmation_request(request_id, character.name)
	events.append(DomainEvent.new(&"character_vault_confirmation_requested", {"characterId": character.id}))
	return _finish_waiting(_session_interaction, events)


func _remove_party_member(character_id: String) -> SessionStep:
	if _state.party_setup_completed or _pending_interaction() != null:
		return SessionStep.failed(_view_revision, &"party_setup_closed", "Party members can be removed only during party setup.")
	if character_id.is_empty() or not _state.party.remove_character(character_id):
		return SessionStep.failed(_view_revision, &"unknown_party_member", "The selected character is not in the setup party.")
	_state.set_selected_character_ids([])
	return _finish_completed([DomainEvent.new(&"party_member_removed", {"characterId": character_id})])


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
	return _begin_direct_battle_reward(events)


func _begin_direct_battle_reward(events: Array[DomainEvent]) -> SessionStep:
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
	if _session_continuation.get("kind") == "service-interaction":
		return _respond_runtime_service(response)
	if _session_continuation.get("kind") == "drop-item-confirmation":
		return _respond_drop_item(response)
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


func _service_action(intent: PlayerIntent) -> SessionStep:
	if intent.action != &"enter":
		return SessionStep.failed(_view_revision, &"unknown_service_action", "Only entering an available service is implemented through this intent.")
	var request_id := "service:%s:%d" % [intent.target_id, _view_revision]
	var operation: ScenarioRuntimeOperationResult
	if intent.target_id == "realmz.service.temple":
		operation = _runtime_api.request_available_temple(request_id)
	elif intent.target_id == "realmz.service.bank":
		operation = _runtime_api.request_available_bank(request_id)
	elif intent.target_id == _state.active_shop_id:
		operation = _runtime_api.request_available_shop(request_id)
	else:
		return SessionStep.failed(_view_revision, &"service_unavailable", "The selected service is not available at this location.")
	return _begin_runtime_service(intent.target_id, operation)


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
	if response.kind != InteractionRequest.YES_NO or response.payload.get("accepted") is not bool:
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
	if not response.payload["accepted"]:
		return _finish_completed([DomainEvent.new(&"item_drop_declined", {"characterId": character.id, "instanceId": instance.id})])
	var removed := _rules.inventory.remove_item(character, instance.id, definition)
	if removed == null:
		return SessionStep.failed(_view_revision, &"item_drop_failed", "The item could not be removed from inventory.")
	return _finish_completed([DomainEvent.new(&"item_dropped", {"characterId": character.id, "instanceId": instance.id, "itemId": definition.id})])


func _respond_character_spell_confirmation(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.YES_NO or response.payload.get("accepted") is not bool:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Starting-spell confirmation requires a yes/no response.")
	var character_id := String(_session_continuation.get("characterId", ""))
	if _state.character_draft == null or _state.character_draft.generated_character == null or _state.character_draft.generated_character.id != character_id:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting starting-spell confirmation is unavailable.")
	_session_interaction = null
	_session_continuation.clear()
	if not response.payload["accepted"]:
		return _finish_completed([DomainEvent.new(&"character_spell_confirmation_declined", {"characterId": character_id})])
	return _commit_character_draft([DomainEvent.new(&"character_spell_confirmation_accepted", {"characterId": character_id})])


func _respond_character_vault_publication(response: InteractionResponse) -> SessionStep:
	if response.kind != InteractionRequest.YES_NO or response.payload.get("accepted") is not bool:
		return SessionStep.failed(_view_revision, &"invalid_interaction_response", "Character-vault publication requires a yes/no response.")
	var character_id := String(_session_continuation.get("characterId", ""))
	var character := _state.party.character_by_id(character_id)
	if _state.party_setup_completed or character == null:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The character awaiting vault publication is unavailable.")
	_session_interaction = null
	_session_continuation.clear()
	if response.payload["accepted"]:
		return _finish_completed([DomainEvent.new(&"character_publication_requested", {"characterId": character_id})])
	return _finish_completed([DomainEvent.new(&"character_publication_declined", {"characterId": character_id})])


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


func _respond_session_battle_reward(response: InteractionResponse) -> SessionStep:
	if _state.combat == null or not _state.combat.completed or _state.combat.battle_id != _session_continuation.get("battleId"):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The completed battle is unavailable for reward distribution.")
	var runtime_continuation: Variant = _session_continuation.get("runtimeContinuation")
	if not runtime_continuation is Dictionary:
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The battle reward continuation is unavailable.")
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
				return service_id == "realmz.service.temple" and state.temple_available and int(runtime.get("costPercent", -100_000)) == state.temple_cost_percent and bool(runtime.get("bankAvailable", false)) == state.bank_available and selected_temple_character is String and state.party.character_by_id(String(selected_temple_character)) != null and session_interaction.kind == InteractionRequest.TEMPLE and session_interaction.payload.get("selectedCharacterId") == selected_temple_character
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
	if continuation.get("kind") == "combat-reward":
		if continuation.size() != 3 or not continuation.get("battleId") is String or continuation["battleId"].is_empty() or not continuation.get("runtimeContinuation") is Dictionary:
			return false
		var runtime: Dictionary = continuation["runtimeContinuation"]
		var reward := ClassicRewardState.from_data(runtime.get("state")) if runtime.size() == 2 and runtime.get("kind") == "classic-reward" else null
		if vm_interaction != null or reward == null or reward.origin != &"battle" or reward.source_id != continuation["battleId"]:
			return false
		return _valid_reward_continuation(content, state, reward, session_interaction)
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


static func _valid_vm_reward_continuation(content: RealmzContent, state: GameState, vm: ScenarioVm) -> bool:
	var snapshot := vm.snapshot()
	if snapshot.pending_continuation.is_empty():
		return true
	var runtime: Variant = snapshot.pending_continuation.get("runtime")
	if not runtime is Dictionary or runtime.get("kind") != "classic-reward":
		return true
	var reward := ClassicRewardState.from_data(runtime.get("state"))
	return reward != null and _valid_reward_continuation(content, state, reward, vm.pending_request())


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
		if request.kind != InteractionRequest.TREASURE_DISTRIBUTION:
			return false
		var expected_mode := "completion-confirmation" if reward.completion_pending else "ordinary"
		if request.payload.get("mode") != expected_mode:
			return false
		var pending := reward.first_item()
		var request_item: Variant = request.payload.get("item")
		return request_item == null if pending == null else request_item is Dictionary and request_item.get("instanceId") == pending.id
	if reward.phase == ClassicRewardState.LEVEL_PHASE:
		return not reward.pending_level_result.is_empty() and request.kind == InteractionRequest.LEVEL_UP and request.payload.get("mode") == "result" and request.payload.get("characterId") == reward.pending_level_result.get("characterId")
	if reward.phase == ClassicRewardState.SPELL_PHASE:
		var spell_ids := reward.spell_character_ids()
		return reward.spell_index < spell_ids.size() and request.kind == InteractionRequest.LEVEL_UP and request.payload.get("mode") == "spell-selection" and request.payload.get("characterId") == spell_ids[reward.spell_index]
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
