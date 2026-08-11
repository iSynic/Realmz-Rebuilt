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
var legal_actions: Array[StringName] = []
var targets: Array[MonsterView] = []
var character_targets: Array[CharacterView] = []
var movement_options: Array[CombatMoveOptionView] = []
var monsters: Array[MonsterView] = []
var battlefield: BattlefieldView


func _init(combat: CombatState, characters: Array[CharacterState] = [], content: RealmzContent = null, inventory_rules: InventoryRules = null, battlefield_rules: BattlefieldRules = null, combat_flow: CombatFlow = null) -> void:
	battle_id = combat.battle_id
	round_number = combat.round_number
	active_actor_id = combat.active_actor_id()
	outcome = combat.outcome
	turn_order = combat.turn_order()
	if combat.battlefield != null:
		var upper_tileset_id := ""
		if content != null:
			var source_map := content.world.map_by_id(combat.battlefield.map_id)
			if source_map != null and source_map.level_type == &"land" and source_map.landlook >= 0:
				upper_tileset_id = "landlook-%d" % source_map.landlook
		battlefield = BattlefieldView.new(combat.battlefield, upper_tileset_id)
	var adjacent_ids: Array[String] = []
	if combat.battlefield != null and battlefield_rules != null and not active_actor_id.is_empty():
		adjacent_ids = battlefield_rules.adjacent_actor_ids(combat.battlefield, active_actor_id)
	for monster: MonsterState in combat.monsters():
		var view := MonsterView.new(monster)
		monsters.append(view)
		if monster.current_health > 0 and monster.traitor and adjacent_ids.has(monster.id):
			targets.append(view)
	for character: CharacterState in characters:
		if character.id == active_actor_id:
			attack_units_remaining = character.attacks_remaining
			movement_remaining = character.movement
		if character.current_health > 0 and character.traitor and adjacent_ids.has(character.id):
			character_targets.append(CharacterView.new(character, content))
	if combat.completed:
		return
	var active_character: CharacterState = null
	for character: CharacterState in characters:
		if character.id == active_actor_id:
			active_character = character
			break
	if active_character != null and content != null and inventory_rules != null:
		if combat_flow != null:
			var retreat_probe: Variant = combat_flow.probe_character_retreat(combat, characters, active_character.id)
			retreat_available = retreat_probe.allowed
			retreat_unavailable_reason = retreat_probe.reason_text
			nearest_enemy_range = retreat_probe.nearest_enemy_range
		var equipment := inventory_rules.combat_equipment(active_character, content.item_definitions())
		if equipment.valid:
			weapon_mode = combat.character_weapon_mode(active_character.id)
			melee_weapon_id = equipment.melee_weapon.id if equipment.melee_weapon != null else ""
			missile_weapon_id = equipment.missile_weapon.id if equipment.missile_weapon != null else ""
			weapon_switch_available = weapon_mode == &"missile" or equipment.missile_weapon != null
			weapon_switch_target_mode = &"melee" if weapon_mode == &"missile" else &"missile"
			weapon_switch_unavailable_reason = "" if weapon_switch_available else "The active character has no equipped Classic type-15 missile weapon."
			if weapon_mode != &"melee":
				targets.clear()
				character_targets.clear()
				var profile := combat_flow.character_projectile_profile(active_character, content, equipment) if combat_flow != null else null
				if profile == null or not profile.available:
					ranged_attack_unavailable_reason = profile.error_message if profile != null else "Projectile rules are unavailable."
				else:
					for monster: MonsterState in combat.monsters():
						if monster.current_health > 0 and monster.traitor != active_character.traitor and combat_flow.projectile_target_is_valid(combat, content, active_character.id, monster.id, profile.maximum_range, profile.spell.range_min + profile.spell.range_max > 0):
							targets.append(MonsterView.new(monster))
					if targets.is_empty():
						ranged_attack_unavailable_reason = "No hostile monster is within the projectile's Classic range and line of sight."
					else:
						legal_actions.append(&"attack")
			if weapon_switch_available:
				legal_actions.append(&"switch_weapon")
		else:
			equipment_error_reason = equipment.error_message
			weapon_switch_unavailable_reason = equipment.error_message
		if combat.battlefield != null and battlefield_rules != null:
			var map := content.world.map_by_id(combat.battlefield.map_id)
			var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
			if terrain_set != null:
				var contact_attack_available := false
				for direction: Vector2i in BattlefieldRules.DIRECTIONS:
					var destination := combat.battlefield.actor_position(active_character.id) + direction
					var edge_retreat: Variant = combat_flow.probe_edge_retreat(combat, active_character.id, destination) if combat_flow != null else null
					var probe := battlefield_rules.probe_step(combat.battlefield, terrain_set, active_character.id, direction, active_character.movement)
					var contact_target_id := ""
					var contact_target_name := ""
					if weapon_mode == &"melee" and probe.reason == &"occupied" and _is_hostile_target(combat, characters, active_character, probe.occupant_id):
						contact_target_id = probe.occupant_id
						contact_target_name = _target_name(combat, characters, contact_target_id)
						contact_attack_available = true
					movement_options.append(CombatMoveOptionView.new(direction, probe, edge_retreat != null and edge_retreat.allowed, edge_retreat != null and edge_retreat.forced, contact_target_id, contact_target_name))
				if weapon_mode == &"melee" and not contact_attack_available:
					melee_attack_unavailable_reason = "No hostile battlefield footprint is adjacent."
				if weapon_mode == &"melee":
					targets.clear()
					character_targets.clear()
	legal_actions.append(&"finish")
	legal_actions.append(&"defend")
	if retreat_available:
		legal_actions.append(&"retreat")


static func _is_hostile_target(combat: CombatState, characters: Array[CharacterState], actor: CharacterState, target_id: String) -> bool:
	if target_id.is_empty() or actor == null:
		return false
	var monster := combat.monster_by_id(target_id)
	if monster != null:
		return monster.current_health > 0 and monster.traitor != actor.traitor
	for character: CharacterState in characters:
		if character.id == target_id:
			return character.current_health > 0 and character.traitor != actor.traitor
	return false


static func _target_name(combat: CombatState, characters: Array[CharacterState], target_id: String) -> String:
	var monster := combat.monster_by_id(target_id)
	if monster != null:
		return monster.name
	for character: CharacterState in characters:
		if character.id == target_id:
			return character.name
	return target_id
