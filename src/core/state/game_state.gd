class_name GameState
extends RefCounted

var party: PartyState
var clock: RealmzClock
var world: WorldState
var combat: CombatState
var random_encounters_enabled: bool = true
var camping_allowed: bool = true
var party_in_boat: bool = false
var party_camping: bool = false
var priest_turning_allowed: bool = true
var allies_suspended: bool = false
var character_spellcasting: bool = false
var monster_spellcasting: bool = false
var spell_charging: bool = false
var last_move_direction: Vector2i = Vector2i.ZERO
var active_shop_id: String = ""
var _shop_accept_ranges: Array[int] = []
var last_battle_outcome: StringName = &"none"
var party_setup_completed: bool = false
var _searched_cells: Dictionary = {}
var _quest_values: Dictionary = {}
var _selected_character_ids: Array[String] = []
var _timed_encounter_overrides: Dictionary = {}
var _instance_counter: int = 0
var _eliminated_simple_options: Dictionary = {}
var _shop_overrides: Dictionary = {}
var _shop_inflation_overrides: Dictionary = {}
var _encounter_attempts: Dictionary = {}
var _thief_encounter_type_flags: Dictionary = {}
var _scenario_program_overrides: Dictionary = {}


func _init(party_state: PartyState, realmz_clock: RealmzClock, world_state: WorldState = null) -> void:
	party = party_state
	clock = realmz_clock
	world = world_state if world_state != null else WorldState.new()


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


func eliminate_simple_option(encounter_id: int, option_index: int) -> bool:
	if encounter_id < 0 or option_index < 0 or option_index > 3:
		return false
	_eliminated_simple_options["%d:%d" % [encounter_id, option_index]] = true
	return true


func simple_option_is_eliminated(encounter_id: int, option_index: int) -> bool:
	return _eliminated_simple_options.has("%d:%d" % [encounter_id, option_index])


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
		"partyCamping": party_camping,
		"priestTurningAllowed": priest_turning_allowed,
		"alliesSuspended": allies_suspended,
		"characterSpellcasting": character_spellcasting,
		"monsterSpellcasting": monster_spellcasting,
		"spellCharging": spell_charging,
		"lastMoveX": last_move_direction.x,
		"lastMoveY": last_move_direction.y,
		"activeShopId": active_shop_id,
		"shopAcceptRanges": _shop_accept_ranges.duplicate(),
		"lastBattleOutcome": String(last_battle_outcome),
		"partySetupCompleted": party_setup_completed,
		"questValues": quests,
		"selectedCharacterIds": _selected_character_ids.duplicate(),
		"timedEncounterOverrides": timed,
		"instanceCounter": _instance_counter,
		"eliminatedSimpleOptions": _sorted_string_keys(_eliminated_simple_options),
		"shopOverrides": _sorted_dictionary(_shop_overrides),
		"shopInflationOverrides": _sorted_dictionary(_shop_inflation_overrides),
		"encounterAttempts": _sorted_dictionary(_encounter_attempts),
		"thiefEncounterTypeFlags": _sorted_dictionary(_thief_encounter_type_flags),
		"scenarioProgramOverrides": _sorted_dictionary(_scenario_program_overrides),
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
	if data.has("combat") and data["combat"] != null:
		state.combat = CombatState.from_data(data["combat"])
		if state.combat == null:
			return null
		if state.combat.pending_monster_attack != null and party_state.character_by_id(state.combat.pending_monster_attack.target_id) == null:
			return null
	for key: Variant in data["searchedCells"]:
		if not key is String or key.is_empty():
			return null
		state._searched_cells[key] = true
	if data.has("randomEncountersEnabled"):
		for field: String in ["randomEncountersEnabled", "campingAllowed", "lastBattleOutcome", "questValues", "selectedCharacterIds", "timedEncounterOverrides", "instanceCounter", "eliminatedSimpleOptions", "shopOverrides", "shopInflationOverrides", "encounterAttempts", "thiefEncounterTypeFlags", "scenarioProgramOverrides"]:
			if not data.has(field):
				return null
		if not data["randomEncountersEnabled"] is bool or not data["campingAllowed"] is bool or not data["lastBattleOutcome"] is String or not data["questValues"] is Dictionary or not data["selectedCharacterIds"] is Array or not data["timedEncounterOverrides"] is Dictionary:
			return null
		if data.has("partySetupCompleted") and not data["partySetupCompleted"] is bool:
			return null
		var counter := _integer(data["instanceCounter"])
		if counter < 0:
			return null
		state.random_encounters_enabled = data["randomEncountersEnabled"]
		state.camping_allowed = data["campingAllowed"]
		if data.has("partyInBoat") and (not data["partyInBoat"] is bool or not data.get("partyCamping") is bool):
			return null
		state.party_in_boat = bool(data.get("partyInBoat", false))
		state.party_camping = bool(data.get("partyCamping", false))
		if data.has("priestTurningAllowed") and not data["priestTurningAllowed"] is bool:
			return null
		state.priest_turning_allowed = bool(data.get("priestTurningAllowed", true))
		if data.has("alliesSuspended") and not data["alliesSuspended"] is bool:
			return null
		state.allies_suspended = bool(data.get("alliesSuspended", false))
		for field: String in ["characterSpellcasting", "monsterSpellcasting", "spellCharging"]:
			if data.has(field) and not data[field] is bool:
				return null
		state.character_spellcasting = bool(data.get("characterSpellcasting", false))
		state.monster_spellcasting = bool(data.get("monsterSpellcasting", false))
		state.spell_charging = bool(data.get("spellCharging", false))
		if data.has("lastMoveX") or data.has("lastMoveY"):
			var last_x := _signed_integer(data.get("lastMoveX"))
			var last_y := _signed_integer(data.get("lastMoveY"))
			var last_direction := Vector2i(last_x, last_y)
			if last_direction != Vector2i.ZERO and not MapTopology.is_cardinal_direction(last_direction) and not MapTopology.is_diagonal_direction(last_direction):
				return null
			state.last_move_direction = last_direction
		if data.has("activeShopId") or data.has("shopAcceptRanges"):
			if not data.get("activeShopId") is String or not data.get("shopAcceptRanges") is Array:
				return null
			var accept_ranges: Array[int] = []
			for value: Variant in data["shopAcceptRanges"]:
				var accepted := _signed_integer(value)
				if accepted < -32_768 or accepted > 32_767:
					return null
				accept_ranges.append(accepted)
			if not String(data["activeShopId"]).is_empty() and not state.set_active_shop(data["activeShopId"], accept_ranges):
				return null
			if String(data["activeShopId"]).is_empty() and not accept_ranges.is_empty():
				return null
		state.last_battle_outcome = StringName(data["lastBattleOutcome"])
		state.party_setup_completed = bool(data.get("partySetupCompleted", false))
		for key: Variant in data["questValues"]:
			if not key is String or not key.is_valid_int():
				return null
			var quest_id: int = String(key).to_int()
			var loaded_quest_value := _signed_integer(data["questValues"][key])
			if quest_id < 0 or quest_id >= 100 or loaded_quest_value < -32_768 or loaded_quest_value > 32_767:
				return null
			state._quest_values[quest_id] = loaded_quest_value
		var selected: Array[String] = []
		for id: Variant in data["selectedCharacterIds"]:
			if not id is String:
				return null
			selected.append(id)
		if not state.set_selected_character_ids(selected):
			return null
		for key: Variant in data["timedEncounterOverrides"]:
			if not key is String or not key.is_valid_int() or not data["timedEncounterOverrides"][key] is Dictionary:
				return null
			state._timed_encounter_overrides[String(key).to_int()] = data["timedEncounterOverrides"][key].duplicate(true)
		state._instance_counter = counter
		if not data["eliminatedSimpleOptions"] is Array or not data["shopOverrides"] is Dictionary:
			return null
		for key: Variant in data["eliminatedSimpleOptions"]:
			if not key is String or key.is_empty():
				return null
			state._eliminated_simple_options[key] = true
		for key: Variant in data["shopOverrides"]:
			var quantity := _integer(data["shopOverrides"][key])
			if not key is String or key.is_empty() or quantity < 0 or quantity > 32_767:
				return null
			state._shop_overrides[key] = quantity
		if not data["shopInflationOverrides"] is Dictionary:
			return null
		for key: Variant in data["shopInflationOverrides"]:
			var inflation := _integer(data["shopInflationOverrides"][key])
			if not key is String or key.is_empty() or inflation < 0 or inflation > 32_767:
				return null
			state._shop_inflation_overrides[key] = inflation
		if not data["encounterAttempts"] is Dictionary or not data["thiefEncounterTypeFlags"] is Dictionary:
			return null
		for key: Variant in data["encounterAttempts"]:
			var count := _integer(data["encounterAttempts"][key])
			if not key is String or key.is_empty() or count < 0 or count > 32_767:
				return null
			state._encounter_attempts[key] = count
		for key: Variant in data["thiefEncounterTypeFlags"]:
			var flags: Variant = data["thiefEncounterTypeFlags"][key]
			if not key is String or not String(key).is_valid_int() or not flags is Array or flags.size() != 10:
				return null
			var copied: Array[bool] = []
			for flag: Variant in flags:
				if not flag is bool:
					return null
				copied.append(flag)
			state._thief_encounter_type_flags[key] = copied
		if not data["scenarioProgramOverrides"] is Dictionary:
			return null
		for key: Variant in data["scenarioProgramOverrides"]:
			var target: Variant = data["scenarioProgramOverrides"][key]
			if not key is String or key.is_empty() or not target is String or target.is_empty():
				return null
			state._scenario_program_overrides[key] = target
	if state.party.characters().is_empty() and (not data.has("partySetupCompleted") or state.party_setup_completed):
		return null
	for character: CharacterState in state.party.characters():
		if character.traitor and (state.combat == null or state.combat.completed):
			return null
	return state


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
