## Assembles and incrementally caches the detached game view for a committed session revision.
class_name SessionViewProjector
extends RefCounted

const DEFAULT_MAP_VIEW_SIZE: Vector2i = Vector2i(25, 25)
const ProjectionPolicy := preload("res://src/playthrough/session/session_view_projection_policy.gd")
const ActionViewProjector := preload("res://src/playthrough/session/session_action_view_projector.gd")
const OrdinaryProjectionPolicy := preload("res://src/playthrough/session/session_ordinary_projection_policy.gd")

var _cached_map_revision: int = -1
var _cached_map_id: String = ""
var _cached_map_coordinate: Vector2i = Vector2i(-1, -1)
var _cached_map_view: MapView
var _cached_visited_membership: Dictionary = {}
var _cached_seen_membership: Dictionary = {}
var _cached_visible_membership: Dictionary = {}
var _cached_view: GameView
var _prepared_visibility_map_id: String = ""
var _prepared_visibility_coordinate: Vector2i = Vector2i(-1, -1)
var _prepared_visible_coordinates: Dictionary = {}
var _visibility_membership_cache: Dictionary = {}
var _map_projection_size: Vector2i = DEFAULT_MAP_VIEW_SIZE
var _equipment_by_character_id: Dictionary = {}
var _map_window_cache: Dictionary = {}
var _map_cell_cache: Dictionary = {}


func project(context: SessionWorkflowContext, pending_interaction: InteractionRequest, revision: int, started: bool, events: Array[DomainEvent] = []) -> GameView:
	if _cached_view != null and _cached_view.revision == revision:
		return _cached_view
	if not started:
		_cached_view = GameView.new(revision, false, null)
		return _cached_view
	if OrdinaryProjectionPolicy.can_reuse(_cached_view, context, pending_interaction, events):
		_cached_view = _project_ordinary_movement(context, revision, events)
		return _cached_view
	_cached_view = _project_complete(context, pending_interaction, revision)
	return _cached_view


func _project_complete(context: SessionWorkflowContext, pending_interaction: InteractionRequest, revision: int) -> GameView:
	_equipment_by_character_id.clear()
	_map_window_cache.clear()
	var state := context.state
	var members := _complete_party_members(context)
	var current_combat := _complete_combat_view(context, pending_interaction)
	var result := GameView.new(revision, true, pending_interaction, state.party.map_id, state.party.coordinate, state.clock.day(), state.clock.hour(), state.clock.minute(), _map_view(context, revision, false, state.combat != null), members, state.party.fatigue, state.party.pooled_wealth.gold, current_combat)
	_populate_complete_identity(context, result)
	_populate_complete_campaign(context, result)
	_populate_complete_party(context, result)
	_populate_complete_collections(context, result)
	_populate_complete_actions(context, result)
	result.domain_revisions = ViewDomainRevisions.new(revision)
	return result


func _complete_party_members(context: SessionWorkflowContext) -> Array[CharacterView]:
	var members: Array[CharacterView] = []
	var item_definitions := context.content.items.definitions()
	for character: CharacterState in context.state.party.characters():
		var member_view := CharacterView.new(character, context.content)
		var equipment := context.rules.equipment.combat_equipment(character, item_definitions)
		_equipment_by_character_id[character.id] = equipment
		member_view.apply_equipment(equipment)
		members.append(member_view)
	return members


static func _complete_combat_view(context: SessionWorkflowContext, pending_interaction: InteractionRequest) -> CombatView:
	var state := context.state
	var current_combat: CombatView
	if state.combat != null:
		var prepared := pending_interaction.transient_combat_view if pending_interaction != null and pending_interaction.kind == InteractionRequest.COMBAT else null
		if prepared != null and prepared.battle_id == state.combat.battle_id:
			current_combat = prepared
		else:
			current_combat = CombatView.new(state.combat, state.party.characters(), context.content, context.rules.equipment, context.rules.battlefield, context.rules.combat_flow, state)
	return current_combat


static func _populate_complete_identity(context: SessionWorkflowContext, result: GameView) -> void:
	result.campaign_id = context.content.campaign_id
	result.rules_version = context.content.rules_version
	result.character_spellcasting_blocked = context.state.character_spellcasting_blocked
	result.party_setup_available = not context.state.party_setup_completed


static func _populate_complete_campaign(context: SessionWorkflowContext, result: GameView) -> void:
	var content := context.content
	var campaign := content.campaign
	result.campaign_summary = CampaignSummaryView.new()
	result.campaign_summary.campaign_id = content.campaign_id
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
	result.campaign_summary.maximum_party_levels = 0
	result.campaign_summary.guidance_authored = campaign.guidance_authored
	result.campaign_summary.banned_races = campaign.restrictions.banned_races.duplicate()
	result.campaign_summary.banned_castes = campaign.restrictions.banned_castes.duplicate()
	result.campaign_summary.package_hash = content.package_hash


static func _populate_complete_party(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	if state.character_draft != null and state.character_draft.generated_character != null:
		result.character_draft = CharacterView.new(state.character_draft.generated_character, context.content)
		ActionViewProjector.populate_character_draft_spells(context, result)
	result.party_setup = PartySetupView.new()
	result.party_setup.difficulty = state.difficulty
	result.party_setup.monster_set = state.monster_set
	result.party_setup.available_monster_sets = context.content.combat.available_monster_sets()
	for character: CharacterState in state.party.characters():
		result.party_setup.current_party_levels += character.level
	result.party_setup.experience_percent = PartySetupRules.experience_percent(context.content.campaign.recommended_party_levels, result.party_setup.current_party_levels, state.difficulty)
	result.party_summary = PartySummaryView.new()
	for character: CharacterState in state.party.characters():
		result.party_summary.character_ids.append(character.id)
	for ally: MonsterState in state.party.allies():
		result.party_summary.ally_ids.append(ally.id)
	result.party_summary.pooled_gold = state.party.pooled_wealth.gold
	result.party_summary.banked_gold = state.party.banked_wealth.gold
	result.party_summary.fatigue = state.party.fatigue
	result.party_summary.light_remaining = state.party.conditions.value(0)
	result.party_summary.condition_values = state.party.conditions.values()
	result.party_summary.has_classic_torch = not FieldItemWorkflow.classic_torch_item(context).is_empty()
	result.party_summary.camping = state.party_camping
	result.party_summary.searching = state.party.conditions.is_active(ConditionRules.PARTY_SEARCHING)
	result.party_summary.in_boat = state.party_in_boat
	result.party_summary.acquired_map_ids = state.world.exploration.acquired_map_ids()


func _populate_complete_collections(context: SessionWorkflowContext, result: GameView) -> void:
	var state := context.state
	var content := context.content
	for ally: MonsterState in state.party.allies():
		result.party_allies.append(MonsterView.new(ally, content.combat.monster_by_id(ally.definition_id), content))
	for definition: MonsterDefinition in content.combat.bestiary_definitions_for_set(state.monster_set):
		result.bestiary_entries.append(MonsterCatalogEntryView.new(definition, content))
	if state.combat != null and _can_reuse_static_map_projections(state):
		_reuse_static_map_projections(result, _cached_view)
	else:
		_populate_movement_map_views(context, result)
	for message_id: int in state.scenario_progress.journal_message_ids():
		var journal_message := content.scenario_records.message_by_id(message_id)
		if journal_message != null:
			result.journal_entries.append(JournalEntryView.new(message_id, journal_message.text))
	if result.party_setup_available:
		for race: RaceDefinition in content.characters.race_definitions():
			result.race_options.append(DefinitionOptionView.from_race(race))
		for caste: CasteDefinition in content.characters.caste_definitions():
			result.caste_options.append(DefinitionOptionView.from_caste(caste))
	for portrait: CharacterAppearanceDefinition in content.characters.appearance_definitions(CharacterAppearanceDefinition.PORTRAIT):
		result.portrait_options.append(CharacterAppearanceOptionView.new(portrait))
	for icon: CharacterAppearanceDefinition in content.characters.appearance_definitions(CharacterAppearanceDefinition.COMBAT_ICON):
		result.combat_icon_options.append(CharacterAppearanceOptionView.new(icon))


static func _populate_complete_actions(context: SessionWorkflowContext, result: GameView) -> void:
	ActionViewProjector.populate_inventory_item_actions(context, result)
	ActionViewProjector.populate_spell_actions(context, result)
	ActionViewProjector.populate_money_screen(context, result)
	ActionViewProjector.populate_services(context, result)
	ActionViewProjector.populate_action_availability(context, result)


func clear() -> void:
	_cached_map_revision = -1
	_cached_map_id = ""
	_cached_map_coordinate = Vector2i(-1, -1)
	_cached_map_view = null
	_cached_visited_membership.clear()
	_cached_seen_membership.clear()
	_cached_visible_membership.clear()
	_cached_view = null
	_prepared_visibility_map_id = ""
	_prepared_visibility_coordinate = Vector2i(-1, -1)
	_prepared_visible_coordinates.clear()
	_visibility_membership_cache.clear()
	_equipment_by_character_id.clear()
	_map_window_cache.clear()
	_map_cell_cache.clear()


func set_map_projection_size(requested_size: Vector2i) -> bool:
	var normalized := Vector2i(maxi(requested_size.x, 1), maxi(requested_size.y, 1))
	if normalized == _map_projection_size:
		return false
	_map_projection_size = normalized
	clear()
	return true


func record_visibility(map_id: String, coordinate: Vector2i, visible_coordinates: Array[Vector2i], topology_revision: int = 0, wizard_eye: bool = false) -> void:
	_prepared_visibility_map_id = map_id
	_prepared_visibility_coordinate = coordinate
	var cache_key := "%s:%d:%d,%d:%d" % [map_id, topology_revision, coordinate.x, coordinate.y, int(wizard_eye)]
	if _visibility_membership_cache.has(cache_key):
		_prepared_visible_coordinates = _visibility_membership_cache[cache_key]
		return
	var membership: Dictionary = {}
	for visible_coordinate: Vector2i in visible_coordinates:
		membership[visible_coordinate] = true
	if _visibility_membership_cache.size() >= 512:
		_visibility_membership_cache.clear()
	_visibility_membership_cache[cache_key] = membership
	_prepared_visible_coordinates = membership


func _project_ordinary_movement(context: SessionWorkflowContext, revision: int, events: Array[DomainEvent]) -> GameView:
	var projection_started := Time.get_ticks_usec()
	var state := context.state
	# Every hour mutates positive character/ally conditions even when no expiry
	# event is published. Rebuild only the party-owned detached records at that
	# boundary while retaining the expensive immutable campaign catalogs.
	var refresh_party := events.any(func(event: DomainEvent) -> bool:
		return event.kind == &"fatigue_changed" and String(event.payload.get("source", "")) == "classic" and String(event.payload.get("reason", "")) == "hour-boundary"
	)
	var magic_character_ids := _ordinary_magic_character_ids(events)
	var magic_affordability_ids := _ordinary_affordability_character_ids(context, events)
	var structural_magic_refresh := _ordinary_magic_requires_structural_refresh(events)
	var inventory_refresh := _ordinary_inventory_refresh(context, events)
	var status_character_ids: Dictionary = {}
	var members := _ordinary_party_members(context, refresh_party, magic_affordability_ids, structural_magic_refresh, inventory_refresh, status_character_ids)
	var party_done := Time.get_ticks_usec()
	var projected_map := _map_view(context, revision, true)
	var map_done := Time.get_ticks_usec()
	var result := _ordinary_game_view(context, revision, projected_map, members)
	if refresh_party:
		for ally: MonsterState in state.party.allies():
			result.party_allies.append(MonsterView.new(ally, context.content.combat.monster_by_id(ally.definition_id), context.content))
	else:
		result.party_allies.assign(_cached_view.party_allies)
	result.bestiary_entries = _cached_view.bestiary_entries
	result.journal_entries = _cached_view.journal_entries
	result.services = _cached_view.services
	result.money_workspace = _cached_view.money_workspace
	_populate_ordinary_movement_map_views(context, result, _cached_view)
	var shell_done := Time.get_ticks_usec()
	# The strict ordinary-movement classifier excludes every interaction,
	# overlay, service, combat, inventory, condition, and campaign-state change.
	# Reuse those already-computed commands; directional movement facts live on
	# the freshly projected MapView.
	if inventory_refresh:
		ActionViewProjector.populate_inventory_item_actions(context, result)
	var inventory_done := Time.get_ticks_usec()
	if not magic_affordability_ids.is_empty():
		if structural_magic_refresh:
			ActionViewProjector.populate_spell_actions(context, result, magic_affordability_ids)
		else:
			ActionViewProjector.populate_spell_affordability(context, result, magic_affordability_ids)
	var magic_done := Time.get_ticks_usec()
	if refresh_party:
		_populate_ordinary_action_availability(result, _cached_view, inventory_refresh, not magic_affordability_ids.is_empty())
	else:
		result.action_availability = _cached_view.action_availability.duplicate()
	result.domain_revisions = _ordinary_domain_revisions(revision, refresh_party, inventory_refresh, magic_character_ids)
	result.change_set = _ordinary_change_set(refresh_party, inventory_refresh, magic_character_ids, status_character_ids)
	result.projection_timings_usec = {
		"partyStatus": party_done - projection_started,
		"mapWindow": map_done - party_done,
		"explorationShell": shell_done - map_done,
		"inventory": inventory_done - shell_done,
		"magic": magic_done - inventory_done,
		"finalize": Time.get_ticks_usec() - magic_done,
	}
	return result


func _ordinary_party_members(context: SessionWorkflowContext, refresh_party: bool, magic_affordability_ids: Dictionary, structural_magic_refresh: bool, inventory_refresh: bool, status_character_ids: Dictionary) -> Array[CharacterView]:
	var members: Array[CharacterView] = []
	if not refresh_party:
		members.assign(_cached_view.party_members)
		return members
	var characters := context.state.party.characters()
	for character_index: int in characters.size():
		var character: CharacterState = characters[character_index]
		var previous_member := _cached_view.party_members[character_index] if character_index < _cached_view.party_members.size() and _cached_view.party_members[character_index].id == character.id else _character_view_by_id(_cached_view.party_members, character.id)
		var magic_changed := magic_affordability_ids.has(character.id)
		if not magic_changed and not inventory_refresh and not _character_status_changed(character, previous_member):
			members.append(previous_member)
			continue
		status_character_ids[character.id] = true
		var equipment := _equipment_by_character_id.get(character.id) as CharacterCombatEquipment
		if equipment == null:
			equipment = context.rules.equipment.combat_equipment(character, context.content.items.definitions())
			_equipment_by_character_id[character.id] = equipment
		members.append(CharacterView.new(character, context.content, previous_member, true, magic_changed) if inventory_refresh else CharacterView.refreshed_status(character, context.content, previous_member, equipment, magic_changed, structural_magic_refresh))
		if inventory_refresh:
			members[-1].apply_equipment(equipment)
	return members


func _ordinary_domain_revisions(revision: int, refresh_party: bool, inventory_refresh: bool, magic_character_ids: Dictionary) -> ViewDomainRevisions:
	var revisions := ViewDomainRevisions.new()
	revisions.party_roster = _cached_view.domain_revisions.party_roster
	revisions.party_status = revision if refresh_party else _cached_view.domain_revisions.party_status
	revisions.setup = _cached_view.domain_revisions.setup
	revisions.exploration = revision
	revisions.inventory = revision if inventory_refresh else _cached_view.domain_revisions.inventory
	revisions.magic = revision if not magic_character_ids.is_empty() else _cached_view.domain_revisions.magic
	revisions.services = _cached_view.domain_revisions.services
	revisions.combat = _cached_view.domain_revisions.combat
	revisions.system = revision
	revisions.synchronize_legacy_aggregates()
	return revisions


static func _ordinary_change_set(refresh_party: bool, inventory_refresh: bool, magic_character_ids: Dictionary, status_character_ids: Dictionary) -> ViewChangeSet:
	var changes := ViewChangeSet.new()
	changes.mark_domain(ViewChangeSet.EXPLORATION)
	if refresh_party:
		changes.mark_domain(ViewChangeSet.PARTY_STATUS)
		for character_id: String in status_character_ids:
			changes.mark_character(character_id)
	if inventory_refresh:
		changes.mark_domain(ViewChangeSet.INVENTORY)
	if not magic_character_ids.is_empty():
		changes.mark_domain(ViewChangeSet.MAGIC)
	changes.mark_domain(ViewChangeSet.SYSTEM)
	for character_id: String in magic_character_ids:
		changes.mark_character(character_id)
	return changes


func _ordinary_game_view(context: SessionWorkflowContext, revision: int, projected_map: MapView, members: Array[CharacterView]) -> GameView:
	var state := context.state
	var result := GameView.new(revision, true, null, state.party.map_id, state.party.coordinate, state.clock.day(), state.clock.hour(), state.clock.minute(), projected_map, members, state.party.fatigue, state.party.pooled_wealth.gold, null)
	result.campaign_id = _cached_view.campaign_id
	result.rules_version = _cached_view.rules_version
	result.character_spellcasting_blocked = _cached_view.character_spellcasting_blocked
	result.party_setup_available = _cached_view.party_setup_available
	result.character_draft = _cached_view.character_draft
	result.character_draft_spell_options = _cached_view.character_draft_spell_options
	result.character_draft_spell_points_total = _cached_view.character_draft_spell_points_total
	result.character_draft_spell_points_remaining = _cached_view.character_draft_spell_points_remaining
	result.race_options = _cached_view.race_options
	result.caste_options = _cached_view.caste_options
	result.portrait_options = _cached_view.portrait_options
	result.combat_icon_options = _cached_view.combat_icon_options
	result.campaign_summary = _cached_view.campaign_summary
	result.party_setup = _cached_view.party_setup
	result.party_summary = _ordinary_party_summary(context, _cached_view.party_summary)
	return result


static func _character_status_changed(character: CharacterState, previous: CharacterView) -> bool:
	return previous == null \
		or character.current_health != previous.current_health \
		or character.maximum_health != previous.maximum_health \
		or character.spell_points != previous.spell_points \
		or character.maximum_spell_points != previous.maximum_spell_points \
		or character.age_days != previous.age_days \
		or character.conditions.values() != previous.condition_values


static func _character_view_by_id(members: Array[CharacterView], character_id: String) -> CharacterView:
	for member: CharacterView in members:
		if member.id == character_id:
			return member
	return null


static func _populate_ordinary_action_availability(result: GameView, previous: GameView, inventory_changed: bool, magic_changed: bool) -> void:
	result.action_availability = previous.action_availability.duplicate()
	var fatigue_blocked := result.party_fatigue > 134
	result.set_action_availability(&"area_search", not fatigue_blocked, "The party is too fatigued to continue Area Search." if fatigue_blocked else "")
	result.set_action_availability(&"heal", not fatigue_blocked, "The party is too fatigued to continue Heal." if fatigue_blocked else "")
	if inventory_changed:
		var field_item_available := result.party_members.any(func(member: CharacterView) -> bool: return member.items.any(func(item: ItemView) -> bool: return item.actions != null and item.actions.use.enabled))
		result.set_action_availability(&"use_item", field_item_available, "No carried item has a supported Classic field use." if not field_item_available else "")
	if magic_changed:
		var field_spell_available := false
		var field_spell_reason := "No known spell has a supported Classic field use."
		for member: CharacterView in result.party_members:
			for spell: SpellView in member.spells:
				if spell.field_cast.enabled:
					field_spell_available = true
					break
				if not spell.field_cast.reason.is_empty(): field_spell_reason = spell.field_cast.reason
			if field_spell_available: break
		result.set_action_availability(&"cast_spell", field_spell_available, "" if field_spell_available else field_spell_reason)


static func _ordinary_magic_character_ids(events: Array[DomainEvent]) -> Dictionary:
	var result: Dictionary = {}
	for event: DomainEvent in events:
		var character_id := String(event.payload.get("characterId", ""))
		if event.kind in [&"spell_points_recovered", &"condition_expired", &"condition_healed", &"condition_damaged"] and not character_id.is_empty():
			result[character_id] = true
	return result


func _ordinary_affordability_character_ids(context: SessionWorkflowContext, events: Array[DomainEvent]) -> Dictionary:
	var result: Dictionary = {}
	for event: DomainEvent in events:
		var character_id := String(event.payload.get("characterId", ""))
		if character_id.is_empty():
			continue
		if event.kind in [&"condition_expired", &"condition_healed", &"condition_damaged"] or event.kind == &"spell_points_recovered" and _spell_affordability_crossed(context, character_id):
			result[character_id] = true
	return result


func _spell_affordability_crossed(context: SessionWorkflowContext, character_id: String) -> bool:
	var character := context.state.party.character_by_id(character_id)
	var previous := _character_view_by_id(_cached_view.party_members, character_id)
	if character == null or previous == null:
		return true
	var before := previous.spell_points
	var after := character.spell_points
	for spell_view: SpellView in previous.spells:
		var spell := context.content.magic.spell_by_id(spell_view.id)
		if spell == null:
			continue
		for power: int in spell_view.structural_power_levels:
			if before < absi(spell.cost * power) and after >= absi(spell.cost * power):
				return true
		for power: int in spell_view.structural_scroll_power_levels:
			if before < absi(spell.cost * power * 2) and after >= absi(spell.cost * power * 2):
				return true
	for binding: FastSpellBindingView in previous.fast_spells:
		if binding.spell_id.is_empty():
			continue
		var spell := context.content.magic.spell_by_id(binding.spell_id)
		if spell != null and before < absi(spell.cost * binding.power) and after >= absi(spell.cost * binding.power):
			return true
	return false


static func _ordinary_magic_requires_structural_refresh(events: Array[DomainEvent]) -> bool:
	return events.any(func(event: DomainEvent) -> bool: return event.kind in [&"condition_expired", &"condition_healed", &"condition_damaged"])


func _ordinary_inventory_refresh(context: SessionWorkflowContext, events: Array[DomainEvent]) -> bool:
	if events.any(func(event: DomainEvent) -> bool: return event.kind == &"rest_ration_consumed"):
		return true
	for event: DomainEvent in events:
		if event.kind != &"spell_points_recovered":
			continue
		var character_id := String(event.payload.get("characterId", ""))
		var current := context.state.party.character_by_id(character_id)
		var previous := _character_view_by_id(_cached_view.party_members, character_id)
		if current == null or previous == null or previous.spell_points >= 25 or current.spell_points < 25:
			continue
		for spell_id: String in current.known_spells():
			var spell := context.content.magic.spell_by_id(spell_id)
			if spell != null and absi(spell.special) == 48:
				return true
	return false


func _map_view(context: SessionWorkflowContext, revision: int, reuse_ordinary_cells: bool = false, reuse_static: bool = false) -> MapView:
	if _cached_map_view != null and _cached_map_revision == revision and _cached_map_id == context.state.party.map_id and _cached_map_coordinate == context.state.party.coordinate:
		return _cached_map_view
	if reuse_static and _cached_map_view != null and _cached_map_id == context.state.party.map_id and _cached_map_coordinate == context.state.party.coordinate:
		return _cached_map_view
	var previous_map_view := _cached_map_view
	var presentation_delta: RefCounted
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	# LOS movement returns every cell in the current projection, but shares
	# unchanged immutable cell views and identifies its changed visibility edge.
	var can_reuse_map_cells := reuse_ordinary_cells and previous_map_view != null and current_map != null
	if can_reuse_map_cells:
		var destination := context.state.party.coordinate
		var newly_visited: Array[Vector2i] = []
		var newly_seen: Array[Vector2i] = []
		var visibility_changed: Array[Vector2i] = []
		if not _cached_visited_membership.has(destination): newly_visited.append(destination)
		if current_map.uses_los:
			for coordinate: Vector2i in _prepared_visible_coordinates:
				if not _cached_seen_membership.has(coordinate): newly_seen.append(coordinate)
			for coordinate: Vector2i in _cached_visible_membership:
				if not _prepared_visible_coordinates.has(coordinate): visibility_changed.append(coordinate)
			for coordinate: Vector2i in _prepared_visible_coordinates:
				if not _cached_visible_membership.has(coordinate): visibility_changed.append(coordinate)
		presentation_delta = MapPresentationDelta.new(context.state.party.map_id, previous_map_view.party_coordinate, destination, newly_visited, newly_seen, visibility_changed)
	_cached_map_revision = revision
	_cached_map_id = context.state.party.map_id
	_cached_map_coordinate = context.state.party.coordinate
	_cached_map_view = SessionMapViewBuilder.build_map_view(context, _map_projection_size, _prepared_visibility_map_id, _prepared_visibility_coordinate, _prepared_visible_coordinates, _map_window_cache, _map_cell_cache, previous_map_view if can_reuse_map_cells else null, presentation_delta)
	if presentation_delta != null:
		for coordinate: Vector2i in presentation_delta.newly_visited:
			_cached_visited_membership[coordinate] = true
		for coordinate: Vector2i in presentation_delta.newly_seen:
			_cached_seen_membership[coordinate] = true
	else:
		_cached_visited_membership.clear()
		_cached_seen_membership.clear()
		for coordinate: Vector2i in _cached_map_view.visited_coordinates(): _cached_visited_membership[coordinate] = true
		for coordinate: Vector2i in _cached_map_view.seen_coordinates(): _cached_seen_membership[coordinate] = true
	_cached_visible_membership = _prepared_visible_coordinates if current_map != null and current_map.uses_los else {}
	return _cached_map_view


static func _ordinary_party_summary(context: SessionWorkflowContext, previous: PartySummaryView) -> PartySummaryView:
	if previous == null:
		return null
	var result := PartySummaryView.new()
	result.character_ids = previous.character_ids
	result.ally_ids = previous.ally_ids
	result.acquired_map_ids = previous.acquired_map_ids
	result.pooled_gold = previous.pooled_gold
	result.banked_gold = previous.banked_gold
	result.has_classic_torch = previous.has_classic_torch
	result.fatigue = context.state.party.fatigue
	result.light_remaining = context.state.party.conditions.value(ConditionRules.PARTY_TORCH_LIT)
	result.condition_values = context.state.party.conditions.values()
	result.camping = previous.camping
	result.searching = previous.searching
	result.in_boat = previous.in_boat
	return result


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
		var acquired := state.world.exploration.has_map(definition.id)
		var player_map_view := SessionMapViewBuilder.build_player_map_view(context, definition) if acquired else PlayerMapView.new(definition, [], false, Vector2i.ZERO, false)
		result.player_map_menu_entries.append(player_map_view)
		if acquired:
			result.acquired_player_maps.append(player_map_view)
	var current_map := content.world.map_by_id(state.party.map_id)
	if current_map == null:
		return
	var current_note := state.world.exploration.location_note_at(current_map.id, state.party.coordinate)
	result.current_location_note = LocationNoteView.new(current_map.id, current_map.name, current_map.level_type, current_map.level_index, state.party.coordinate, current_note.text if current_note != null else "", current_note.darkness_value if current_note != null else _current_location_note_darkness(context, current_map), current_note.record_ordinal if current_note != null else -1, true)
	for note: LocationNoteState in state.world.exploration.location_notes_for_kind(current_map.level_type):
		var note_map := content.world.map_by_id(note.map_id)
		if note_map != null:
			result.location_notes.append(LocationNoteView.new(note.map_id, note_map.name, note_map.level_type, note_map.level_index, note.coordinate, note.text, note.darkness_value, note.record_ordinal, note.map_id == state.party.map_id and note.coordinate == state.party.coordinate, SessionMapViewBuilder.build_location_note_map_view(context, note_map, note)))


static func _populate_ordinary_movement_map_views(context: SessionWorkflowContext, result: GameView, previous: GameView) -> void:
	var state := context.state
	for previous_map: PlayerMapView in previous.player_map_menu_entries:
		var definition := context.content.world.player_map_by_id(previous_map.id)
		if definition == null:
			continue
		var source_map := context.content.world.map_by_id(definition.map_id) if not definition.map_id.is_empty() else null
		var show_party := SessionMapViewBuilder.player_map_shows_party(definition, source_map, state.party.map_id, state.party.coordinate)
		var refreshed := PlayerMapView.new(definition, previous_map.cells, show_party, state.party.coordinate, previous_map.acquired)
		result.player_map_menu_entries.append(refreshed)
		if refreshed.acquired:
			result.acquired_player_maps.append(refreshed)
	var current_map := context.content.world.map_by_id(state.party.map_id)
	if current_map == null:
		return
	var current_note := state.world.exploration.location_note_at(current_map.id, state.party.coordinate)
	result.current_location_note = LocationNoteView.new(current_map.id, current_map.name, current_map.level_type, current_map.level_index, state.party.coordinate, current_note.text if current_note != null else "", current_note.darkness_value if current_note != null else _current_location_note_darkness(context, current_map), current_note.record_ordinal if current_note != null else -1, true)
	for previous_note: LocationNoteView in previous.location_notes:
		result.location_notes.append(LocationNoteView.new(previous_note.map_id, previous_note.map_name, previous_note.level_type, previous_note.level_index, previous_note.coordinate, previous_note.text, previous_note.darkness_value, previous_note.record_ordinal, previous_note.map_id == state.party.map_id and previous_note.coordinate == state.party.coordinate, previous_note.preview_map))


static func _current_location_note_darkness(context: SessionWorkflowContext, map: MapDefinition) -> int:
	if map == null or map.level_type == &"dungeon" or not context.state.world.topology.map_is_dark(map):
		return 0
	return clampi(int(context.state.party.conditions.value(0) / 30) + 1, 1, 255)
