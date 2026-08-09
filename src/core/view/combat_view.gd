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
var equipment_error_reason: String = ""
var outcome: StringName
var turn_order: Array[String] = []
var legal_actions: Array[StringName] = []
var targets: Array[MonsterView] = []
var character_targets: Array[CharacterView] = []
var monsters: Array[MonsterView] = []


func _init(combat: CombatState, characters: Array[CharacterState] = [], content: RealmzContent = null, inventory_rules: InventoryRules = null) -> void:
	battle_id = combat.battle_id
	round_number = combat.round_number
	active_actor_id = combat.active_actor_id()
	outcome = combat.outcome
	turn_order = combat.turn_order()
	for monster: MonsterState in combat.monsters():
		var view := MonsterView.new(monster)
		monsters.append(view)
		if monster.current_health > 0 and monster.traitor:
			targets.append(view)
	for character: CharacterState in characters:
		if character.id == active_actor_id:
			attack_units_remaining = character.attacks_remaining
			movement_remaining = character.movement
		if character.current_health > 0 and character.traitor:
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
			if weapon_mode == &"melee":
				legal_actions.append(&"attack")
			else:
				ranged_attack_unavailable_reason = "Missile attacks require battle positions, range, and line-of-sight state that the session does not own yet."
			if weapon_switch_available:
				legal_actions.append(&"switch_weapon")
		else:
			equipment_error_reason = equipment.error_message
			weapon_switch_unavailable_reason = equipment.error_message
	legal_actions.append(&"defend")
	legal_actions.append(&"retreat")
