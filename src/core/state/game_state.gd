class_name GameState
extends RefCounted

const JOURNAL_MESSAGE_CAPACITY: int = 3000

var party: PartyState
var clock: RealmzClock
var world: WorldState
var combat: CombatState
var random_encounters_enabled: bool = true
var camping_allowed: bool = true
var party_in_boat: bool = false
var boat_shore_attempts: int = 0
var party_camping: bool = false
var priest_turning_allowed: bool = true
var allies_suspended: bool = false
var character_spellcasting_blocked: bool = false
var monster_spellcasting_blocked: bool = false
var spell_charging: bool = false
var last_move_direction: Vector2i = Vector2i.ZERO
var dungeon_heading: int = 1
var dungeon_multiview: bool = true
var xy_display_hidden: bool = false
var compass_enabled: bool = true
var saved_party_map_id: String = ""
var saved_party_coordinate: Vector2i = Vector2i(-1, -1)
var saved_party_level_type: StringName = &""
var active_shop_id: String = ""
var _shop_accept_ranges: Array[int] = []
var temple_available: bool = false
var temple_cost_percent: int = 100
var bank_available: bool = false
var last_battle_outcome: StringName = &"none"
var party_setup_completed: bool = false
var difficulty: int = 0
var monster_set: int = 0
var experience_multiplier: float = -1.0
var character_draft: CharacterDraft
var _searched_cells: Dictionary = {}
var _quest_values: Dictionary = {}
var _selected_character_ids: Array[String] = []
var _timed_encounter_overrides: Dictionary = {}
var _instance_counter: int = 0
var _eliminated_simple_options: Dictionary = {}
var _eliminated_complex_results: Dictionary = {}
var _shop_overrides: Dictionary = {}
var _shop_inflation_overrides: Dictionary = {}
var _shop_buyback_overrides: Dictionary = {}
var _shop_buyback_slots: Dictionary = {}
var _encounter_attempts: Dictionary = {}
var _thief_encounter_type_flags: Dictionary = {}
var _scenario_program_overrides: Dictionary = {}
var _journal_message_ids: Dictionary = {}
var _combat_auto_character_ids: Dictionary = {}


func _init(party_state: PartyState, realmz_clock: RealmzClock, world_state: WorldState = null) -> void:
	party = party_state
	clock = realmz_clock
	world = world_state if world_state != null else WorldState.new()


func save_party_position(map: MapDefinition) -> bool:
	if map == null or map.id != party.map_id or map.topology.cell_at(party.coordinate) == null:
		return false
	saved_party_map_id = map.id
	saved_party_coordinate = party.coordinate
	saved_party_level_type = map.level_type
	return true


func has_saved_party_position() -> bool:
	return not saved_party_map_id.is_empty() and saved_party_coordinate.x >= 0 and saved_party_coordinate.y >= 0 and saved_party_level_type in [&"land", &"dungeon"]


func mark_searched(map_id: String, coordinate: Vector2i) -> void:
	_searched_cells[_cell_key(map_id, coordinate)] = true


func was_searched(map_id: String, coordinate: Vector2i) -> bool:
	return _searched_cells.has(_cell_key(map_id, coordinate))


func quest_value(quest_id: int) -> int:
	return int(_quest_values.get(quest_id, 0))


func quest_is_set(quest_id: int) -> bool:
	return quest_value(quest_id) != 0


func set_quest_value(quest_id: int, value: int) -> bool:
	if quest_id < 0 or quest_id >= 100:
		return false
	_quest_values[quest_id] = clampi(value, -32_768, 32_767)
	return true


func adjust_quest_value(quest_id: int, amount: int) -> int:
	if not set_quest_value(quest_id, quest_value(quest_id) + amount):
		return 0
	return quest_value(quest_id)


func record_journal_message(message_id: int) -> bool:
	if not journal_message_id_is_valid(message_id):
		return false
	_journal_message_ids[message_id] = true
	return true


func journal_message_is_recorded(message_id: int) -> bool:
	return _journal_message_ids.has(message_id)


func journal_message_ids() -> Array[int]:
	var result: Array[int] = []
	for value: Variant in _journal_message_ids.keys():
		result.append(int(value))
	result.sort()
	return result


static func journal_message_id_is_valid(message_id: int) -> bool:
	return message_id >= 0 and message_id < JOURNAL_MESSAGE_CAPACITY


func selected_character_ids() -> Array[String]:
	return _selected_character_ids.duplicate()


func set_selected_character_ids(ids: Array[String]) -> bool:
	var known: Dictionary = {}
	for character: CharacterState in party.characters():
		known[character.id] = true
	var unique: Array[String] = []
	for id: String in ids:
		if not known.has(id) or unique.has(id):
			return false
		unique.append(id)
	_selected_character_ids = unique
	return true


func selected_characters(living_only: bool = false) -> Array[CharacterState]:
	var result: Array[CharacterState] = []
	for id: String in _selected_character_ids:
		var character := party.character_by_id(id)
		if character != null and (not living_only or character.current_health > 0):
			result.append(character)
	return result


func set_timed_encounter_override(encounter_id: int, value: Dictionary) -> void:
	_timed_encounter_overrides[encounter_id] = value.duplicate(true)


func timed_encounter_override(encounter_id: int) -> Dictionary:
	return (_timed_encounter_overrides.get(encounter_id, {}) as Dictionary).duplicate(true)


func next_instance_id(prefix: String) -> String:
	_instance_counter += 1
	return "%s.%d" % [prefix, _instance_counter]


func instance_id_checkpoint() -> int:
	return _instance_counter


func rollback_instance_ids(checkpoint: int) -> bool:
	if checkpoint < 0 or checkpoint > _instance_counter:
		return false
	_instance_counter = checkpoint
	return true


func eliminate_simple_option(encounter_id: int, option_index: int) -> bool:
	if encounter_id < 0 or option_index < 0 or option_index > 3:
		return false
	_eliminated_simple_options["%d:%d" % [encounter_id, option_index]] = true
	return true


func simple_option_is_eliminated(encounter_id: int, option_index: int) -> bool:
	return _eliminated_simple_options.has("%d:%d" % [encounter_id, option_index])


func eliminate_complex_result(encounter_id: int, result_index: int) -> bool:
	if encounter_id < 0 or result_index < 0 or result_index > 3:
		return false
	_eliminated_complex_results["%d:%d" % [encounter_id, result_index]] = true
	return true


func complex_result_is_eliminated(encounter_id: int, result_index: int) -> bool:
	return _eliminated_complex_results.has("%d:%d" % [encounter_id, result_index])


func encounter_attempts(kind: StringName, encounter_id: int) -> int:
	return int(_encounter_attempts.get("%s:%d" % [String(kind), encounter_id], 0))


func record_encounter_attempt(kind: StringName, encounter_id: int) -> int:
	var key := "%s:%d" % [String(kind), encounter_id]
	var next := mini(32_767, int(_encounter_attempts.get(key, 0)) + 1)
	_encounter_attempts[key] = next
	return next


func thief_encounter_type_flags(encounter: ThiefEncounterDefinition) -> Array[bool]:
	var key := str(encounter.id)
	if not _thief_encounter_type_flags.has(key):
		return encounter.type_flags()
	var result: Array[bool] = []
	for value: Variant in _thief_encounter_type_flags[key]:
		result.append(bool(value))
	return result


func set_thief_encounter_type_flags(encounter: ThiefEncounterDefinition, flags: Array[bool]) -> bool:
	if encounter == null or flags.size() != 10:
		return false
	_thief_encounter_type_flags[str(encounter.id)] = flags.duplicate()
	return true


func set_scenario_program_override(source_program_id: String, target_program_id: String) -> bool:
	if source_program_id.is_empty() or target_program_id.is_empty():
		return false
	_scenario_program_overrides[source_program_id] = target_program_id
	return true


func scenario_program_id(source_program_id: String) -> String:
	return str(_scenario_program_overrides.get(source_program_id, source_program_id))


func shop_quantity(shop: ShopDefinition, stock_index: int) -> int:
	var key := "%s:%d" % [shop.id, stock_index]
	return int(_shop_overrides.get(key, shop.quantity(stock_index)))


func set_shop_quantity(shop: ShopDefinition, stock_index: int, quantity: int) -> bool:
	if shop == null or stock_index < 0 or stock_index >= shop.item_ids().size():
		return false
	_shop_overrides["%s:%d" % [shop.id, stock_index]] = clampi(quantity, 0, 32_767)
	return true


func shop_buyback_quantity(shop_id: String, item_id: String) -> int:
	var shop_items: Variant = _shop_buyback_overrides.get(shop_id, {})
	return int(shop_items.get(item_id, 0)) if shop_items is Dictionary else 0


func set_shop_buyback_quantity(shop_id: String, item_id: String, quantity: int, slot: int = -1) -> bool:
	if shop_id.is_empty() or item_id.is_empty() or quantity < 0 or quantity > 32_767:
		return false
	var shop_items: Dictionary = (_shop_buyback_overrides.get(shop_id, {}) as Dictionary).duplicate()
	var shop_slots: Dictionary = (_shop_buyback_slots.get(shop_id, {}) as Dictionary).duplicate()
	if quantity == 0:
		shop_items.erase(item_id)
		shop_slots.erase(item_id)
	else:
		var retained_slot := slot if slot >= 0 else int(shop_slots.get(item_id, -1))
		if retained_slot < 0 or retained_slot > 999:
			return false
		shop_items[item_id] = quantity
		shop_slots[item_id] = retained_slot
	if shop_items.is_empty():
		_shop_buyback_overrides.erase(shop_id)
		_shop_buyback_slots.erase(shop_id)
	else:
		_shop_buyback_overrides[shop_id] = shop_items
		_shop_buyback_slots[shop_id] = shop_slots
	return true


func shop_buyback_items(shop_id: String) -> Dictionary:
	var items: Variant = _shop_buyback_overrides.get(shop_id, {})
	return items.duplicate() if items is Dictionary else {}


func shop_buyback_slot(shop_id: String, item_id: String) -> int:
	var slots: Variant = _shop_buyback_slots.get(shop_id, {})
	return int(slots.get(item_id, -1)) if slots is Dictionary else -1


func shop_buyback_overrides() -> Dictionary:
	return _sorted_nested_dictionary(_shop_buyback_overrides)


func shop_buyback_slot_overrides() -> Dictionary:
	return _sorted_nested_dictionary(_shop_buyback_slots)


func shop_inflation(shop: ShopDefinition) -> int:
	return int(_shop_inflation_overrides.get(shop.id, shop.inflation_percent))


func set_shop_inflation(shop: ShopDefinition, percent: int) -> bool:
	if shop == null or percent < 0 or percent > 32_767:
		return false
	_shop_inflation_overrides[shop.id] = percent
	return true


func set_active_shop(shop_id: String, accept_ranges: Array[int]) -> bool:
	if shop_id.is_empty() or accept_ranges.size() != 4:
		return false
	active_shop_id = shop_id
	_shop_accept_ranges = accept_ranges.duplicate()
	return true


func shop_accept_ranges() -> Array[int]:
	return _shop_accept_ranges.duplicate()


func set_active_temple(cost_percent: int) -> bool:
	if cost_percent < -32_768 or cost_percent > 32_767:
		return false
	temple_available = true
	temple_cost_percent = cost_percent
	return true


func clear_location_services() -> void:
	active_shop_id = ""
	_shop_accept_ranges.clear()
	temple_available = false
	temple_cost_percent = 100
	bank_available = false


func combat_auto_character_ids() -> Array[String]:
	return _sorted_string_keys(_combat_auto_character_ids)


func combat_auto_enabled(character_id: String) -> bool:
	return bool(_combat_auto_character_ids.get(character_id, false))


func set_combat_auto(character_id: String, enabled: bool) -> bool:
	if not enabled:
		if character_id.is_empty():
			return false
		_combat_auto_character_ids.erase(character_id)
		return true
	var character := party.character_by_id(character_id)
	if character == null or character.current_health <= 0:
		return false
	_combat_auto_character_ids[character_id] = true
	return true


func prune_combat_auto_characters() -> void:
	for character_id: Variant in _combat_auto_character_ids.keys():
		var character := party.character_by_id(String(character_id))
		if character == null or character.current_health <= 0:
			_combat_auto_character_ids.erase(character_id)


func restore_from_data(data: Dictionary) -> bool:
	var loaded := GameState.from_data(data)
	if loaded == null:
		return false
	party = loaded.party
	clock = loaded.clock
	world = loaded.world
	combat = loaded.combat
	random_encounters_enabled = loaded.random_encounters_enabled
	camping_allowed = loaded.camping_allowed
	party_in_boat = loaded.party_in_boat
	boat_shore_attempts = loaded.boat_shore_attempts
	party_camping = loaded.party_camping
	priest_turning_allowed = loaded.priest_turning_allowed
	allies_suspended = loaded.allies_suspended
	character_spellcasting_blocked = loaded.character_spellcasting_blocked
	monster_spellcasting_blocked = loaded.monster_spellcasting_blocked
	spell_charging = loaded.spell_charging
	last_move_direction = loaded.last_move_direction
	dungeon_heading = loaded.dungeon_heading
	dungeon_multiview = loaded.dungeon_multiview
	xy_display_hidden = loaded.xy_display_hidden
	compass_enabled = loaded.compass_enabled
	saved_party_map_id = loaded.saved_party_map_id
	saved_party_coordinate = loaded.saved_party_coordinate
	saved_party_level_type = loaded.saved_party_level_type
	active_shop_id = loaded.active_shop_id
	_shop_accept_ranges = loaded._shop_accept_ranges
	temple_available = loaded.temple_available
	temple_cost_percent = loaded.temple_cost_percent
	bank_available = loaded.bank_available
	last_battle_outcome = loaded.last_battle_outcome
	party_setup_completed = loaded.party_setup_completed
	difficulty = loaded.difficulty
	monster_set = loaded.monster_set
	experience_multiplier = loaded.experience_multiplier
	character_draft = loaded.character_draft
	_searched_cells = loaded._searched_cells
	_quest_values = loaded._quest_values
	_selected_character_ids = loaded._selected_character_ids
	_timed_encounter_overrides = loaded._timed_encounter_overrides
	_instance_counter = loaded._instance_counter
	_eliminated_simple_options = loaded._eliminated_simple_options
	_eliminated_complex_results = loaded._eliminated_complex_results
	_shop_overrides = loaded._shop_overrides
	_shop_inflation_overrides = loaded._shop_inflation_overrides
	_shop_buyback_overrides = loaded._shop_buyback_overrides
	_shop_buyback_slots = loaded._shop_buyback_slots
	_encounter_attempts = loaded._encounter_attempts
	_thief_encounter_type_flags = loaded._thief_encounter_type_flags
	_scenario_program_overrides = loaded._scenario_program_overrides
	_journal_message_ids = loaded._journal_message_ids
	_combat_auto_character_ids = loaded._combat_auto_character_ids
	return true


func to_data() -> Dictionary:
	var searched: Array[String] = []
	for key: Variant in _searched_cells.keys():
		searched.append(String(key))
	searched.sort()
	var quests: Dictionary = {}
	var quest_ids: Array = _quest_values.keys()
	quest_ids.sort()
	for quest_id: Variant in quest_ids:
		quests[str(quest_id)] = _quest_values[quest_id]
	var timed: Dictionary = {}
	var timed_ids: Array = _timed_encounter_overrides.keys()
	timed_ids.sort()
	for encounter_id: Variant in timed_ids:
		timed[str(encounter_id)] = (_timed_encounter_overrides[encounter_id] as Dictionary).duplicate(true)
	var combat_data: Variant = null
	if combat != null:
		combat_data = combat.to_data()
	return {
		"party": party.to_data(),
		"clock": clock.to_data(),
		"searchedCells": searched,
		"worldOverlays": world.to_data(),
		"combat": combat_data,
		"randomEncountersEnabled": random_encounters_enabled,
		"campingAllowed": camping_allowed,
		"partyInBoat": party_in_boat,
		"boatShoreAttempts": boat_shore_attempts,
		"partyCamping": party_camping,
		"priestTurningAllowed": priest_turning_allowed,
		"alliesSuspended": allies_suspended,
		# Save-v3 field names predate the Castle audit. Their values are blocking
		# flags: nonzero Extra Code disables the corresponding caster group.
		"characterSpellcasting": character_spellcasting_blocked,
		"monsterSpellcasting": monster_spellcasting_blocked,
		"spellCharging": spell_charging,
		"lastMoveX": last_move_direction.x,
		"lastMoveY": last_move_direction.y,
		"dungeonHeading": dungeon_heading,
		"dungeonMultiview": dungeon_multiview,
		"xyDisplayHidden": xy_display_hidden,
		"compassEnabled": compass_enabled,
		"partyPositionBookmark": null if not has_saved_party_position() else {"mapId": saved_party_map_id, "x": saved_party_coordinate.x, "y": saved_party_coordinate.y, "levelType": String(saved_party_level_type)},
		"activeShopId": active_shop_id,
		"shopAcceptRanges": _shop_accept_ranges.duplicate(),
		"templeAvailable": temple_available,
		"templeCostPercent": temple_cost_percent,
		"bankAvailable": bank_available,
		"lastBattleOutcome": String(last_battle_outcome),
		"partySetupCompleted": party_setup_completed,
		"difficulty": difficulty,
		"monsterSet": monster_set,
		"experienceMultiplier": experience_multiplier,
		"characterDraft": null if character_draft == null else character_draft.to_data(),
		"questValues": quests,
		"selectedCharacterIds": _selected_character_ids.duplicate(),
		"timedEncounterOverrides": timed,
		"instanceCounter": _instance_counter,
		"eliminatedSimpleOptions": _sorted_string_keys(_eliminated_simple_options),
		"eliminatedComplexResults": _sorted_string_keys(_eliminated_complex_results),
		"shopOverrides": _sorted_dictionary(_shop_overrides),
		"shopInflationOverrides": _sorted_dictionary(_shop_inflation_overrides),
		"shopBuybackOverrides": _sorted_nested_dictionary(_shop_buyback_overrides),
		"shopBuybackSlots": _sorted_nested_dictionary(_shop_buyback_slots),
		"encounterAttempts": _sorted_dictionary(_encounter_attempts),
		"thiefEncounterTypeFlags": _sorted_dictionary(_thief_encounter_type_flags),
		"scenarioProgramOverrides": _sorted_dictionary(_scenario_program_overrides),
		"journalMessageIds": journal_message_ids(),
		"combatAutoCharacterIds": combat_auto_character_ids(),
	}


static func from_data(data: Variant) -> GameState:
	if not data is Dictionary:
		return null
	for field: String in ["party", "clock", "searchedCells", "worldOverlays"]:
		if not data.has(field):
			return null
	var party_state := PartyState.from_data(data["party"])
	var realmz_clock := RealmzClock.from_data(data["clock"])
	var world_state := WorldState.from_data(data["worldOverlays"])
	if party_state == null or realmz_clock == null or world_state == null or not data["searchedCells"] is Array:
		return null
	var state := GameState.new(party_state, realmz_clock, world_state)
	if not _restore_combat_state(state, party_state, data):
		return null
	for key: Variant in data["searchedCells"]:
		if not key is String or key.is_empty():
			return null
		state._searched_cells[key] = true
	if data.has("randomEncountersEnabled") and (not _restore_session_settings(state, data) or not _restore_session_collections(state, data)):
		return null
	if state.party.characters().is_empty() and (not data.has("partySetupCompleted") or state.party_setup_completed):
		return null
	if state.party_setup_completed and state.character_draft != null:
		return null
	for character: CharacterState in state.party.characters():
		if character.traitor and (state.combat == null or state.combat.completed):
			return null
	return state


static func _restore_combat_state(state: GameState, party_state: PartyState, data: Dictionary) -> bool:
	if not data.has("combat") or data["combat"] == null:
		return true
	state.combat = CombatState.from_data(data["combat"])
	if state.combat == null or not _combat_references_are_valid(state, party_state):
		return false
	var owned_item_ids: Dictionary = {}
	for item_id: String in party_state.item_instance_ids():
		owned_item_ids[item_id] = true
	for item: ItemInstance in state.combat.fumbled_items():
		if owned_item_ids.has(item.id): return false
		owned_item_ids[item.id] = true
	return true


static func _combat_references_are_valid(state: GameState, party_state: PartyState) -> bool:
	var combat := state.combat
	if combat.battlefield != null:
		var battlefield := combat.battlefield
		if battlefield.map_id != party_state.map_id: return false
		for actor_id: Variant in battlefield.character_positions():
			if not actor_id is String or party_state.character_by_id(actor_id) == null: return false
		for actor_id: Variant in battlefield.monster_positions():
			if not actor_id is String or combat.monster_by_id(actor_id) == null: return false
		for actor_id: String in combat.retreated_character_ids():
			if party_state.character_by_id(actor_id) == null: return false
		for character: CharacterState in party_state.characters():
			var on_field := battlefield.character_position(character.id).x >= 0
			if character.current_health > 0 and not on_field and not combat.has_character_retreated(character.id): return false
			if combat.has_character_retreated(character.id) and (character.current_health <= 0 or on_field): return false
		for monster: MonsterState in combat.monsters():
			if monster.current_health > 0 and battlefield.monster_position(monster.id).x < 0: return false
	for monster: MonsterState in combat.monsters():
		if not monster.target_id.is_empty() and party_state.character_by_id(monster.target_id) == null and combat.monster_by_id(monster.target_id) == null: return false
	for character_id: String in combat.bleeding_character_ids():
		var character := party_state.character_by_id(character_id)
		if character == null or character.current_health > 0 or character.current_health <= -10: return false
	for character_id: String in combat.turn_undead_actor_ids():
		if party_state.character_by_id(character_id) == null: return false
	if combat.active_turn != null and not combat.active_turn.target_id.is_empty() and party_state.character_by_id(combat.active_turn.target_id) == null and combat.monster_by_id(combat.active_turn.target_id) == null: return false
	if combat.pending_monster_attack != null and party_state.character_by_id(combat.pending_monster_attack.target_id) == null: return false
	return _combat_reaction_is_valid(combat, party_state)


static func _combat_reaction_is_valid(combat: CombatState, party_state: PartyState) -> bool:
	if combat.pending_reaction == null: return true
	var reaction := combat.pending_reaction
	var mover_character := party_state.character_by_id(reaction.mover_id)
	var mover_monster := combat.monster_by_id(reaction.mover_id)
	if (reaction.kind == CombatReactionState.CHARACTER_MOVE and mover_character == null) or (reaction.kind != CombatReactionState.CHARACTER_MOVE and mover_monster == null): return false
	for attacker_id: String in reaction.attackers():
		if party_state.character_by_id(attacker_id) == null and combat.monster_by_id(attacker_id) == null: return false
	for hostile_id: String in reaction.origin_hostiles():
		if party_state.character_by_id(hostile_id) == null and combat.monster_by_id(hostile_id) == null: return false
	if combat.battlefield == null: return false
	var expected_position := reaction.destination if reaction.phase == CombatReactionState.GUARD_AFTER and reaction.kind != CombatReactionState.MONSTER_CONTACT else reaction.origin
	return combat.battlefield.actor_position(reaction.mover_id) == expected_position


static func _restore_session_settings(state: GameState, data: Dictionary) -> bool:
	var required := ["randomEncountersEnabled", "campingAllowed", "lastBattleOutcome", "questValues", "selectedCharacterIds", "timedEncounterOverrides", "instanceCounter", "eliminatedSimpleOptions", "shopOverrides", "shopInflationOverrides", "encounterAttempts", "thiefEncounterTypeFlags", "scenarioProgramOverrides"]
	for field: String in required:
		if not data.has(field): return false
	if not data["randomEncountersEnabled"] is bool or not data["campingAllowed"] is bool or not data["lastBattleOutcome"] is String or not data["questValues"] is Dictionary or not data["selectedCharacterIds"] is Array or not data["timedEncounterOverrides"] is Dictionary: return false
	if data.has("partySetupCompleted") and not data["partySetupCompleted"] is bool: return false
	state._instance_counter = _integer(data["instanceCounter"])
	if state._instance_counter < 0: return false
	state.random_encounters_enabled = data["randomEncountersEnabled"]
	state.camping_allowed = data["campingAllowed"]
	if data.has("partyInBoat") and (not data["partyInBoat"] is bool or not data.get("partyCamping") is bool): return false
	state.party_in_boat = bool(data.get("partyInBoat", false))
	state.boat_shore_attempts = _integer(data.get("boatShoreAttempts", 0))
	if state.boat_shore_attempts < 0 or state.boat_shore_attempts > 2:
		return false
	state.party_camping = bool(data.get("partyCamping", false))
	if data.has("priestTurningAllowed") and not data["priestTurningAllowed"] is bool: return false
	if data.has("alliesSuspended") and not data["alliesSuspended"] is bool: return false
	state.priest_turning_allowed = bool(data.get("priestTurningAllowed", true))
	state.allies_suspended = bool(data.get("alliesSuspended", false))
	for field: String in ["characterSpellcasting", "monsterSpellcasting", "spellCharging"]:
		if data.has(field) and not data[field] is bool: return false
	state.character_spellcasting_blocked = bool(data.get("characterSpellcasting", false))
	state.monster_spellcasting_blocked = bool(data.get("monsterSpellcasting", false))
	state.spell_charging = bool(data.get("spellCharging", false))
	if not _restore_location_settings(state, data): return false
	state.last_battle_outcome = StringName(data["lastBattleOutcome"])
	state.party_setup_completed = bool(data.get("partySetupCompleted", false))
	state.difficulty = _signed_integer(data.get("difficulty", 0))
	state.monster_set = _signed_integer(data.get("monsterSet", 0))
	var multiplier: Variant = data.get("experienceMultiplier", -1.0)
	if not multiplier is int and not multiplier is float: return false
	state.experience_multiplier = float(multiplier)
	var multiplier_valid := is_equal_approx(state.experience_multiplier, -1.0) or (state.experience_multiplier >= 0.20 and state.experience_multiplier <= 2.50)
	if state.difficulty < -2 or state.difficulty > 2 or state.monster_set not in [-1, 0, 1] or is_nan(state.experience_multiplier) or is_inf(state.experience_multiplier) or not multiplier_valid: return false
	if data.has("characterDraft") and data["characterDraft"] != null:
		state.character_draft = CharacterDraft.from_data(data["characterDraft"])
		if state.character_draft == null: return false
	return true


static func _restore_location_settings(state: GameState, data: Dictionary) -> bool:
	if data.has("lastMoveX") or data.has("lastMoveY"):
		var direction := Vector2i(_signed_integer(data.get("lastMoveX")), _signed_integer(data.get("lastMoveY")))
		if direction != Vector2i.ZERO and not MapTopology.is_cardinal_direction(direction) and not MapTopology.is_diagonal_direction(direction): return false
		state.last_move_direction = direction
	if data.has("dungeonHeading"):
		state.dungeon_heading = _signed_integer(data["dungeonHeading"])
		if state.dungeon_heading < 1 or state.dungeon_heading > 4: return false
	if data.has("dungeonMultiview"):
		if not data["dungeonMultiview"] is bool: return false
		state.dungeon_multiview = data["dungeonMultiview"]
	for field: String in ["xyDisplayHidden", "compassEnabled"]:
		if data.has(field) and not data[field] is bool: return false
	state.xy_display_hidden = bool(data.get("xyDisplayHidden", false))
	state.compass_enabled = bool(data.get("compassEnabled", true))
	if data.has("partyPositionBookmark") and data["partyPositionBookmark"] != null:
		var bookmark: Variant = data["partyPositionBookmark"]
		if not bookmark is Dictionary or bookmark.size() != 4 or not bookmark.get("mapId") is String or bookmark["mapId"].is_empty() or bookmark.get("levelType") not in ["land", "dungeon"]:
			return false
		var bookmark_x := _signed_integer(bookmark.get("x")); var bookmark_y := _signed_integer(bookmark.get("y"))
		if bookmark_x < 0 or bookmark_y < 0:
			return false
		state.saved_party_map_id = bookmark["mapId"]
		state.saved_party_coordinate = Vector2i(bookmark_x, bookmark_y)
		state.saved_party_level_type = StringName(bookmark["levelType"])
	if data.has("activeShopId") or data.has("shopAcceptRanges"):
		if not data.get("activeShopId") is String or not data.get("shopAcceptRanges") is Array: return false
		var ranges: Array[int] = []
		for value: Variant in data["shopAcceptRanges"]:
			var accepted := _signed_integer(value)
			if accepted < -32_768 or accepted > 32_767: return false
			ranges.append(accepted)
		if not String(data["activeShopId"]).is_empty() and not state.set_active_shop(data["activeShopId"], ranges): return false
		if String(data["activeShopId"]).is_empty() and not ranges.is_empty(): return false
	if data.has("templeAvailable") or data.has("templeCostPercent") or data.has("bankAvailable"):
		if not data.get("templeAvailable") is bool or not data.get("bankAvailable") is bool: return false
		var percent := _signed_integer(data.get("templeCostPercent"))
		if percent < -32_768 or percent > 32_767: return false
		state.temple_available = data["templeAvailable"]
		state.temple_cost_percent = percent
		state.bank_available = data["bankAvailable"]
	return true


static func _restore_session_collections(state: GameState, data: Dictionary) -> bool:
	for key: Variant in data["questValues"]:
		if not key is String or not key.is_valid_int(): return false
		var quest_id: int = String(key).to_int()
		var value := _signed_integer(data["questValues"][key])
		if quest_id < 0 or quest_id >= 100 or value < -32_768 or value > 32_767: return false
		state._quest_values[quest_id] = value
	var selected: Array[String] = []
	for id: Variant in data["selectedCharacterIds"]:
		if not id is String: return false
		selected.append(id)
	if not state.set_selected_character_ids(selected): return false
	for key: Variant in data["timedEncounterOverrides"]:
		if not key is String or not key.is_valid_int() or not data["timedEncounterOverrides"][key] is Dictionary: return false
		state._timed_encounter_overrides[String(key).to_int()] = data["timedEncounterOverrides"][key].duplicate(true)
	return _restore_override_collections(state, data) and _restore_optional_collections(state, data)


static func _restore_override_collections(state: GameState, data: Dictionary) -> bool:
	if not data["eliminatedSimpleOptions"] is Array or not data["shopOverrides"] is Dictionary or not data["shopInflationOverrides"] is Dictionary: return false
	for key: Variant in data["eliminatedSimpleOptions"]:
		if not key is String or key.is_empty(): return false
		state._eliminated_simple_options[key] = true
	if data.has("eliminatedComplexResults"):
		if not data["eliminatedComplexResults"] is Array: return false
		for key: Variant in data["eliminatedComplexResults"]:
			if not key is String or key.is_empty(): return false
			var parts := String(key).split(":")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or parts[0].to_int() < 0 or parts[1].to_int() < 0 or parts[1].to_int() > 3: return false
			state._eliminated_complex_results[key] = true
	for key: Variant in data["shopOverrides"]:
		var quantity := _integer(data["shopOverrides"][key])
		if not key is String or key.is_empty() or quantity < 0 or quantity > 32_767: return false
		state._shop_overrides[key] = quantity
	for key: Variant in data["shopInflationOverrides"]:
		var inflation := _integer(data["shopInflationOverrides"][key])
		if not key is String or key.is_empty() or inflation < 0 or inflation > 32_767: return false
		state._shop_inflation_overrides[key] = inflation
	if data.has("shopBuybackOverrides"):
		if not data["shopBuybackOverrides"] is Dictionary or not data.get("shopBuybackSlots") is Dictionary: return false
		for shop_id: Variant in data["shopBuybackOverrides"]:
			var items: Variant = data["shopBuybackOverrides"][shop_id]
			var slots: Variant = data["shopBuybackSlots"].get(shop_id)
			if not shop_id is String or shop_id.is_empty() or not items is Dictionary or not slots is Dictionary or items.size() != slots.size(): return false
			for item_id: Variant in items:
				var quantity := _integer(items[item_id])
				var slot := _integer(slots.get(item_id))
				if not item_id is String or item_id.is_empty() or not slots.has(item_id) or quantity < 1 or quantity > 32_767 or slot < 0 or slot > 999 or not state.set_shop_buyback_quantity(shop_id, item_id, quantity, slot): return false
		if data["shopBuybackOverrides"].size() != data["shopBuybackSlots"].size(): return false
	elif data.has("shopBuybackSlots") and (not data["shopBuybackSlots"] is Dictionary or not data["shopBuybackSlots"].is_empty()): return false
	return true


static func _restore_optional_collections(state: GameState, data: Dictionary) -> bool:
	if not data["encounterAttempts"] is Dictionary or not data["thiefEncounterTypeFlags"] is Dictionary or not data["scenarioProgramOverrides"] is Dictionary: return false
	for key: Variant in data["encounterAttempts"]:
		var count := _integer(data["encounterAttempts"][key])
		if not key is String or key.is_empty() or count < 0 or count > 32_767: return false
		state._encounter_attempts[key] = count
	for key: Variant in data["thiefEncounterTypeFlags"]:
		var flags: Variant = data["thiefEncounterTypeFlags"][key]
		if not key is String or not String(key).is_valid_int() or not flags is Array or flags.size() != 10: return false
		var copied: Array[bool] = []
		for flag: Variant in flags:
			if not flag is bool: return false
			copied.append(flag)
		state._thief_encounter_type_flags[key] = copied
	for key: Variant in data["scenarioProgramOverrides"]:
		var target: Variant = data["scenarioProgramOverrides"][key]
		if not key is String or key.is_empty() or not target is String or target.is_empty(): return false
		state._scenario_program_overrides[key] = target
	if data.has("journalMessageIds"):
		if not data["journalMessageIds"] is Array: return false
		for value: Variant in data["journalMessageIds"]:
			var message_id := _integer(value)
			if not journal_message_id_is_valid(message_id) or state.journal_message_is_recorded(message_id): return false
			state._journal_message_ids[message_id] = true
	if data.has("combatAutoCharacterIds"):
		if not data["combatAutoCharacterIds"] is Array or data["combatAutoCharacterIds"].size() > 6: return false
		for character_id: Variant in data["combatAutoCharacterIds"]:
			if not character_id is String or state._combat_auto_character_ids.has(character_id) or not state.set_combat_auto(character_id, true): return false
	return true


static func _cell_key(map_id: String, coordinate: Vector2i) -> String:
	return "%s:%d,%d" % [map_id, coordinate.x, coordinate.y]


static func _integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -1


static func _signed_integer(value: Variant) -> int:
	if value is int:
		return value
	if value is float and is_equal_approx(value, round(value)):
		return int(value)
	return -100_000


static func _sorted_string_keys(source: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for key: Variant in source:
		result.append(String(key))
	result.sort()
	return result


static func _sorted_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		result[key] = source[key]
	return result


static func _sorted_nested_dictionary(source: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var keys: Array = source.keys()
	keys.sort()
	for key: Variant in keys:
		if source[key] is Dictionary:
			result[key] = _sorted_dictionary(source[key])
	return result
