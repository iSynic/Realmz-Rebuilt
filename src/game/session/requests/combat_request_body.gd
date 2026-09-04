## Carries one detached combat command boundary for the active actor.

class_name CombatRequestBody
extends InteractionRequestBody

var battle_id: String
var round_number: int
var actor_id: String
var attack_units_remaining: int
var movement_remaining: int
var enemies_remaining: int
var actions: Array[String] = []
var weapon_mode: StringName
var weapon_switch: InteractionRequestValue.Availability
var ranged_attack: InteractionRequestValue.Availability
var retreat: InteractionRequestValue.Availability
var melee_attack_reason: String
var targets: Array[InteractionRequestValue.CombatTarget] = []
var combatants: Array[InteractionRequestValue.Combatant] = []
var movement: Array[InteractionRequestValue.MovementOption] = []
var spell_casts: Array[InteractionRequestValue.CastOption] = []
var spell_cast_reason: String
var fast_spells: Array[InteractionRequestValue.FastSpell] = []
var item_casts: Array[InteractionRequestValue.CastOption] = []
var item_cast_reason: String
var scroll_casts: Array[InteractionRequestValue.CastOption] = []
var scroll_cast_reason: String
var auto_turn: InteractionRequestValue.Availability
var auto_character_ids: Array[String] = []
var delay: InteractionRequestValue.Availability
var bandage: InteractionRequestValue.Availability
var bandage_targets: Array[InteractionRequestValue.CombatTarget] = []
var turn_undead: InteractionRequestValue.Availability
var turn_undead_targets: Array[InteractionRequestValue.CombatTarget] = []
var undo: InteractionRequestValue.Availability


func to_data() -> Dictionary:
	var bandage_data := bandage.to_data()
	bandage_data["targets"] = bandage_targets.map(func(value: InteractionRequestValue.CombatTarget) -> Dictionary: return value.to_data())
	var turn_data := turn_undead.to_data()
	turn_data["targets"] = turn_undead_targets.map(func(value: InteractionRequestValue.CombatTarget) -> Dictionary: return value.to_data())
	return {"battleId": battle_id, "round": round_number, "actorId": actor_id, "attackUnitsRemaining": attack_units_remaining, "movementRemaining": movement_remaining, "enemiesRemaining": enemies_remaining, "actions": actions.duplicate(), "weaponMode": String(weapon_mode), "weaponSwitch": weapon_switch.to_data(), "rangedAttack": ranged_attack.to_data(), "retreat": retreat.to_data(), "meleeAttackReason": melee_attack_reason, "targets": targets.map(func(value: InteractionRequestValue.CombatTarget) -> Dictionary: return value.to_data()), "combatants": combatants.map(func(value: InteractionRequestValue.Combatant) -> Dictionary: return value.to_data()), "movement": movement.map(func(value: InteractionRequestValue.MovementOption) -> Dictionary: return value.to_data()), "spellCasts": spell_casts.map(func(value: InteractionRequestValue.CastOption) -> Dictionary: return value.to_data()), "spellCastReason": spell_cast_reason, "fastSpells": fast_spells.map(func(value: InteractionRequestValue.FastSpell) -> Dictionary: return value.to_data()), "itemCasts": item_casts.map(func(value: InteractionRequestValue.CastOption) -> Dictionary: return value.to_data()), "itemCastReason": item_cast_reason, "scrollCasts": scroll_casts.map(func(value: InteractionRequestValue.CastOption) -> Dictionary: return value.to_data()), "scrollCastReason": scroll_cast_reason, "autoTurn": auto_turn.to_data(), "autoCharacterIds": auto_character_ids.duplicate(), "delay": delay.to_data(), "bandage": bandage_data, "turnUndead": turn_data, "undo": undo.to_data()}
