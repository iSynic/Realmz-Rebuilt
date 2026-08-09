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
var outcome: StringName
var turn_order: Array[String] = []
var legal_actions: Array[StringName] = []
var targets: Array[MonsterView] = []
var character_targets: Array[CharacterView] = []
var movement_options: Array[CombatMoveOptionView] = []
var monsters: Array[MonsterView] = []
var battlefield: BattlefieldView


func _init(combat: CombatState, characters: Array[CharacterState] = [], content: RealmzContent = null, inventory_rules: InventoryRules = null, battlefield_rules: BattlefieldRules = null) -> void:
	battle_id = combat.battle_id
	round_number = combat.round_number
	active_actor_id = combat.active_actor_id()
	outcome = combat.outcome
	turn_order = combat.turn_order()
	if combat.battlefield != null:
		battlefield = BattlefieldView.new(combat.battlefield)
	var adjacent_ids: Array[String] = []
	var hostile_ids: Dictionary = {}
	if combat.battlefield != null and battlefield_rules != null and not active_actor_id.is_empty():
		adjacent_ids = battlefield_rules.adjacent_actor_ids(combat.battlefield, active_actor_id)
	for monster: MonsterState in combat.monsters():
		if monster.current_health > 0 and monster.traitor:
			hostile_ids[monster.id] = true
	for character: CharacterState in characters:
		if character.current_health > 0 and character.traitor:
			hostile_ids[character.id] = true
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
		var equipment := inventory_rules.combat_equipment(active_character, content.item_definitions())
		if equipment.valid:
			weapon_mode = combat.character_weapon_mode(active_character.id)
			melee_weapon_id = equipment.melee_weapon.id if equipment.melee_weapon != null else ""
			missile_weapon_id = equipment.missile_weapon.id if equipment.missile_weapon != null else ""
			weapon_switch_available = weapon_mode == &"missile" or equipment.missile_weapon != null
			weapon_switch_target_mode = &"melee" if weapon_mode == &"missile" else &"missile"
			weapon_switch_unavailable_reason = "" if weapon_switch_available else "The active character has no equipped Classic type-15 missile weapon."
			if weapon_mode == &"melee" and (not targets.is_empty() or not character_targets.is_empty()):
				legal_actions.append(&"attack")
			elif weapon_mode == &"melee":
				melee_attack_unavailable_reason = "No hostile battlefield footprint is adjacent."
			else:
				ranged_attack_unavailable_reason = "Missile range, line of sight, and projectile resolution are not implemented yet."
			if weapon_switch_available:
				legal_actions.append(&"switch_weapon")
		else:
			equipment_error_reason = equipment.error_message
			weapon_switch_unavailable_reason = equipment.error_message
		if combat.battlefield != null and battlefield_rules != null:
			var map := content.world.map_by_id(combat.battlefield.map_id)
			var terrain_set := content.world.battle_terrain_set_by_id(map.battle_terrain_set_id) if map != null else null
			if terrain_set != null:
				var origin := combat.battlefield.character_position(active_character.id)
				for direction: Vector2i in BattlefieldRules.DIRECTIONS:
					var probe := battlefield_rules.probe_step(combat.battlefield, terrain_set, active_character.id, direction, active_character.movement)
					if probe.allowed:
						var before := battlefield_rules.adjacent_actor_ids(combat.battlefield, active_character.id).filter(func(actor_id: String) -> bool: return hostile_ids.has(actor_id))
						var after := battlefield_rules.adjacent_actor_ids(combat.battlefield, active_character.id, origin + direction).filter(func(actor_id: String) -> bool: return hostile_ids.has(actor_id))
						for actor_id: String in before:
							if not after.has(actor_id):
								probe = BattlefieldStepResult.blocked(&"withdrawal_attack_unavailable", probe.destination)
								break
						if probe.allowed and (not before.is_empty() or not after.is_empty()):
							probe = BattlefieldStepResult.blocked(&"guard_reaction_unavailable", probe.destination)
					movement_options.append(CombatMoveOptionView.new(direction, probe))
	legal_actions.append(&"defend")
	legal_actions.append(&"retreat")
