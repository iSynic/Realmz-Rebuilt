## Stores mutable game state inside a deterministic playthrough.

class_name GameState
extends RefCounted

var party: PartyState
var clock: RealmzClock
var world: WorldState
var combat: CombatState
var scenario_progress: ScenarioProgressState
var location_services: LocationServiceState = LocationServiceState.new()
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
var last_battle_outcome: StringName = &"none"
var party_setup_completed: bool = false
var difficulty: int = 0
var monster_set: int = 0
var experience_multiplier: float = -1.0
var character_draft: CharacterDraftState
var _instance_counter: int = 0
var _combat_auto_character_ids: Dictionary = {}


func _init(party_state: PartyState, realmz_clock: RealmzClock, world_state: WorldState = null) -> void:
	party = party_state
	clock = realmz_clock
	world = world_state if world_state != null else WorldState.new()
	scenario_progress = ScenarioProgressState.new(party)


func save_party_position(map: MapDefinition) -> bool:
	if map == null or map.id != party.map_id or map.topology.cell_at(party.coordinate) == null:
		return false
	saved_party_map_id = map.id
	saved_party_coordinate = party.coordinate
	saved_party_level_type = map.level_type
	return true


func has_saved_party_position() -> bool:
	return not saved_party_map_id.is_empty() and saved_party_coordinate.x >= 0 and saved_party_coordinate.y >= 0 and saved_party_level_type in [&"land", &"dungeon"]


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
	last_battle_outcome = loaded.last_battle_outcome
	party_setup_completed = loaded.party_setup_completed
	difficulty = loaded.difficulty
	monster_set = loaded.monster_set
	experience_multiplier = loaded.experience_multiplier
	character_draft = loaded.character_draft
	scenario_progress = loaded.scenario_progress
	location_services = loaded.location_services
	_instance_counter = loaded._instance_counter
	_combat_auto_character_ids = loaded._combat_auto_character_ids
	return true


func to_data() -> Dictionary:
	var combat_data: Variant = null
	if combat != null:
		combat_data = combat.to_data()
	var data: Dictionary = {
		"party": party.to_data(),
		"clock": clock.to_data(),
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
	}
	LocationServiceStateCodec.write_availability_to(location_services, data)
	data.merge({
		"lastBattleOutcome": String(last_battle_outcome),
		"partySetupCompleted": party_setup_completed,
		"difficulty": difficulty,
		"monsterSet": monster_set,
		"experienceMultiplier": experience_multiplier,
		"characterDraft": null if character_draft == null else character_draft.to_data(),
		"instanceCounter": _instance_counter,
	})
	LocationServiceStateCodec.write_collections_to(location_services, data)
	data["combatAutoCharacterIds"] = combat_auto_character_ids()
	scenario_progress.write_to(data)
	return data


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
	if not state.scenario_progress.restore_searched_cells(data["searchedCells"]):
		return null
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
	for item: ItemInstance in state.combat.dropped_items.items():
		if owned_item_ids.has(item.id): return false
		owned_item_ids[item.id] = true
	return true


static func _combat_references_are_valid(state: GameState, party_state: PartyState) -> bool:
	var combat := state.combat
	if combat.battlefield != null:
		var battlefield := combat.battlefield
		if battlefield.map_id != party_state.map_id: return false
		for actor_id: Variant in battlefield.actors.character_positions():
			if not actor_id is String or party_state.character_by_id(actor_id) == null: return false
		for actor_id: Variant in battlefield.actors.monster_positions():
			if not actor_id is String or combat.roster.monster_by_id(actor_id) == null: return false
		for actor_id: String in combat.actor_statuses.retreated_character_ids():
			if party_state.character_by_id(actor_id) == null: return false
		for character: CharacterState in party_state.characters():
			var on_field := battlefield.actors.character_position(character.id).x >= 0
			if character.current_health > 0 and not on_field and not combat.actor_statuses.has_character_retreated(character.id): return false
			if combat.actor_statuses.has_character_retreated(character.id) and (character.current_health <= 0 or on_field): return false
		for monster: MonsterState in combat.roster.monsters():
			if monster.current_health > 0 and battlefield.actors.monster_position(monster.id).x < 0: return false
	for monster: MonsterState in combat.roster.monsters():
		if not monster.target_id.is_empty() and party_state.character_by_id(monster.target_id) == null and combat.roster.monster_by_id(monster.target_id) == null: return false
	for character_id: String in combat.actor_statuses.bleeding_character_ids():
		var character := party_state.character_by_id(character_id)
		if character == null or character.current_health > 0 or character.current_health <= -10: return false
	for character_id: String in combat.actor_statuses.turn_undead_actor_ids():
		if party_state.character_by_id(character_id) == null: return false
	if combat.turns.active_turn != null and not combat.turns.active_turn.target_id.is_empty() and party_state.character_by_id(combat.turns.active_turn.target_id) == null and combat.roster.monster_by_id(combat.turns.active_turn.target_id) == null: return false
	if combat.pending_monster_attack != null and party_state.character_by_id(combat.pending_monster_attack.target_id) == null: return false
	return _combat_reaction_is_valid(combat, party_state)


static func _combat_reaction_is_valid(combat: CombatState, party_state: PartyState) -> bool:
	if combat.pending_reaction == null: return true
	var reaction := combat.pending_reaction
	var mover_character := party_state.character_by_id(reaction.mover_id)
	var mover_monster := combat.roster.monster_by_id(reaction.mover_id)
	if (reaction.kind == CombatReactionState.CHARACTER_MOVE and mover_character == null) or (reaction.kind != CombatReactionState.CHARACTER_MOVE and mover_monster == null): return false
	for attacker_id: String in reaction.attackers():
		if party_state.character_by_id(attacker_id) == null and combat.roster.monster_by_id(attacker_id) == null: return false
	for hostile_id: String in reaction.origin_hostiles():
		if party_state.character_by_id(hostile_id) == null and combat.roster.monster_by_id(hostile_id) == null: return false
	if combat.battlefield == null: return false
	var expected_position := reaction.destination if reaction.phase == CombatReactionState.GUARD_AFTER and reaction.kind != CombatReactionState.MONSTER_CONTACT else reaction.origin
	return combat.battlefield.actors.actor_position(reaction.mover_id) == expected_position


static func _restore_session_settings(state: GameState, data: Dictionary) -> bool:
	var required := ["randomEncountersEnabled", "campingAllowed", "lastBattleOutcome", "instanceCounter", "shopOverrides", "shopInflationOverrides"]
	for field: String in required:
		if not data.has(field): return false
	if not data["randomEncountersEnabled"] is bool or not data["campingAllowed"] is bool or not data["lastBattleOutcome"] is String: return false
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
		state.character_draft = CharacterDraftState.from_data(data["characterDraft"])
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
		var bookmark_x := _signed_integer(bookmark.get("x"))
		var bookmark_y := _signed_integer(bookmark.get("y"))
		if bookmark_x < 0 or bookmark_y < 0:
			return false
		state.saved_party_map_id = bookmark["mapId"]
		state.saved_party_coordinate = Vector2i(bookmark_x, bookmark_y)
		state.saved_party_level_type = StringName(bookmark["levelType"])
	return LocationServiceStateCodec.restore_availability(state.location_services, data)


static func _restore_session_collections(state: GameState, data: Dictionary) -> bool:
	return state.scenario_progress.restore_collections(data) and LocationServiceStateCodec.restore_collections(state.location_services, data) and _restore_optional_collections(state, data)


static func _restore_optional_collections(state: GameState, data: Dictionary) -> bool:
	if data.has("combatAutoCharacterIds"):
		if not data["combatAutoCharacterIds"] is Array or data["combatAutoCharacterIds"].size() > 6: return false
		for character_id: Variant in data["combatAutoCharacterIds"]:
			if not character_id is String or state._combat_auto_character_ids.has(character_id) or not state.set_combat_auto(character_id, true): return false
	return true


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
