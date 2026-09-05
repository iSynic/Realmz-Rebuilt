## Detaches one battle into player-facing actors, terrain, commands, targets, and movement choices.
class_name CombatView
extends RefCounted


var battle_id: String
var round_number: int
var active_actor_id: String
var attack_units_remaining: int = 0
var movement_remaining: int = 0
var weapon_mode: StringName = &"melee"
var melee_weapon_id: String = ""
var missile_weapon_id: String = ""
var weapon_switch_available: bool = false
var weapon_switch_target_mode: StringName = &""
var weapon_switch_unavailable_reason: String = "The active combatant has no alternate weapon mode."
var ranged_attack_unavailable_reason: String = ""
var melee_attack_unavailable_reason: String = ""
var equipment_error_reason: String = ""
var retreat_available: bool = false
var retreat_unavailable_reason: String = "Retreat is unavailable."
var nearest_enemy_range: int = 127
var outcome: StringName
var turn_order: Array[String] = []
var friendly_actor_ids: Array[String] = []
var hostile_actor_ids: Array[String] = []
var legal_actions: Array[StringName] = []
var targets: Array[MonsterView] = []
var character_targets: Array[CharacterView] = []
var movement_options: Array[CombatMoveOptionView] = []
var monsters: Array[MonsterView] = []
var battlefield: BattlefieldView
var persistent_fields: Array[PersistentCombatFieldView] = []
var auto_turn: ActionAvailabilityView = ActionAvailabilityView.new(&"auto", false, "Auto Turn is unavailable.")
var delay: ActionAvailabilityView = ActionAvailabilityView.new(&"delay", false, "Delay is unavailable.")
var bandage: ActionAvailabilityView = ActionAvailabilityView.new(&"bandage", false, "Bandage is unavailable.")
var turn_undead: ActionAvailabilityView = ActionAvailabilityView.new(&"turn_undead", false, "Turn Undead is unavailable.")
var undo: ActionAvailabilityView = ActionAvailabilityView.new(&"undo", false, "Undo is unavailable.")
var bandage_candidates: Array[CharacterView] = []
var turn_undead_targets: Array[MonsterView] = []
var auto_character_ids: Array[String] = []


func _init(combat: CombatState, characters: Array[CharacterState] = [], content: RealmzContent = null, equipment_rules: EquipmentRules = null, battlefield_rules: BattlefieldRules = null, combat_flow: CombatFlow = null, game_state: GameState = null) -> void:
	battle_id = combat.battle_id
	round_number = combat.turns.round_number
	active_actor_id = combat.turns.active_actor_id()
	outcome = combat.outcome
	turn_order = combat.turns.turn_order()
	_populate_battlefield(combat, content, game_state)
	var adjacent_ids := _adjacent_actor_ids(combat, battlefield_rules)
	_populate_combatants(combat, characters, content, adjacent_ids)
	_populate_active_relationships(combat, characters)
	if combat.completed:
		return
	var active_character := _active_character(characters)
	if active_character != null and content != null and equipment_rules != null:
		_populate_character_actions(combat, characters, content, equipment_rules, battlefield_rules, combat_flow, game_state, active_character)
	_finalize_legal_actions(game_state)


func _populate_battlefield(combat: CombatState, content: RealmzContent, game_state: GameState) -> void:
	if combat.battlefield != null:
		var upper_tileset_id := ""
		var terrain_set: BattleTerrainSetDefinition
		if content != null:
			var source_map := content.world.map_by_id(combat.battlefield.map_id)
			var landlook := -1 if source_map == null else source_map.landlook if game_state == null else game_state.world.topology.map_landlook(source_map)
			if source_map != null and source_map.level_type == &"land" and landlook >= 0:
				upper_tileset_id = "landlook-%d" % landlook
			terrain_set = content.world.battle_terrain_set_for_map(source_map, null if game_state == null else game_state.world)
		battlefield = BattlefieldView.new(combat.battlefield, upper_tileset_id)
		var area_rules := SpellAreaRules.new()
		for field: PersistentCombatField in combat.spell_runtime.persistent_fields():
			var coordinates: Array[Vector2i] = []
			for offset: Vector2i in area_rules.pattern(field.shape):
				var coordinate := field.center + offset
				if not BattlefieldGrid.contains(coordinate):
					continue
				var terrain := terrain_set.tile_by_id(combat.battlefield.terrain.tile_at(coordinate)) if terrain_set != null else null
				if terrain == null or terrain.solid == 0:
					coordinates.append(coordinate)
			var spell := content.magic.spell_by_id(field.spell_id) if content != null else null
			persistent_fields.append(PersistentCombatFieldView.new(field, spell.name if spell != null else field.spell_id, coordinates))


func _adjacent_actor_ids(combat: CombatState, battlefield_rules: BattlefieldRules) -> Array[String]:
	var adjacent_ids: Array[String] = []
	if combat.battlefield != null and battlefield_rules != null and not active_actor_id.is_empty():
		adjacent_ids = battlefield_rules.adjacent_actor_ids(combat.battlefield, active_actor_id)
	return adjacent_ids


func _populate_combatants(combat: CombatState, characters: Array[CharacterState], content: RealmzContent, adjacent_ids: Array[String]) -> void:
	for monster: MonsterState in combat.roster.monsters():
		var definition := content.combat.monster_by_id(monster.definition_id) if content != null else null
		var view := MonsterView.new(monster, definition, content)
		monsters.append(view)
		if monster.current_health > 0 and monster.traitor and adjacent_ids.has(monster.id):
			targets.append(view)
	for character: CharacterState in characters:
		if character.id == active_actor_id:
			attack_units_remaining = character.attacks_remaining
			movement_remaining = character.maximum_movement if combat.turns.active_turn == null else character.movement
		if character.current_health > 0 and character.traitor and adjacent_ids.has(character.id):
			character_targets.append(CharacterView.new(character, content))


func _active_character(characters: Array[CharacterState]) -> CharacterState:
	for character: CharacterState in characters:
		if character.id == active_actor_id:
			return character
	return null


func _populate_character_actions(combat: CombatState, characters: Array[CharacterState], content: RealmzContent, equipment_rules: EquipmentRules, battlefield_rules: BattlefieldRules, combat_flow: CombatFlow, game_state: GameState, active_character: CharacterState) -> void:
	if combat_flow != null:
		_populate_command_probes(combat, characters, content, combat_flow, game_state, active_character)
	var equipment := equipment_rules.combat_equipment(active_character, content.items.definitions())
	_populate_weapon_actions(combat, content, combat_flow, game_state, active_character, equipment)
	_populate_movement_actions(combat, characters, content, battlefield_rules, combat_flow, game_state, active_character)


func _populate_command_probes(combat: CombatState, characters: Array[CharacterState], content: RealmzContent, combat_flow: CombatFlow, game_state: GameState, active_character: CharacterState) -> void:
	var retreat_probe: Variant = combat_flow.reactions.probe_character_retreat(combat, characters, active_character.id)
	retreat_available = retreat_probe.allowed
	retreat_unavailable_reason = retreat_probe.reason_text
	nearest_enemy_range = retreat_probe.nearest_enemy_range
	auto_turn = ActionAvailabilityView.new(&"auto", true)
	var delay_probe := combat_flow.actions.probe_delay(game_state, active_character.id)
	delay = ActionAvailabilityView.new(&"delay", delay_probe.allowed, delay_probe.reason_text)
	var bandage_probe := combat_flow.actions.probe_bandage(game_state, active_character.id)
	bandage = ActionAvailabilityView.new(&"bandage", bandage_probe.allowed, bandage_probe.reason_text)
	var turn_probe := combat_flow.actions.probe_turn_undead(game_state, content, active_character.id)
	turn_undead = ActionAvailabilityView.new(&"turn_undead", turn_probe.allowed, turn_probe.reason_text)
	var undo_probe := combat_flow.actions.probe_undo(game_state, active_character.id)
	undo = ActionAvailabilityView.new(&"undo", undo_probe.allowed, undo_probe.reason_text)
	for candidate_id: String in combat_flow.actions.bandage_candidate_ids(game_state):
		var candidate := game_state.party.character_by_id(candidate_id)
		if candidate != null:
			bandage_candidates.append(CharacterView.new(candidate, content))
	for target_id: String in combat_flow.actions.turn_undead_target_ids(game_state, content):
		var target := combat.roster.monster_by_id(target_id)
		if target != null:
			turn_undead_targets.append(MonsterView.new(target, content.combat.monster_by_id(target.definition_id), content))


func _populate_weapon_actions(combat: CombatState, content: RealmzContent, combat_flow: CombatFlow, game_state: GameState, active_character: CharacterState, equipment: CharacterCombatEquipment) -> void:
	if equipment.valid:
		weapon_mode = combat.actor_statuses.character_weapon_mode(active_character.id)
		melee_weapon_id = equipment.melee_weapon.id if equipment.melee_weapon != null else ""
		missile_weapon_id = equipment.missile_weapon.id if equipment.missile_weapon != null else ""
		weapon_switch_available = weapon_mode == &"missile" or equipment.missile_weapon != null
		weapon_switch_target_mode = &"melee" if weapon_mode == &"missile" else &"missile"
		weapon_switch_unavailable_reason = "" if weapon_switch_available else "The active character has no equipped Classic type-15 missile weapon."
		if weapon_mode != &"melee":
			_populate_projectile_targets(combat, content, combat_flow, active_character, equipment)
		if weapon_switch_available:
			legal_actions.append(&"switch_weapon")
	else:
		equipment_error_reason = equipment.error_message
		weapon_switch_unavailable_reason = equipment.error_message


func _populate_projectile_targets(combat: CombatState, content: RealmzContent, combat_flow: CombatFlow, active_character: CharacterState, equipment: CharacterCombatEquipment) -> void:
	targets.clear()
	character_targets.clear()
	var profile := combat_flow.reactions.character_projectile_profile(active_character, content, equipment) if combat_flow != null else null
	if profile == null or not profile.available:
		ranged_attack_unavailable_reason = profile.error_message if profile != null else "Projectile rules are unavailable."
		return
	for monster: MonsterState in combat.roster.monsters():
		if monster.current_health > 0 and monster.traitor != active_character.traitor and combat_flow.reactions.projectile_target_is_valid(combat, content, active_character.id, monster.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
			targets.append(MonsterView.new(monster, content.combat.monster_by_id(monster.definition_id), content))
	if targets.is_empty():
		ranged_attack_unavailable_reason = "No hostile monster is within the projectile's Classic range and line of sight."
	else:
		legal_actions.append(&"attack")


func _populate_movement_actions(combat: CombatState, characters: Array[CharacterState], content: RealmzContent, battlefield_rules: BattlefieldRules, combat_flow: CombatFlow, game_state: GameState, active_character: CharacterState) -> void:
	if combat.battlefield == null or battlefield_rules == null:
		return
	var map := content.world.map_by_id(combat.battlefield.map_id)
	var terrain_set := content.world.battle_terrain_set_for_map(map, game_state.world) if map != null and game_state != null else null
	if terrain_set == null:
		return
	var contact_attack_available := false
	var movement_allowance := active_character.maximum_movement if combat.turns.active_turn == null else active_character.movement
	for direction: Vector2i in BattlefieldRules.DIRECTIONS:
		var destination := combat.battlefield.actors.actor_position(active_character.id) + direction
		var edge_retreat: Variant = combat_flow.reactions.probe_edge_retreat(combat, active_character.id, destination) if combat_flow != null else null
		var probe := battlefield_rules.probe_step(combat.battlefield, terrain_set, active_character.id, direction, movement_allowance)
		var contact_target_id := ""
		var contact_target_name := ""
		if weapon_mode == &"melee" and probe.reason == &"occupied" and _is_hostile_target(combat, characters, active_character, probe.occupant_id):
			contact_target_id = probe.occupant_id
			contact_target_name = _target_name(combat, characters, contact_target_id)
			contact_attack_available = true
		var move_option := CombatMoveOptionView.new(direction, probe, edge_retreat != null and edge_retreat.allowed, edge_retreat != null and edge_retreat.forced, contact_target_id, contact_target_name)
		if probe.reason == &"occupied" and combat_flow.reactions.friendly_collision_target_id(game_state, active_character.id, destination) == probe.occupant_id:
			move_option.enabled = true
			move_option.reason = &""
			move_option.reason_text = ""
			move_option.movement_cost = 5
		movement_options.append(move_option)
	if weapon_mode == &"melee" and not contact_attack_available:
		melee_attack_unavailable_reason = "No hostile battlefield footprint is adjacent."
	if weapon_mode == &"melee":
		targets.clear()
		character_targets.clear()


func _finalize_legal_actions(game_state: GameState) -> void:
	legal_actions.append(&"finish")
	legal_actions.append(&"defend")
	if retreat_available:
		legal_actions.append(&"retreat")
	if auto_turn.enabled:
		legal_actions.append(&"auto")
	if delay.enabled:
		legal_actions.append(&"delay")
	if bandage.enabled:
		legal_actions.append(&"bandage")
	if turn_undead.enabled:
		legal_actions.append(&"turn_undead")
	if undo.enabled:
		legal_actions.append(&"undo")
	if game_state != null:
		auto_character_ids = game_state.combat_auto_character_ids()


func _populate_active_relationships(combat: CombatState, characters: Array[CharacterState]) -> void:
	if combat.battlefield == null:
		return
	for character: CharacterState in characters:
		if character.current_health <= 0 or not combat.battlefield.actors.has_actor(character.id):
			continue
		(friendly_actor_ids if not character.traitor else hostile_actor_ids).append(character.id)
	for monster: MonsterState in combat.roster.monsters():
		if monster.current_health <= 0 or not combat.battlefield.actors.has_actor(monster.id):
			continue
		(friendly_actor_ids if not monster.traitor else hostile_actor_ids).append(monster.id)


static func _is_hostile_target(combat: CombatState, characters: Array[CharacterState], actor: CharacterState, target_id: String) -> bool:
	if target_id.is_empty() or actor == null:
		return false
	var monster := combat.roster.monster_by_id(target_id)
	if monster != null:
		return monster.current_health > 0 and monster.traitor != actor.traitor
	for character: CharacterState in characters:
		if character.id == target_id:
			return character.current_health > 0 and character.traitor != actor.traitor
	return false


static func _target_name(combat: CombatState, characters: Array[CharacterState], target_id: String) -> String:
	var monster := combat.roster.monster_by_id(target_id)
	if monster != null:
		return monster.name
	for character: CharacterState in characters:
		if character.id == target_id:
			return character.name
	return target_id
