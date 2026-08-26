class_name SessionViewProjector
extends RefCounted

const MAP_VIEW_RADIUS: int = 12
const ViewDomainRevisionsScript := preload("res://src/core/session/view_domain_revisions.gd")

var _cached_map_revision: int = -1
var _cached_map_id: String = ""
var _cached_map_coordinate: Vector2i = Vector2i(-1, -1)
var _cached_map_view: MapView
var _cached_map_cells_by_coordinate: Dictionary = {}
var _cached_view: GameView


func project(context: SessionWorkflowContext, pending_interaction: InteractionRequest, revision: int, started: bool, events: Array[DomainEvent] = []) -> GameView:
	if _cached_view != null and _cached_view.revision == revision:
		return _cached_view
	if not started:
		_cached_view = GameView.new(revision, false, null)
		return _cached_view
	if _can_project_ordinary_movement(context, pending_interaction, events):
		_cached_view = _project_ordinary_movement(context, revision)
		return _cached_view
	_cached_view = _project_complete(context, pending_interaction, revision)
	return _cached_view


func _project_complete(context: SessionWorkflowContext, pending_interaction: InteractionRequest, revision: int) -> GameView:
	var content := context.content
	var state := context.state
	var rules := context.rules
	var members: Array[CharacterView] = []
	for character: CharacterState in state.party.characters():
		var member_view := CharacterView.new(character, content)
		member_view.apply_equipment(rules.inventory.combat_equipment(character, content.item_definitions()))
		members.append(member_view)
	var current_combat: CombatView
	if state.combat != null:
		var prepared := pending_interaction.transient_combat_view if pending_interaction != null and pending_interaction.kind == InteractionRequest.COMBAT else null
		if prepared != null and prepared.battle_id == state.combat.battle_id:
			current_combat = prepared
		else:
			current_combat = CombatView.new(state.combat, state.party.characters(), content, rules.inventory, rules.battlefield, rules.combat_flow, state)
	var result := GameView.new(revision, true, pending_interaction, state.party.map_id, state.party.coordinate, state.clock.day(), state.clock.hour(), state.clock.minute(), _map_view(context, revision, false, state.combat != null), members, state.party.fatigue, state.party.pooled_wealth.gold, current_combat)
	for ally: MonsterState in state.party.allies():
		result.party_allies.append(MonsterView.new(ally, content.monster_by_id(ally.definition_id), content))
	result.campaign_id = content.campaign_id
	result.rules_version = content.rules_version
	result.party_setup_available = not state.party_setup_completed
	if state.character_draft != null and state.character_draft.generated_character != null:
		result.character_draft = CharacterView.new(state.character_draft.generated_character, content)
		_populate_character_draft_spells(context, result)
	result.campaign_summary = CampaignSummaryView.new()
	result.campaign_summary.campaign_id = content.campaign_id
	var campaign := content.campaign_definition()
	result.campaign_summary.title = campaign.title if not campaign.title.is_empty() else content.campaign_id.replace("-", " ").capitalize()
	result.campaign_summary.version = campaign.version if not campaign.version.is_empty() else content.rules_version
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
	result.campaign_summary.package_hash = content.package_hash
	result.party_setup = PartySetupView.new()
	result.party_setup.difficulty = state.difficulty
	result.party_setup.monster_set = state.monster_set
	result.party_setup.available_monster_sets = content.available_monster_sets()
	for character: CharacterState in state.party.characters():
		result.party_setup.current_party_levels += character.level
	result.party_setup.experience_percent = PartySetupRules.experience_percent(campaign.recommended_party_levels, result.party_setup.current_party_levels, state.difficulty)
	result.party_summary = PartySummaryView.new()
	for character: CharacterState in state.party.characters():
		result.party_summary.character_ids.append(character.id)
	for ally: MonsterState in state.party.allies():
		result.party_summary.ally_ids.append(ally.id)
	result.party_summary.pooled_gold = state.party.pooled_wealth.gold
	result.party_summary.banked_gold = state.party.banked_wealth.gold
	result.party_summary.fatigue = state.party.fatigue
	result.party_summary.light_remaining = state.party.conditions.value(0)
	result.party_summary.has_classic_torch = not InventoryMagicServicesWorkflow.classic_torch_item(context).is_empty()
	result.party_summary.camping = state.party_camping
	result.party_summary.searching = state.party.conditions.is_active(ConditionRules.PARTY_SEARCHING)
	result.party_summary.in_boat = state.party_in_boat
	result.party_summary.acquired_map_ids = state.world.acquired_map_ids()
	if state.combat != null and _can_reuse_static_map_projections(state):
		_reuse_static_map_projections(result, _cached_view)
	else:
		_populate_movement_map_views(context, result)
	for message_id: int in state.journal_message_ids():
		var journal_message := content.message_by_id(message_id)
		if journal_message != null:
			result.journal_entries.append(JournalEntryView.new(message_id, journal_message.text))
	if result.party_setup_available:
		for race: RaceDefinition in content.race_definitions():
			result.race_options.append(DefinitionOptionView.from_race(race))
		for caste: CasteDefinition in content.caste_definitions():
			result.caste_options.append(DefinitionOptionView.from_caste(caste))
	for portrait: CharacterAppearanceDefinition in content.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT):
		result.portrait_options.append(CharacterAppearanceOptionView.new(portrait))
	for icon: CharacterAppearanceDefinition in content.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON):
		result.combat_icon_options.append(CharacterAppearanceOptionView.new(icon))
	_populate_inventory_item_actions(context, result)
	_populate_spell_actions(context, result)
	_populate_money_workspace(context, result)
	_populate_services(context, result)
	_populate_action_availability(context, result)
	result.domain_revisions = ViewDomainRevisionsScript.new(revision)
	return result


func clear() -> void:
	_cached_map_revision = -1
	_cached_map_id = ""
	_cached_map_coordinate = Vector2i(-1, -1)
	_cached_map_view = null
	_cached_map_cells_by_coordinate.clear()
	_cached_view = null


func _can_project_ordinary_movement(context: SessionWorkflowContext, pending_interaction: InteractionRequest, events: Array[DomainEvent]) -> bool:
	if _cached_view == null or pending_interaction != null or _cached_view.pending_interaction != null or _cached_view.combat_view != null or events.is_empty():
		return false
	if _cached_view.party_map_id != context.state.party.map_id:
		return false
	var moved_count := 0
	for event: DomainEvent in events:
		match event.kind:
			&"party_moved":
				if event.payload.has("source"):
					return false
				if String(event.payload.get("fromMapId", "")) != _cached_view.party_map_id or String(event.payload.get("mapId", "")) != context.state.party.map_id:
					return false
				var origin := Vector2i(int(event.payload.get("fromX", -100000)), int(event.payload.get("fromY", -100000)))
				var destination := Vector2i(int(event.payload.get("x", -100000)), int(event.payload.get("y", -100000)))
				var delta := destination - origin
				if origin != _cached_view.party_coordinate or destination != context.state.party.coordinate or delta == Vector2i.ZERO or absi(delta.x) > 1 or absi(delta.y) > 1:
					return false
				moved_count += 1
			&"time_advanced": pass
			&"sound_requested":
				if String(event.payload.get("source", "")) != "classic-map-movement" or bool(event.payload.get("waitForCompletion", true)) or event.payload.has("stopExisting"):
					return false
			&"fatigue_changed":
				if String(event.payload.get("source", "")) != "classic" or String(event.payload.get("reason", "")) != "hour-boundary" or int(event.payload.get("current", -1)) != context.state.party.fatigue:
					return false
			&"random_encounter_checked":
				if bool(event.payload.get("triggered", false)):
					return false
			_:
				return false
	return moved_count == 1


func _project_ordinary_movement(context: SessionWorkflowContext, revision: int) -> GameView:
	var state := context.state
	var result := GameView.new(revision, true, null, state.party.map_id, state.party.coordinate, state.clock.day(), state.clock.hour(), state.clock.minute(), _map_view(context, revision, true), _cached_view.party_members, state.party.fatigue, state.party.pooled_wealth.gold, null)
	result.campaign_id = _cached_view.campaign_id
	result.rules_version = _cached_view.rules_version
	result.party_setup_available = _cached_view.party_setup_available
	result.character_draft = _cached_view.character_draft
	result.character_draft_spell_options.assign(_cached_view.character_draft_spell_options)
	result.character_draft_spell_points_total = _cached_view.character_draft_spell_points_total
	result.character_draft_spell_points_remaining = _cached_view.character_draft_spell_points_remaining
	result.race_options.assign(_cached_view.race_options)
	result.caste_options.assign(_cached_view.caste_options)
	result.portrait_options.assign(_cached_view.portrait_options)
	result.combat_icon_options.assign(_cached_view.combat_icon_options)
	result.campaign_summary = _cached_view.campaign_summary
	result.party_setup = _cached_view.party_setup
	result.party_summary = _cached_view.party_summary
	result.journal_entries.assign(_cached_view.journal_entries)
	result.services.assign(_cached_view.services)
	result.money_workspace = _cached_view.money_workspace
	_populate_ordinary_movement_map_views(context, result, _cached_view)
	# The strict ordinary-movement classifier excludes every interaction,
	# overlay, service, combat, inventory, condition, and campaign-state change.
	# Reuse those already-computed commands; directional movement facts live on
	# the freshly projected MapView.
	result.action_availability = _cached_view.action_availability.duplicate()
	var revisions := ViewDomainRevisionsScript.new()
	revisions.party = _cached_view.domain_revisions.party
	revisions.setup = _cached_view.domain_revisions.setup
	revisions.exploration = revision
	revisions.inventory_magic = _cached_view.domain_revisions.inventory_magic
	revisions.services = _cached_view.domain_revisions.services
	revisions.combat = _cached_view.domain_revisions.combat
	revisions.system = revision
	result.domain_revisions = revisions
	return result


func _map_view(context: SessionWorkflowContext, revision: int, reuse_ordinary_cells: bool = false, reuse_static: bool = false) -> MapView:
	if _cached_map_view != null and _cached_map_revision == revision and _cached_map_id == context.state.party.map_id and _cached_map_coordinate == context.state.party.coordinate:
		return _cached_map_view
	if reuse_static and _cached_map_view != null and _cached_map_id == context.state.party.map_id and _cached_map_coordinate == context.state.party.coordinate:
		return _cached_map_view
	_cached_map_revision = revision
	_cached_map_id = context.state.party.map_id
	_cached_map_coordinate = context.state.party.coordinate
	_cached_map_view = _build_map_view(context, _cached_map_cells_by_coordinate if reuse_ordinary_cells else {})
	_cached_map_cells_by_coordinate.clear()
	for cell: MapCellView in _cached_map_view.cells():
		_cached_map_cells_by_coordinate[cell.coordinate] = cell
	return _cached_map_view


func _can_reuse_static_map_projections(state: GameState) -> bool:
	return _cached_view != null and _cached_view.party_map_id == state.party.map_id and _cached_view.party_coordinate == state.party.coordinate


static func _reuse_static_map_projections(result: GameView, previous: GameView) -> void:
	result.player_map_menu_entries.assign(previous.player_map_menu_entries)
	result.acquired_player_maps.assign(previous.acquired_player_maps)
	result.location_notes.assign(previous.location_notes)
	result.current_location_note = previous.current_location_note


static func _populate_movement_map_views(context: SessionWorkflowContext, result: GameView) -> void:
	var content := context.content
	var state := context.state
	for definition: PlayerMapDefinition in content.world.player_maps():
		var acquired := state.world.has_map(definition.id)
		var player_map_view := _build_player_map_view(context, definition) if acquired else PlayerMapView.new(definition, [], false, Vector2i.ZERO, false)
		result.player_map_menu_entries.append(player_map_view)
		if acquired:
			result.acquired_player_maps.append(player_map_view)
	var current_map := content.world.map_by_id(state.party.map_id)
	if current_map == null:
		return
	var current_note := state.world.location_note_at(current_map.id, state.party.coordinate)
	result.current_location_note = LocationNoteView.new(current_map.id, current_map.name, current_map.level_type, current_map.level_index, state.party.coordinate, current_note.text if current_note != null else "", current_note.darkness_value if current_note != null else _current_location_note_darkness(context, current_map), current_note.record_ordinal if current_note != null else -1, true)
	for note: LocationNoteState in state.world.location_notes_for_kind(current_map.level_type):
		var note_map := content.world.map_by_id(note.map_id)
		if note_map != null:
			result.location_notes.append(LocationNoteView.new(note.map_id, note_map.name, note_map.level_type, note_map.level_index, note.coordinate, note.text, note.darkness_value, note.record_ordinal, note.map_id == state.party.map_id and note.coordinate == state.party.coordinate))


static func _populate_ordinary_movement_map_views(context: SessionWorkflowContext, result: GameView, previous: GameView) -> void:
	var state := context.state
	for previous_map: PlayerMapView in previous.player_map_menu_entries:
		var definition := context.content.world.player_map_by_id(previous_map.id)
		if definition == null:
			continue
		var source_map := context.content.world.map_by_id(definition.map_id) if not definition.map_id.is_empty() else null
		var show_party := _player_map_shows_party(definition, source_map, state.party.map_id, state.party.coordinate)
		var refreshed := PlayerMapView.new(definition, previous_map.cells, show_party, state.party.coordinate, previous_map.acquired)
		result.player_map_menu_entries.append(refreshed)
		if refreshed.acquired:
			result.acquired_player_maps.append(refreshed)
	var current_map := context.content.world.map_by_id(state.party.map_id)
	if current_map == null:
		return
	var current_note := state.world.location_note_at(current_map.id, state.party.coordinate)
	result.current_location_note = LocationNoteView.new(current_map.id, current_map.name, current_map.level_type, current_map.level_index, state.party.coordinate, current_note.text if current_note != null else "", current_note.darkness_value if current_note != null else _current_location_note_darkness(context, current_map), current_note.record_ordinal if current_note != null else -1, true)
	for previous_note: LocationNoteView in previous.location_notes:
		result.location_notes.append(LocationNoteView.new(previous_note.map_id, previous_note.map_name, previous_note.level_type, previous_note.level_index, previous_note.coordinate, previous_note.text, previous_note.darkness_value, previous_note.record_ordinal, previous_note.map_id == state.party.map_id and previous_note.coordinate == state.party.coordinate))


static func _populate_services(context: SessionWorkflowContext, result: GameView) -> void:
	if not context.state.active_shop_id.is_empty():
		var shop := context.content.shop_by_id(context.state.active_shop_id)
		if shop != null:
			var shop_view := ServiceView.new()
			shop_view.service_id = shop.id
			shop_view.service_kind = &"shop"
			shop_view.title = "Shop %d" % shop.classic_id
			shop_view.actions = [&"enter"]
			result.services.append(shop_view)
	if context.state.temple_available:
		var temple_view := ServiceView.new()
		temple_view.service_id = "realmz.service.temple"
		temple_view.service_kind = &"temple"
		temple_view.title = "Temple"
		temple_view.actions = [&"enter"]
		result.services.append(temple_view)
	if context.state.bank_available:
		var bank_view := ServiceView.new()
		bank_view.service_id = "realmz.service.bank"
		bank_view.service_kind = &"bank"
		bank_view.title = "Bank"
		bank_view.actions = [&"enter"]
		result.services.append(bank_view)


static func _populate_money_workspace(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	if not state.party_setup_completed:
		return
	var workspace := MoneyWorkspaceView.new()
	workspace.pooled_gold = state.party.pooled_wealth.gold
	workspace.pooled_gems = state.party.pooled_wealth.gems
	workspace.pooled_jewelry = state.party.pooled_wealth.jewelry
	workspace.banked_gold = state.party.banked_wealth.gold
	workspace.banked_gems = state.party.banked_wealth.gems
	workspace.banked_jewelry = state.party.banked_wealth.jewelry
	var pool_probe := context.rules.economy.pool_probe(state.party)
	workspace.pool = ActionAvailabilityView.new(&"money_action", pool_probe.allowed, pool_probe.reason)
	var share_probe := context.rules.economy.share_probe(state.party)
	workspace.share = ActionAvailabilityView.new(&"money_action", share_probe.allowed, share_probe.reason)
	for character: CharacterState in state.party.characters():
		var character_view := MoneyCharacterView.new(character)
		for denomination: StringName in [&"gold", &"gems", &"jewelry"]:
			var kind := _money_kind(denomination)
			var amount := EconomyRules.classic_transfer_increment(kind as WealthState.Kind)
			var to_pool := context.rules.economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, false)
			var to_character := context.rules.economy.transfer_probe(state.party, character, kind as WealthState.Kind, amount, true)
			character_view.transfers.append(MoneyTransferView.new(denomination, amount, ActionAvailabilityView.new(&"money_action", to_pool.allowed, to_pool.reason), ActionAvailabilityView.new(&"money_action", to_character.allowed, to_character.reason)))
		workspace.characters.append(character_view)
	result.money_workspace = workspace


static func _populate_action_availability(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	var content := context.content
	var rules := context.rules
	var blocked_by_interaction := result.pending_interaction != null
	var party_setup := result.party_setup_available
	var setup_member_count := state.party.characters().size()
	var setup_member_limit := clampi(content.campaign_definition().restrictions.maximum_party_size, 1, 6)
	var draft_active := state.character_draft != null and state.character_draft.generated_character != null
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	var ordinary_reason := "Resolve the current interaction first." if blocked_by_interaction else "Complete party setup first." if party_setup else ""
	var field_item_available := false
	for member: CharacterView in result.party_members:
		if member.items.any(func(item: ItemView) -> bool: return item.actions != null and item.actions.use.enabled):
			field_item_available = true
			break
	var combat_item_available := battle_active and not rules.combat_flow.character_item_spell_options(state, content, result.combat_view.active_actor_id).is_empty()
	result.set_action_availability(&"move", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Movement is unavailable during battle." if battle_active else "")
	var search_reason := ordinary_reason if not ordinary_reason.is_empty() else "Search is unavailable during battle." if battle_active else "Search is replaced by scroll scribing while camped." if state.party_camping else ""
	result.set_action_availability(&"search", search_reason.is_empty(), search_reason)
	result.set_action_availability(&"toggle_search", search_reason.is_empty(), search_reason)
	var area_search_reason := search_reason if not search_reason.is_empty() else "The party is too fatigued to continue Area Search." if state.party.fatigue > 134 else ""
	result.set_action_availability(&"area_search", area_search_reason.is_empty(), area_search_reason)
	var torch_probe := InventoryMagicServicesWorkflow.classic_torch_probe(context)
	result.set_action_availability(&"use_torch", ordinary_reason.is_empty() and not battle_active and torch_probe.allowed, ordinary_reason if not ordinary_reason.is_empty() else "Torches are unavailable during battle." if battle_active else torch_probe.reason)
	var encounter_reason := ordinary_reason if not ordinary_reason.is_empty() else "Encounters are unavailable during battle." if battle_active else "Break camp before using Encounter." if state.party_camping else ""
	result.set_action_availability(&"contextual_encounter", encounter_reason.is_empty(), encounter_reason)
	result.set_action_availability(&"camp", ordinary_reason.is_empty() and not battle_active and (state.camping_allowed or state.party_camping), ordinary_reason if not ordinary_reason.is_empty() else "Camping is unavailable during battle." if battle_active else "Camping is unavailable here." if not state.camping_allowed and not state.party_camping else "")
	result.set_action_availability(&"rest", ordinary_reason.is_empty() and not battle_active and state.party_camping, ordinary_reason if not ordinary_reason.is_empty() else "Rest is unavailable during battle." if battle_active else "Make camp before resting.")
	var heal_reason := ordinary_reason if not ordinary_reason.is_empty() else "Heal is unavailable during battle." if battle_active else "The party is too fatigued to continue Heal." if state.party.fatigue > 134 else ""
	result.set_action_availability(&"heal", heal_reason.is_empty(), heal_reason)
	result.set_action_availability(&"use_item", not blocked_by_interaction and (combat_item_available or not battle_active and field_item_available), "Resolve the current interaction first." if blocked_by_interaction else rules.combat_flow.character_item_spell_unavailable_reason(state, content, result.combat_view.active_actor_id) if battle_active else "No carried item has a supported Classic field use.")
	result.set_action_availability(&"use_item_on_target", not blocked_by_interaction and combat_item_available, "Resolve the current interaction first." if blocked_by_interaction else rules.combat_flow.character_item_spell_unavailable_reason(state, content, result.combat_view.active_actor_id) if battle_active else "Targeted combat item use is available only during battle.")
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
	var combat_spell_available := battle_active and not rules.combat_flow.character_spell_options(state, content, result.combat_view.active_actor_id).is_empty()
	var cast_enabled := not blocked_by_interaction and (combat_spell_available or not battle_active and field_spell_available)
	var cast_reason := ordinary_reason
	if cast_reason.is_empty() and battle_active:
		cast_reason = rules.combat_flow.character_spell_unavailable_reason(state, content, result.combat_view.active_actor_id)
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
	var appearance_available := not party_setup and not blocked_by_interaction and not battle_active and setup_member_count > 0 and content.has_character_appearance_catalog()
	var appearance_reason := "Resolve the current interaction first." if blocked_by_interaction else "Begin the adventure before changing appearance." if party_setup else "Appearance changes are unavailable during battle." if battle_active else "No party member is available." if setup_member_count == 0 else "This package does not contain the complete Classic portrait and combat-icon catalogs." if not content.has_character_appearance_catalog() else ""
	result.set_action_availability(&"change_character_appearance", appearance_available, appearance_reason)
	for action_id: StringName in [&"equip_item", &"unequip_item", &"drop_item", &"trade_item"]:
		result.set_action_availability(action_id, ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"split_item", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
	result.set_action_availability(&"join_item", ordinary_reason.is_empty() and not battle_active, ordinary_reason if not ordinary_reason.is_empty() else "Inventory changes are unavailable during battle." if battle_active else "")
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


static func _populate_spell_actions(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	var content := context.content
	var rules := context.rules
	var blocked_reason := "Resolve the current interaction first." if result.pending_interaction != null else "Complete party setup first." if result.party_setup_available else ""
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	for member_view: CharacterView in result.party_members:
		var character := state.party.character_by_id(member_view.id)
		for spell_view: SpellView in member_view.spells:
			var spell := content.spell_by_id(spell_view.id)
			if not blocked_reason.is_empty():
				spell_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				continue
			if battle_active:
				var combat_reason := ""
				var combat_enabled := false
				for power: int in range(1, 8):
					var combat_probe := rules.combat_flow.probe_character_spell_choice(state, content, character.id, spell_view.id, power)
					if combat_probe.allowed:
						combat_enabled = true
					elif combat_reason.is_empty():
						combat_reason = combat_probe.reason_text
					if spell != null and spell.cost < 0:
						break
				spell_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", combat_enabled, combat_reason)
				spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", false, "Use the tactical spell action during battle.")
				spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", false, "Scroll scribing is unavailable during battle.")
				continue
			spell_view.combat_cast = ActionAvailabilityView.new(&"cast_spell", false, "Combat casting requires an active battle.")
			var first_reason := ""
			for power: int in range(1, 8):
				var probe := _field_spell_probe(context, character, spell, power)
				if probe.allowed:
					spell_view.power_levels.append(power)
				elif first_reason.is_empty():
					first_reason = probe.reason
				if spell != null and spell.cost < 0:
					break
			spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", not spell_view.power_levels.is_empty(), first_reason)
			var make_reason := ""
			for power: int in range(1, 8):
				var make_probe := _make_scroll_probe(context, character, spell, power)
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
				scroll_view.discard = ActionAvailabilityView.new(&"cast_spell", false, blocked_reason)
				continue
			if battle_active:
				var combat_scroll := character.scroll_at(scroll_view.slot_index)
				var combat_scroll_spell := content.spell_by_id(combat_scroll.spell_id) if combat_scroll != null and not combat_scroll.is_empty() else null
				var combat_target_id := character.id if combat_scroll_spell != null and combat_scroll_spell.target_type == 5 else ""
				var combat_probe := rules.combat_flow.probe_character_scroll_cast(state, content, character.id, scroll_view.slot_index, combat_target_id)
				scroll_view.use = ActionAvailabilityView.new(&"cast_spell", combat_probe.allowed, combat_probe.reason_text)
				continue
			var scroll := character.scroll_at(scroll_view.slot_index)
			var scroll_spell := content.spell_by_id(scroll.spell_id) if scroll != null and not scroll.is_empty() else null
			var scroll_probe := _scroll_use_probe(context, character, scroll_view.slot_index, scroll_spell)
			scroll_view.use = ActionAvailabilityView.new(&"cast_spell", scroll_probe.allowed, scroll_probe.reason)
			var discard_probe := _scroll_discard_probe(context, character, scroll_view.slot_index, scroll_spell)
			scroll_view.discard = ActionAvailabilityView.new(&"cast_spell", discard_probe.allowed, discard_probe.reason)
		for fast_spell: FastSpellBindingView in member_view.fast_spells:
			if fast_spell.spell_id.is_empty():
				continue
			var bound_spell := content.spell_by_id(fast_spell.spell_id)
			if bound_spell == null or not character.known_spells().has(fast_spell.spell_id):
				fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", false, "The stored spell is unavailable to this character.")
				continue
			if battle_active:
				var option_available := false
				for option: CombatSpellOptionView in rules.combat_flow.character_spell_options(state, content, character.id):
					if option.spell_id == bound_spell.id and option.power == fast_spell.power:
						option_available = true
						break
				fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", option_available, "No legal target or casting action is currently available." if not option_available else "")
			else:
				var field_probe := _field_spell_probe(context, character, bound_spell, fast_spell.power)
				fast_spell.activation = ActionAvailabilityView.new(&"cast_spell", field_probe.allowed, field_probe.reason)


static func _populate_inventory_item_actions(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	var content := context.content
	var rules := context.rules
	var context_reason := ""
	if result.pending_interaction != null:
		context_reason = "Resolve the current interaction first."
	elif result.party_setup_available:
		context_reason = "Begin the adventure before changing carried equipment."
	elif result.combat_view != null and result.combat_view.outcome == &"active":
		context_reason = "Use the battle action flow during combat."
	var party := state.party.characters()
	var definitions := content.item_definitions()
	for member_view: CharacterView in result.party_members:
		var character := state.party.character_by_id(member_view.id)
		if character == null:
			continue
		var race := content.race_by_id(character.race_id)
		var caste := content.caste_by_id(character.caste_id)
		var identify_cast := _inventory_identify_cast(context, character)
		for item_view: ItemView in member_view.items:
			var instance := _item_instance(character, item_view.instance_id)
			var definition: ItemDefinition = null if instance == null else content.item_by_id(instance.definition_id)
			var actions := InventoryItemActionsView.new()
			if not context_reason.is_empty():
				actions.block_all(context_reason)
				item_view.actions = actions
				continue
			var equip_probe := rules.inventory.classic_equip_probe(character, instance, definition, race, caste, party, definitions)
			var unequip_probe := rules.inventory.classic_unequip_probe(character, instance, definition, definitions)
			var drop_probe := rules.inventory.classic_drop_probe(character, instance)
			var split_probe := rules.inventory.classic_split_probe(character, instance, definition)
			var join_probe := rules.inventory.classic_join_probe(character, instance, definition)
			var use_probe := InventoryMagicServicesWorkflow.field_spell_item_probe(context, character, instance, definition, content.spell_by_classic_id(definition.special_2) if definition != null else null)
			actions.equip = ActionAvailabilityView.new(&"equip_item", equip_probe.allowed, equip_probe.reason)
			actions.unequip = ActionAvailabilityView.new(&"unequip_item", unequip_probe.allowed, unequip_probe.reason)
			actions.drop = ActionAvailabilityView.new(&"drop_item", drop_probe.allowed, drop_probe.reason)
			actions.split = ActionAvailabilityView.new(&"split_item", split_probe.allowed, split_probe.reason)
			actions.join = ActionAvailabilityView.new(&"join_item", join_probe.allowed, join_probe.reason)
			actions.use = ActionAvailabilityView.new(&"use_item", use_probe.allowed, use_probe.reason)
			if identify_cast.is_empty():
				actions.identify = ActionAvailabilityView.new(&"identify_item", false, "No living party member knows Identify Objects with 25 spell points.")
			else:
				actions.identify_caster_id = String(identify_cast[0])
				actions.identify_spell_id = String(identify_cast[1])
				actions.identify = ActionAvailabilityView.new(&"identify_item", true)
			for destination: CharacterState in party:
				if destination == character:
					continue
				var trade_probe := InventoryMagicServicesWorkflow.trade_item_probe(context, character, destination, instance, definition)
				actions.trade_targets.append(ItemTransferTargetView.new(destination.id, destination.name, trade_probe.allowed, trade_probe.reason, destination.carried_load, destination.carried_load + item_view.weight, destination.maximum_load))
			var enabled_targets := actions.trade_targets.filter(func(target: ItemTransferTargetView) -> bool: return target.enabled)
			var trade_reason := "Choose another party member." if actions.trade_targets.is_empty() else actions.trade_targets[0].reason if enabled_targets.is_empty() else ""
			actions.trade = ActionAvailabilityView.new(&"trade_item", not enabled_targets.is_empty(), trade_reason)
			item_view.actions = actions


static func _inventory_identify_cast(context: SessionWorkflowContext, target: CharacterState) -> Array[String]:
	for caster: CharacterState in context.state.party.characters():
		var spells: Array[SpellDefinition] = []
		for spell_id: String in caster.known_spells():
			var spell := context.content.spell_by_id(spell_id)
			if spell != null and absi(spell.special) == 48:
				spells.append(spell)
		spells.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
		for spell: SpellDefinition in spells:
			if InventoryMagicServicesWorkflow.inventory_identify_probe(context, target.id, caster.id, spell.id).allowed:
				return [caster.id, spell.id]
	return []


static func _populate_character_draft_spells(context: SessionWorkflowContext, result: GameView) -> void:
	var character := context.state.character_draft.generated_character
	var caste := context.content.caste_by_id(character.caste_id)
	result.character_draft_spell_points_total = context.rules.characters.spell_selection_total(character, caste)
	var spent := 0
	for spell: SpellDefinition in _character_spell_candidates(context, character, caste):
		result.character_draft_spell_options.append(CharacterSpellOptionView.new(spell, context.rules.characters.spell_selection_cost(spell), character.known_spells().has(spell.id)))
	for spell_id: String in character.known_spells():
		spent += context.rules.characters.spell_selection_cost(context.content.spell_by_id(spell_id))
	result.character_draft_spell_points_remaining = maxi(0, result.character_draft_spell_points_total - spent)


static func _character_spell_candidates(context: SessionWorkflowContext, character: CharacterState, caste: CasteDefinition) -> Array[SpellDefinition]:
	var result: Array[SpellDefinition] = []
	if character == null or caste == null or character.spellcaster_type < 1:
		return result
	var maximum_level := context.rules.characters.maximum_spell_selection_level(caste)
	for spell: SpellDefinition in context.content.spell_definitions():
		if int(spell.classic_id / 1000) != character.spellcaster_type:
			continue
		var tier := spell.classic_tier()
		var slot := spell.classic_slot()
		if tier >= 0 and tier < maximum_level and slot >= 1 and slot <= 12:
			result.append(spell)
	result.sort_custom(func(left: SpellDefinition, right: SpellDefinition) -> bool: return left.classic_id < right.classic_id)
	return result


static func _current_location_note_darkness(context: SessionWorkflowContext, map: MapDefinition) -> int:
	if map == null or map.level_type == &"dungeon" or not context.state.world.map_is_dark(map):
		return 0
	return clampi(int(context.state.party.conditions.value(0) / 30) + 1, 1, 255)


static func _make_scroll_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if not context.state.party_camping:
		return InventoryActionProbe.block("Enter camp before making a scroll.")
	if character.current_health < 1 or character.spellcaster_type < 1:
		return InventoryActionProbe.block("The selected character cannot scribe scrolls.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip a scroll case before making a scroll.")
	if _first_empty_scroll_slot(character) < 0:
		return InventoryActionProbe.block("The scroll case already contains five spells.")
	if _parchment_instance(context, character) == null:
		return InventoryActionProbe.block("The character has no parchment.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected scroll power.")
	if character.spell_points < absi(spell.cost * power * 2):
		return InventoryActionProbe.block("Scribing requires twice the spell's normal spell-point cost.")
	return InventoryActionProbe.permit()


static func _scroll_use_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if character == null or slot_index < 0 or slot_index >= 5:
		return InventoryActionProbe.block("The scroll slot is unavailable.")
	var scroll := character.scroll_at(slot_index)
	if scroll == null or scroll.is_empty() or spell == null or spell.id != scroll.spell_id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip the scroll case before using its spells.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This scroll cannot be used outside battle; Classic offers to discard it.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This scroll has an invalid Classic field target type.")
	if spell.target_type in [3, 7, 9] and not context.state.party.allies().is_empty():
		return InventoryActionProbe.block("This scroll also targets allied creatures; that Classic field branch is not implemented yet.")
	if not _field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This scroll's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


static func _scroll_discard_probe(context: SessionWorkflowContext, character: CharacterState, slot_index: int, spell: SpellDefinition) -> InventoryActionProbe:
	if spell == null or spell.in_camp:
		return InventoryActionProbe.block("This scroll has a valid field use.")
	var scroll := character.scroll_at(slot_index) if character != null else null
	if scroll == null or scroll.is_empty() or scroll.spell_id != spell.id or scroll.power < 1 or scroll.power > 7:
		return InventoryActionProbe.block("This scroll slot is empty or invalid.")
	if character.current_health < 1 or character.conditions.is_active(ConditionRules.ANIMATED):
		return InventoryActionProbe.block("The selected character cannot use a scroll.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip the scroll case before managing its spells.")
	return InventoryActionProbe.permit()


static func _field_spell_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if context.state.character_spellcasting_blocked:
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
	if spell.target_type in [3, 7, 9] and not context.state.party.allies().is_empty():
		return InventoryActionProbe.block("This spell also targets allied creatures; that Classic field branch is not implemented yet.")
	if not _field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This spell's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


static func _field_spell_effect_supported(spell: SpellDefinition) -> bool:
	return ClassicSpellCapabilityCatalog.field_character_disposition(spell) == ClassicSpellCapabilityCatalog.DISPOSITION_EXECUTABLE


static func _has_equipped_scroll_case(context: SessionWorkflowContext, character: CharacterState) -> bool:
	if character == null:
		return false
	for instance: ItemInstance in character.inventory():
		var definition := context.content.item_by_id(instance.definition_id)
		if instance.equipped and definition != null and absi(definition.item_type) == 13:
			return true
	return false


static func _parchment_instance(context: SessionWorkflowContext, character: CharacterState) -> ItemInstance:
	if character == null:
		return null
	for instance: ItemInstance in character.inventory():
		var definition := context.content.item_by_id(instance.definition_id)
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


static func _item_instance(character: CharacterState, instance_id: String) -> ItemInstance:
	if character == null or instance_id.is_empty():
		return null
	for instance: ItemInstance in character.inventory():
		if instance.id == instance_id:
			return instance
	return null


static func _money_kind(value: StringName) -> int:
	match value:
		&"gold": return WealthState.Kind.GOLD
		&"gems": return WealthState.Kind.GEMS
		&"jewelry": return WealthState.Kind.JEWELRY
	return -1


static func _build_map_view(context: SessionWorkflowContext, reusable_cells: Dictionary = {}) -> MapView:
	var content := context.content
	var state := context.state
	var map := content.world.map_by_id(state.party.map_id)
	var visible: Dictionary = {}
	if map.uses_los:
		for coordinate: Vector2i in map.topology.visible_cells(state.party.coordinate, 8, state.world, true):
			visible[coordinate] = true
	var cells: Array[MapCellView] = []
	var projection_diameter := MAP_VIEW_RADIUS * 2 + 1
	var projection_width := mini(map.topology.width, projection_diameter)
	var projection_height := mini(map.topology.height, projection_diameter)
	var first_x := clampi(state.party.coordinate.x - MAP_VIEW_RADIUS, 0, map.topology.width - projection_width)
	var first_y := clampi(state.party.coordinate.y - MAP_VIEW_RADIUS, 0, map.topology.height - projection_height)
	var last_x := first_x + projection_width
	var last_y := first_y + projection_height
	for y: int in range(first_y, last_y):
		for x: int in range(first_x, last_x):
			var cell := map.topology.cell_at(Vector2i(x, y))
			if cell == null:
				continue
			# An ordinary land step changes only the destination's visited flag. Keep
			# overlapping detached cells and build the entering strip plus destination.
			# LOS maps must rebuild because moving changes visibility across the window.
			var reusable := reusable_cells.get(cell.coordinate) as MapCellView
			if not map.uses_los and cell.coordinate != state.party.coordinate and reusable != null:
				cells.append(reusable)
			else:
				cells.append(_build_cell_view(context, map, cell, not map.uses_los or visible.has(cell.coordinate)))
	var movement_options: Dictionary = {}
	var directions := MapTopology.land_directions() if map.level_type == &"land" else MapTopology.cardinal_directions()
	for direction: Vector2i in directions:
		var direction_name := MapTopology.direction_name(direction)
		var probe := _probe_movement(context, direction)
		movement_options[direction_name] = {"allowed": probe.allowed, "reason": String(probe.reason)}
	return MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, state.party.coordinate, cells, state.world.map_is_dark(map), state.world.visited_coordinates(map.id), movement_options, state.last_move_direction, map.landlook, state.dungeon_heading, state.dungeon_multiview, state.party.conditions.is_active(ConditionRules.PARTY_WIZARDS_EYE), map.base_scale, state.xy_display_hidden, state.compass_enabled)


static func _build_player_map_view(context: SessionWorkflowContext, definition: PlayerMapDefinition) -> PlayerMapView:
	var cells: Array[MapCellView] = []
	var source_map: MapDefinition = context.content.world.map_by_id(definition.map_id) if not definition.map_id.is_empty() else null
	if definition.mode in [PlayerMapDefinition.LAND_CROP, PlayerMapDefinition.DUNGEON_CROP] and source_map != null:
		var tile_count := ceili(320.0 / float(definition.icon_size))
		for y: int in range(definition.start.y, definition.start.y + tile_count):
			for x: int in range(definition.start.x, definition.start.x + tile_count):
				var cell := source_map.topology.cell_at(Vector2i(x, y))
				if cell != null:
					cells.append(_build_cell_view(context, source_map, cell, true))
	var show_party := _player_map_shows_party(definition, source_map, context.state.party.map_id, context.state.party.coordinate)
	return PlayerMapView.new(definition, cells, show_party, context.state.party.coordinate, true)


static func _player_map_shows_party(definition: PlayerMapDefinition, source_map: MapDefinition, party_map_id: String, party_coordinate: Vector2i) -> bool:
	if source_map == null or source_map.id != party_map_id or definition.mode == PlayerMapDefinition.SCROLLING_TEXT:
		return false
	var visible_tiles := 320 / definition.icon_size
	var marker_bounds := Rect2i(definition.start - Vector2i.ONE, Vector2i(visible_tiles + 1, visible_tiles + 1))
	return marker_bounds.has_point(party_coordinate)


static func _build_cell_view(context: SessionWorkflowContext, map: MapDefinition, cell: MapCell, is_visible: bool) -> MapCellView:
	cell = map.topology.effective_cell_at(cell.coordinate, context.state.world)
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
		if feature.kind == &"secret" and feature.orientation.is_empty() and not context.state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
			hidden_secret = true
			continue
		if not feature_kinds.has(feature.kind):
			feature_kinds.append(feature.kind)
			feature_orientations[feature.kind] = feature.orientation
	var can_enter := cell.passable and not hidden_secret
	return MapCellView.new(cell.coordinate, context.state.world.terrain_for(map.id, cell), cell.render_tile, cell.tileset_id, can_enter, cell.blocks_los, is_visible, context.state.world.was_visited(map.id, cell.coordinate), not hidden_secret and not cell.trigger_ids().is_empty(), not cell.random_rect_ids().is_empty(), feature_kinds, feature_orientations, edge_kinds, edge_passability, cell.overlay_asset_id)


static func _probe_movement(context: SessionWorkflowContext, direction: Vector2i) -> WorldMovementResult:
	return context.content.world.probe_movement(context.state.party.map_id, context.state.party.coordinate, direction, context.state.world, context.state.party_in_boat)
