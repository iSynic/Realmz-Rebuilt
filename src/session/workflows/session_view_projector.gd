class_name SessionViewProjector
extends RefCounted

const DEFAULT_MAP_VIEW_SIZE: Vector2i = Vector2i(25, 25)
const ViewDomainRevisionsScript := preload("res://src/core/session/view_domain_revisions.gd")
const MapPresentationDeltaScript := preload("res://src/core/view/map_presentation_delta.gd")
const ViewChangeSetScript := preload("res://src/core/view/view_change_set.gd")
const ProjectionPolicy := preload("res://src/session/workflows/session_view_projection_policy.gd")

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
var _equipment_by_character_id: Dictionary = {}; var _map_window_cache: Dictionary = {}; var _map_cell_cache: Dictionary = {}


func project(context: SessionWorkflowContext, pending_interaction: InteractionRequest, revision: int, started: bool, events: Array[DomainEvent] = []) -> GameView:
	if _cached_view != null and _cached_view.revision == revision:
		return _cached_view
	if not started:
		_cached_view = GameView.new(revision, false, null)
		return _cached_view
	if _can_project_ordinary_movement(context, pending_interaction, events):
		_cached_view = _project_ordinary_movement(context, revision, events)
		return _cached_view
	_cached_view = _project_complete(context, pending_interaction, revision)
	return _cached_view


func _project_complete(context: SessionWorkflowContext, pending_interaction: InteractionRequest, revision: int) -> GameView:
	var content := context.content
	var state := context.state
	var rules := context.rules
	var members: Array[CharacterView] = []
	var item_definitions := content.item_definitions()
	_equipment_by_character_id.clear(); _map_window_cache.clear()
	for character: CharacterState in state.party.characters():
		var member_view := CharacterView.new(character, content)
		var equipment := rules.inventory.combat_equipment(character, item_definitions)
		_equipment_by_character_id[character.id] = equipment
		member_view.apply_equipment(equipment)
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
	for definition: MonsterDefinition in content.bestiary_definitions_for_set(state.monster_set):
		result.bestiary_entries.append(MonsterCatalogEntryView.new(definition, content))
	result.campaign_id = content.campaign_id
	result.rules_version = content.rules_version
	result.character_spellcasting_blocked = state.character_spellcasting_blocked
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
	result.campaign_summary.maximum_party_levels = 0
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
	result.party_summary.condition_values = state.party.conditions.values()
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
	_cached_visited_membership.clear()
	_cached_seen_membership.clear()
	_cached_visible_membership.clear()
	_cached_view = null
	_prepared_visibility_map_id = ""
	_prepared_visibility_coordinate = Vector2i(-1, -1)
	_prepared_visible_coordinates.clear()
	_visibility_membership_cache.clear()
	_equipment_by_character_id.clear(); _map_window_cache.clear(); _map_cell_cache.clear()


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


func _can_project_ordinary_movement(context: SessionWorkflowContext, pending_interaction: InteractionRequest, events: Array[DomainEvent]) -> bool:
	if _cached_view == null or pending_interaction != null or _cached_view.pending_interaction != null or _cached_view.combat_view != null or events.is_empty():
		return false
	if _cached_view.party_map_id != context.state.party.map_id:
		return false
	var current_map := context.content.world.map_by_id(context.state.party.map_id)
	if current_map == null:
		return false
	var moved_count := 0
	var heading_change_count := 0
	for event: DomainEvent in events:
		match event.kind:
			&"party_moved", &"debug_party_noclip_moved":
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
			&"dungeon_heading_changed":
				if current_map.level_type != &"dungeon":
					return false
				var source := String(event.payload.get("source", ""))
				if source == "classic":
					if int(event.payload.get("heading", 0)) != context.state.dungeon_heading or int(event.payload.get("delta", 0)) not in [-1, 1]:
						return false
				elif source == "classic-overhead-movement":
					if int(event.payload.get("current", 0)) != context.state.dungeon_heading:
						return false
				else:
					return false
				heading_change_count += 1
				if heading_change_count > 1:
					return false
			&"time_advanced": pass
			&"sound_requested":
				if String(event.payload.get("source", "")) != "classic-map-movement" or bool(event.payload.get("waitForCompletion", true)) or event.payload.has("stopExisting"):
					return false
			&"fatigue_changed":
				if String(event.payload.get("source", "")) != "classic" or String(event.payload.get("reason", "")) != "hour-boundary" or int(event.payload.get("current", -1)) != context.state.party.fatigue:
					return false
			&"spell_points_recovered":
				var character := context.state.party.character_by_id(String(event.payload.get("characterId", "")))
				if String(event.payload.get("source", "")) != "classic-hour" or character == null or int(event.payload.get("amount", 0)) <= 0:
					return false
			&"ally_spell_points_recovered":
				var ally := _ally_by_id(context.state.party, String(event.payload.get("allyId", "")))
				if String(event.payload.get("source", "")) != "classic-hour" or ally == null or int(event.payload.get("amount", 0)) <= 0:
					return false
			&"condition_expired":
				var character := context.state.party.character_by_id(String(event.payload.get("characterId", "")))
				var condition := int(event.payload.get("condition", -1))
				if character == null or condition < 0 or condition >= ConditionSet.CHARACTER_COUNT or character.conditions.value(condition) != 0:
					return false
			&"condition_healed", &"condition_damaged":
				var character := context.state.party.character_by_id(String(event.payload.get("characterId", "")))
				var condition := int(event.payload.get("condition", -1))
				if character == null or condition < 0 or condition >= ConditionSet.CHARACTER_COUNT or int(event.payload.get("amount", 0)) <= 0:
					return false
			&"party_condition_expired":
				var condition := int(event.payload.get("condition", -1))
				if condition < 0 or condition >= ConditionSet.PARTY_COUNT or context.state.party.conditions.value(condition) != 0:
					return false
			&"ally_condition_expired":
				var ally := _ally_by_id(context.state.party, String(event.payload.get("allyId", "")))
				var condition := int(event.payload.get("condition", -1))
				if ally == null or condition < 0 or condition >= ConditionSet.CHARACTER_COUNT or ally.conditions.value(condition) != 0:
					return false
			&"health_recovered":
				var character := context.state.party.character_by_id(String(event.payload.get("characterId", "")))
				if String(event.payload.get("source", "")) != "classic-half-day" or character == null or int(event.payload.get("amount", 0)) <= 0:
					return false
			&"ally_health_recovered":
				var ally := _ally_by_id(context.state.party, String(event.payload.get("allyId", "")))
				if String(event.payload.get("source", "")) != "classic-half-day" or ally == null or int(event.payload.get("amount", 0)) <= 0:
					return false
			&"rest_ration_consumed":
				if String(event.payload.get("source", "")) != "classic-half-day" or String(event.payload.get("characterId", "")).is_empty() or String(event.payload.get("instanceId", "")).is_empty():
					return false
			&"random_encounter_checked":
				if bool(event.payload.get("triggered", false)):
					return false
			&"movement_secret_search_completed":
				if String(event.payload.get("mapId", "")) != context.state.party.map_id or Vector2i(int(event.payload.get("x", -100000)), int(event.payload.get("y", -100000))) != context.state.party.coordinate or not (event.payload.get("discoveredSecrets", []) as Array).is_empty():
					return false
			_:
				return false
	return moved_count == 1 or moved_count == 0 and heading_change_count == 1 and _cached_view.party_coordinate == context.state.party.coordinate


static func _ally_by_id(party: PartyState, ally_id: String) -> MonsterState:
	for ally: MonsterState in party.allies():
		if ally.id == ally_id:
			return ally
	return null


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
	var members: Array[CharacterView] = []
	if refresh_party:
		var characters := state.party.characters()
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
				equipment = context.rules.inventory.combat_equipment(character, context.content.item_definitions())
				_equipment_by_character_id[character.id] = equipment
			members.append(CharacterView.new(character, context.content, previous_member, true, magic_changed) if inventory_refresh else CharacterView.refreshed_status(character, context.content, previous_member, equipment, magic_changed, structural_magic_refresh))
			if inventory_refresh: members[-1].apply_equipment(equipment)
	else:
		members.assign(_cached_view.party_members)
	var party_done := Time.get_ticks_usec()
	var projected_map := _map_view(context, revision, true)
	var map_done := Time.get_ticks_usec()
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
	if refresh_party:
		for ally: MonsterState in state.party.allies():
			result.party_allies.append(MonsterView.new(ally, context.content.monster_by_id(ally.definition_id), context.content))
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
		_populate_inventory_item_actions(context, result)
	var inventory_done := Time.get_ticks_usec()
	if not magic_affordability_ids.is_empty():
		if structural_magic_refresh:
			_populate_spell_actions(context, result, magic_affordability_ids)
		else:
			_populate_spell_affordability(context, result, magic_affordability_ids)
	var magic_done := Time.get_ticks_usec()
	if refresh_party:
		_populate_ordinary_action_availability(result, _cached_view, inventory_refresh, not magic_affordability_ids.is_empty())
	else:
		result.action_availability = _cached_view.action_availability.duplicate()
	var revisions := ViewDomainRevisionsScript.new()
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
	result.domain_revisions = revisions
	var changes := ViewChangeSetScript.new()
	changes.mark_domain(ViewChangeSetScript.EXPLORATION)
	if refresh_party:
		changes.mark_domain(ViewChangeSetScript.PARTY_STATUS)
		for character_id: String in status_character_ids: changes.mark_character(character_id)
	if inventory_refresh: changes.mark_domain(ViewChangeSetScript.INVENTORY)
	if not magic_character_ids.is_empty(): changes.mark_domain(ViewChangeSetScript.MAGIC)
	changes.mark_domain(ViewChangeSetScript.SYSTEM)
	for character_id: String in magic_character_ids: changes.mark_character(character_id)
	result.change_set = changes
	result.projection_timings_usec = {
		"partyStatus": party_done - projection_started,
		"mapWindow": map_done - party_done,
		"explorationShell": shell_done - map_done,
		"inventory": inventory_done - shell_done,
		"magic": magic_done - inventory_done,
		"finalize": Time.get_ticks_usec() - magic_done,
	}
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
		var spell := context.content.spell_by_id(spell_view.id)
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
		var spell := context.content.spell_by_id(binding.spell_id)
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
			var spell := context.content.spell_by_id(spell_id)
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
		presentation_delta = MapPresentationDeltaScript.new(context.state.party.map_id, previous_map_view.party_coordinate, destination, newly_visited, newly_seen, visibility_changed)
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
		_cached_visited_membership.clear(); _cached_seen_membership.clear()
		for coordinate: Vector2i in _cached_map_view.visited_coordinates(): _cached_visited_membership[coordinate] = true
		for coordinate: Vector2i in _cached_map_view.seen_coordinates(): _cached_seen_membership[coordinate] = true
	_cached_visible_membership = _prepared_visible_coordinates if current_map != null and current_map.uses_los else {}
	return _cached_map_view


static func _ordinary_party_summary(context: SessionWorkflowContext, previous: PartySummaryView) -> PartySummaryView:
	if previous == null:
		return null
	var result := PartySummaryView.new()
	result.character_ids = previous.character_ids; result.ally_ids = previous.ally_ids; result.acquired_map_ids = previous.acquired_map_ids
	result.pooled_gold = previous.pooled_gold; result.banked_gold = previous.banked_gold; result.has_classic_torch = previous.has_classic_torch
	result.fatigue = context.state.party.fatigue; result.light_remaining = context.state.party.conditions.value(ConditionRules.PARTY_TORCH_LIT)
	result.condition_values = context.state.party.conditions.values()
	result.camping = previous.camping; result.searching = previous.searching; result.in_boat = previous.in_boat
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
		var acquired := state.world.has_map(definition.id)
		var player_map_view := SessionMapViewBuilder.build_player_map_view(context, definition) if acquired else PlayerMapView.new(definition, [], false, Vector2i.ZERO, false)
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
	var current_note := state.world.location_note_at(current_map.id, state.party.coordinate)
	result.current_location_note = LocationNoteView.new(current_map.id, current_map.name, current_map.level_type, current_map.level_index, state.party.coordinate, current_note.text if current_note != null else "", current_note.darkness_value if current_note != null else _current_location_note_darkness(context, current_map), current_note.record_ordinal if current_note != null else -1, true)
	for previous_note: LocationNoteView in previous.location_notes:
		result.location_notes.append(LocationNoteView.new(previous_note.map_id, previous_note.map_name, previous_note.level_type, previous_note.level_index, previous_note.coordinate, previous_note.text, previous_note.darkness_value, previous_note.record_ordinal, previous_note.map_id == state.party.map_id and previous_note.coordinate == state.party.coordinate, previous_note.preview_map))


static func _populate_services(context: SessionWorkflowContext, result: GameView) -> void:
	if not context.state.active_shop_id.is_empty():
		var shop := context.content.shop_by_id(context.state.active_shop_id)
		if shop != null:
			var shop_view := ServiceView.new()
			shop_view.service_id = shop.id
			shop_view.service_kind = &"shop"
			shop_view.title = "Shop"
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
			var kind := ProjectionPolicy.money_kind(denomination)
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


static func _populate_spell_actions(context: SessionWorkflowContext, result: GameView, character_filter: Dictionary = {}) -> void:
	var state := context.state
	var content := context.content
	var rules := context.rules
	var blocked_reason := "Resolve the current interaction first." if result.pending_interaction != null else "Complete party setup first." if result.party_setup_available else ""
	var battle_active := result.combat_view != null and result.combat_view.outcome == &"active"
	for member_view: CharacterView in result.party_members:
		if not character_filter.is_empty() and not character_filter.has(member_view.id):
			continue
		var character := state.party.character_by_id(member_view.id)
		for spell_view: SpellView in member_view.spells:
			var spell := content.spell_by_id(spell_view.id)
			spell_view.power_levels.clear(); spell_view.structural_power_levels.clear(); spell_view.scroll_power_levels.clear(); spell_view.structural_scroll_power_levels.clear()
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
				var probe := _field_spell_probe(context, character, spell, power, false)
				if probe.allowed:
					spell_view.structural_power_levels.append(power)
					if character.spell_points >= absi(spell.cost * power): spell_view.power_levels.append(power)
					elif first_reason.is_empty(): first_reason = "The character does not have enough spell points."
				elif first_reason.is_empty():
					first_reason = probe.reason
				if spell != null and spell.cost < 0:
					break
			spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", not spell_view.power_levels.is_empty(), first_reason)
			var make_reason := ""
			for power: int in range(1, 8):
				var make_probe := _make_scroll_probe(context, character, spell, power, false)
				if make_probe.allowed:
					spell_view.structural_scroll_power_levels.append(power)
					if character.spell_points >= absi(spell.cost * power * 2): spell_view.scroll_power_levels.append(power)
					elif make_reason.is_empty(): make_reason = "Scribing requires twice the spell's normal spell-point cost."
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


static func _populate_spell_affordability(context: SessionWorkflowContext, result: GameView, character_filter: Dictionary) -> void:
	for member_view: CharacterView in result.party_members:
		if not character_filter.has(member_view.id):
			continue
		var character := context.state.party.character_by_id(member_view.id)
		for spell_index: int in member_view.spells.size():
			var spell_view: SpellView = member_view.spells[spell_index]
			var spell := context.content.spell_by_id(spell_view.id)
			if spell == null:
				continue
			var affordable: Array[int] = []
			var affordable_scrolls: Array[int] = []
			for power: int in spell_view.structural_power_levels:
				if character.spell_points >= absi(spell.cost * power): affordable.append(power)
			for power: int in spell_view.structural_scroll_power_levels:
				if character.spell_points >= absi(spell.cost * power * 2): affordable_scrolls.append(power)
			if affordable == spell_view.power_levels and affordable_scrolls == spell_view.scroll_power_levels:
				continue
			spell_view = SpellView.new(spell, spell_view)
			spell_view.power_levels = affordable
			spell_view.scroll_power_levels = affordable_scrolls
			spell_view.field_cast = ActionAvailabilityView.new(&"cast_spell", not spell_view.power_levels.is_empty(), "The character does not have enough spell points.")
			spell_view.make_scroll = ActionAvailabilityView.new(&"cast_spell", not spell_view.scroll_power_levels.is_empty(), "Scribing requires twice the spell's normal spell-point cost.")
			member_view.spells[spell_index] = spell_view
		for fast_index: int in member_view.fast_spells.size():
			var fast_spell: FastSpellBindingView = member_view.fast_spells[fast_index]
			if fast_spell.spell_id.is_empty():
				continue
			var bound_spell := context.content.spell_by_id(fast_spell.spell_id)
			var field_probe := _field_spell_probe(context, character, bound_spell, fast_spell.power)
			if fast_spell.activation.enabled != field_probe.allowed or fast_spell.activation.reason != field_probe.reason:
				var replacement := FastSpellBindingView.new(fast_index, character.fast_spell_at(fast_index), bound_spell)
				replacement.activation = ActionAvailabilityView.new(&"cast_spell", field_probe.allowed, field_probe.reason)
				member_view.fast_spells[fast_index] = replacement


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
			var instance := ProjectionPolicy.item_instance(character, item_view.instance_id)
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
			var use_probe := InventoryMagicServicesWorkflow.field_item_use_probe(context, character, instance, definition)
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


static func _make_scroll_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int, check_affordability: bool = true) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if not context.state.party_camping:
		return InventoryActionProbe.block("Enter camp before making a scroll.")
	if character.current_health < 1 or character.spellcaster_type < 1:
		return InventoryActionProbe.block("The selected character cannot scribe scrolls.")
	if not _has_equipped_scroll_case(context, character):
		return InventoryActionProbe.block("Equip a scroll case before making a scroll.")
	if ProjectionPolicy.first_empty_scroll_slot(character) < 0:
		return InventoryActionProbe.block("The scroll case already contains five spells.")
	if _parchment_instance(context, character) == null:
		return InventoryActionProbe.block("The character has no parchment.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected scroll power.")
	if check_affordability and character.spell_points < absi(spell.cost * power * 2):
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
	if not ProjectionPolicy.field_spell_effect_supported(spell):
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


static func _field_spell_probe(context: SessionWorkflowContext, character: CharacterState, spell: SpellDefinition, power: int, check_affordability: bool = true) -> InventoryActionProbe:
	if character == null or spell == null or not character.known_spells().has(spell.id):
		return InventoryActionProbe.block("The character does not know that spell.")
	if context.state.character_spellcasting_blocked:
		return InventoryActionProbe.block("Classic scenario state currently blocks character spellcasting.")
	if character.current_health < 1 or check_affordability and character.spell_points < 1:
		return InventoryActionProbe.block("The character cannot cast in their current state.")
	for condition: int in [ConditionRules.CONFUSED, ConditionRules.SILENCED, ConditionRules.HELPLESS, ConditionRules.STUPID, ConditionRules.ANIMATED]:
		if character.conditions.is_active(condition):
			return InventoryActionProbe.block("The character's current Classic condition prevents spellcasting.")
	if not spell.in_camp:
		return InventoryActionProbe.block("This spell cannot be cast outside battle.")
	if power < 1 or power > 7 or spell.cost < 0 and power != 1:
		return InventoryActionProbe.block("This spell does not support the selected power level.")
	if check_affordability and character.spell_points < absi(spell.cost * power):
		return InventoryActionProbe.block("The character does not have enough spell points.")
	if spell.target_type < 0 or spell.target_type > 12:
		return InventoryActionProbe.block("This spell has an invalid Classic field target type.")
	if not ProjectionPolicy.field_spell_effect_supported(spell):
		return InventoryActionProbe.block("This spell's Classic field effect is not implemented yet.")
	return InventoryActionProbe.permit()


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
