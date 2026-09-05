## Resolves deterministic character physical attacks and weapon effects.

class_name CombatCharacterAttackResolver
extends CombatAttackResolutionSupport

const AttackPolicy := preload("res://src/game/combat/combat_attack_policy.gd")


class CharacterMonsterAttackAttempt extends RefCounted:
	var condition_roll: Dictionary
	var chance: int
	var roll: int
	var hit: bool
	var fumble: Dictionary
	var type_damage: int


func resolve_character_attack(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, realmz_day: int = 0, behind: bool = false, allow_fumbles: bool = false, can_queue_fumble: bool = true) -> AttackResolution:
	if attacker == null or equipment == null or not equipment.valid or defender == null or defender_definition == null or rng == null:
		return null
	var attempt_value: Variant = _prepare_character_monster_attack(attacker, equipment, defender, defender_definition, rng, realmz_day, behind, allow_fumbles, can_queue_fumble)
	if attempt_value is AttackResolution:
		return attempt_value
	return _resolve_character_monster_hit(attacker, equipment, defender, defender_definition, rng, attempt_value)


func _prepare_character_monster_attack(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, realmz_day: int, behind: bool, allow_fumbles: bool, can_queue_fumble: bool) -> Variant:
	var invalid_weapon := AttackPolicy.invalid_weapon_reason(equipment.melee_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_character_attack(invalid_weapon)
	var condition_roll := _roll_weapon_condition_monster(equipment.melee_weapon, defender, defender_definition, rng)
	if condition_roll.get("blocked", false):
		return _blocked_character_attack(StringName(condition_roll.get("reason", "invalid_weapon_condition")))
	var attempt := CharacterMonsterAttackAttempt.new()
	attempt.condition_roll = condition_roll
	var chance := 50 + attacker.to_hit + (20 if behind else 0) + 5 * equipment.equipped_damage_bonus
	if equipment.melee_weapon != null and equipment.melee_weapon.special_1 == 121:
		chance += 5 * equipment.melee_weapon.damage_bonus
	chance += AttackPolicy.attacker_condition_modifier(attacker.conditions)
	if defender_definition.type_flag(4) and attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance += rng.draw_classic(equipment.effective_luck, &"combat.attack.luck")
	for index: int in 8:
		if defender_definition.type_flag(index):
			chance += 5 * attacker.special_value(index)
			attempt.type_damage += attacker.special_value(index)
	chance -= defender.armor
	chance += AttackPolicy.defender_condition_modifier(defender.conditions, true)
	chance -= int(float(maxi(0, realmz_day)) / 120.0)
	attempt.chance = maxi(5, chance)
	attempt.roll = rng.draw(100, &"combat.attack.hit")
	attempt.hit = attempt.roll <= attempt.chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	attempt.fumble = AttackPolicy.character_fumble(attacker, equipment, rng, allow_fumbles, can_queue_fumble)
	if attempt.fumble.get("fumbled", false):
		return AttackPolicy.fumbled_attack(attempt.chance, attempt.roll, int(attempt.fumble["roll"]))
	var magic_requirement := AttackPolicy.magic_weapon_requirement_reason(attacker, equipment, defender_definition, attempt.hit)
	if not magic_requirement.is_empty():
		return AttackPolicy.with_fumble_observation(_blocked_character_attack(magic_requirement, attempt.chance, attempt.roll), attempt.fumble)
	var weapon_requirement := AttackPolicy.required_weapon_reason(equipment, defender_definition, attempt.hit)
	if not weapon_requirement.is_empty():
		return AttackPolicy.with_fumble_observation(_blocked_character_attack(weapon_requirement, attempt.chance, attempt.roll), attempt.fumble)
	if equipment.melee_weapon != null and equipment.melee_weapon.special_1 == 120:
		attempt.hit = true
	if not attempt.hit:
		attacker.lifetime_record.add_damage_given(0, false, false)
		return AttackPolicy.with_fumble_observation(AttackResolution.new(false, false, attempt.chance, attempt.roll, 0), attempt.fumble)
	return attempt


func _resolve_character_monster_hit(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, attempt: CharacterMonsterAttackAttempt) -> AttackResolution:
	var reflected := defender.conditions.is_active(ConditionRules.REFLECTING_ATTACKS) and rng.draw(100, &"combat.attack.reflect") < 34
	var physical_damage := attempt.type_damage + equipment.effective_damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		physical_damage += 3
	var effects: Array[Dictionary] = []
	var elemental_damage := 0
	if equipment.is_armed():
		if reflected:
			elemental_damage = _roll_weapon_elements_character(equipment.melee_weapon, attacker, rng, effects)
		else:
			elemental_damage = _roll_weapon_elements_monster(equipment.melee_weapon, defender, defender_definition, rng, effects)
		physical_damage += AttackPolicy.roll_weapon_physical(equipment.melee_weapon, defender_definition if not reflected else null, rng)
	else:
		physical_damage += rng.draw(maxi(1, attacker.hand_to_hand), &"combat.attack.unarmed-damage")
	var critical_rolls: Array[int] = [rng.draw(100, &"combat.attack.sneak-critical"), rng.draw(100, &"combat.attack.major-wound-critical")]
	physical_damage = maxi(0, physical_damage)
	if not reflected and defender.conditions.is_active(ConditionRules.HELPLESS):
		physical_damage = defender.current_health
	elif reflected and attacker.conditions.is_active(ConditionRules.HELPLESS):
		physical_damage = attacker.current_health
	var total_damage := physical_damage + elemental_damage
	var resolution := AttackResolution.new(true, false, attempt.chance, attempt.roll, total_damage, reflected)
	AttackPolicy.with_fumble_observation(resolution, attempt.fumble)
	resolution.physical_damage = physical_damage
	resolution.weapon_effects = effects
	resolution.critical_rolls = critical_rolls
	if reflected:
		_apply_weapon_condition_character(attacker, attempt.condition_roll, resolution)
		attacker.current_health -= total_damage
		resolution.killed = attacker.current_health <= 0
		attacker.lifetime_record.add_damage_taken(total_damage, true)
		return resolution
	_apply_weapon_condition_monster(defender, attempt.condition_roll, resolution)
	defender.current_health -= total_damage
	resolution.killed = defender.current_health <= 0
	attacker.lifetime_record.add_damage_given(total_damage, true, resolution.killed)
	return resolution


func resolve_character_attack_character(attacker: CharacterState, attacker_equipment: CharacterCombatEquipment, defender: CharacterState, defender_equipment: CharacterCombatEquipment, rng: RealmzRng, behind: bool = false, allow_fumbles: bool = false, can_queue_fumble: bool = true) -> AttackResolution:
	if attacker == null or attacker_equipment == null or not attacker_equipment.valid or defender == null or defender_equipment == null or not defender_equipment.valid or rng == null:
		return null
	var invalid_weapon := AttackPolicy.invalid_weapon_reason(attacker_equipment.melee_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_character_attack(invalid_weapon)
	var condition_roll := _roll_weapon_condition_character(attacker_equipment.melee_weapon, defender, rng)
	if condition_roll.get("blocked", false):
		return _blocked_character_attack(StringName(condition_roll.get("reason", "invalid_weapon_condition")))
	var chance := 50 + attacker.to_hit + (20 if behind else 0) + 5 * attacker_equipment.equipped_damage_bonus
	if attacker_equipment.melee_weapon != null and attacker_equipment.melee_weapon.special_1 == 121:
		chance += 5 * attacker_equipment.melee_weapon.damage_bonus
	chance += AttackPolicy.attacker_condition_modifier(attacker.conditions)
	chance += rng.draw_classic(attacker_equipment.effective_luck, &"combat.attack.luck")
	chance -= defender_equipment.effective_armor
	chance += AttackPolicy.defender_condition_modifier(defender.conditions, false)
	chance = maxi(5, chance)
	var roll := rng.draw(100, &"combat.attack.hit")
	var hit := roll <= chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	var fumble := AttackPolicy.character_fumble(attacker, attacker_equipment, rng, allow_fumbles, can_queue_fumble)
	if fumble.get("fumbled", false):
		return AttackPolicy.fumbled_attack(chance, roll, int(fumble["roll"]))
	if attacker_equipment.melee_weapon != null and attacker_equipment.melee_weapon.special_1 == 120:
		hit = true
	if not hit:
		return AttackPolicy.with_fumble_observation(AttackResolution.new(false, false, chance, roll, 0), fumble)
	var reflected := defender.conditions.is_active(ConditionRules.REFLECTING_ATTACKS) and rng.draw(100, &"combat.attack.reflect") < 34
	var target := attacker if reflected else defender
	var physical_damage := attacker_equipment.effective_damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		physical_damage += 3
	var effects: Array[Dictionary] = []
	var elemental_damage := 0
	if attacker_equipment.is_armed():
		elemental_damage = _roll_weapon_elements_character(attacker_equipment.melee_weapon, target, rng, effects)
		physical_damage += AttackPolicy.roll_weapon_physical(attacker_equipment.melee_weapon, null, rng)
	else:
		physical_damage += rng.draw(maxi(1, attacker.hand_to_hand), &"combat.attack.unarmed-damage")
	var critical_rolls: Array[int] = [rng.draw(100, &"combat.attack.sneak-critical"), rng.draw(100, &"combat.attack.major-wound-critical")]
	physical_damage = maxi(0, physical_damage)
	if target.conditions.is_active(ConditionRules.HELPLESS):
		physical_damage = target.current_health
	var total_damage := physical_damage + elemental_damage
	var resolution := AttackResolution.new(true, false, chance, roll, total_damage, reflected)
	AttackPolicy.with_fumble_observation(resolution, fumble)
	resolution.physical_damage = physical_damage
	resolution.weapon_effects = effects
	resolution.critical_rolls = critical_rolls
	_apply_weapon_condition_character(target, condition_roll, resolution)
	target.current_health -= total_damage
	resolution.killed = target.current_health <= 0
	target.lifetime_record.add_damage_taken_without_hit(total_damage)
	return resolution


static func _blocked_character_attack(reason: StringName, chance: int = 0, roll: int = 0) -> AttackResolution:
	var resolution := AttackResolution.new(false, false, chance, roll, 0)
	resolution.blocked = true
	resolution.block_reason = reason
	return resolution
