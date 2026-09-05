## Resolves deterministic monster physical attacks and authored attack specials.

class_name CombatMonsterAttackResolver
extends CombatAttackResolutionSupport

const AttackPolicy := preload("res://src/game/combat/combat_attack_policy.gd")

var _characters: CharacterRules


class MonsterAttackAttempt extends RefCounted:
	var context: MonsterAttackContext
	var condition_roll: Dictionary
	var chance: int
	var roll: int
	var helpless: bool
	var fumble_roll: int
	var attack: MonsterAttackDefinition


class MonsterDamageRoll extends RefCounted:
	var physical: int
	var elemental: int
	var effects: Array[Dictionary] = []
	var physical_reduction: int


func _init(character_rules: CharacterRules) -> void:
	_characters = character_rules


func resolve_monster_attack(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng, charm_save_bonus: int = 0, context: MonsterAttackContext = null, allow_fumbles: bool = false) -> AttackResolution:
	if attacker == null or attacker_definition == null or defender == null or rng == null:
		return null
	var attempt_value: Variant = _prepare_character_target_attempt(attacker, attacker_definition, attack_index, defender, rng, context, allow_fumbles)
	if attempt_value is AttackResolution:
		return attempt_value
	return _resolve_character_target_hit(attacker, attacker_definition, defender, race, caste, rng, charm_save_bonus, attempt_value)


func _prepare_character_target_attempt(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: CharacterState, rng: RealmzRng, context: MonsterAttackContext, allow_fumbles: bool) -> Variant:
	var attempt := MonsterAttackAttempt.new()
	attempt.context = context if context != null else MonsterAttackContext.new(null, 0, false, defender.luck)
	var invalid_weapon := AttackPolicy.invalid_weapon_reason(attempt.context.attacker_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_monster_attack(invalid_weapon)
	attempt.condition_roll = _roll_weapon_condition_character(attempt.context.attacker_weapon, defender, rng)
	if attempt.condition_roll.get("blocked", false):
		return _blocked_monster_attack(StringName(attempt.condition_roll.get("reason", "invalid_weapon_condition")))
	var chance := _monster_attack_base_chance(attacker, attacker_definition, attempt.context)
	chance += AttackPolicy.attacker_condition_modifier(attacker.conditions)
	if attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance -= rng.draw_classic(attempt.context.defender_luck, &"combat.monster-attack.defender-luck")
	chance -= attempt.context.defender_armor if attempt.context.defender_armor >= 0 else defender.armor
	chance += AttackPolicy.defender_condition_modifier(defender.conditions, false)
	if attacker_definition.type_flag(4) and defender.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance -= 10
	attempt.chance = maxi(10, chance)
	attempt.roll = rng.draw(100, &"combat.monster-attack.hit")
	var hit := attempt.roll <= attempt.chance or _monster_weapon_auto_hits(attempt.context.attacker_weapon)
	attempt.helpless = defender.conditions.is_active(ConditionRules.HELPLESS)
	hit = hit or attempt.helpless
	attempt.fumble_roll = _monster_fumble_roll(attacker, rng, allow_fumbles)
	if _monster_fumbled(attempt.context.attacker_weapon, attempt.fumble_roll):
		return AttackPolicy.fumbled_attack(attempt.chance, attempt.roll, attempt.fumble_roll)
	if not hit:
		defender.lifetime_record.add_damage_taken(0, false)
		return _with_monster_fumble_roll(AttackResolution.new(false, false, attempt.chance, attempt.roll, 0), attempt.fumble_roll)
	attempt.attack = _monster_attack_row(attacker_definition.attacks(), attack_index)
	return attempt


func _resolve_character_target_hit(attacker: MonsterState, attacker_definition: MonsterDefinition, defender: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng, charm_save_bonus: int, attempt: MonsterAttackAttempt) -> AttackResolution:
	var damage := _roll_character_target_damage(attacker, attacker_definition, defender, rng, attempt)
	var resolution := AttackResolution.new(true, defender.current_health - damage.physical - damage.elemental <= 0, attempt.chance, attempt.roll, damage.physical + damage.elemental)
	_with_monster_fumble_roll(resolution, attempt.fumble_roll)
	resolution.physical_damage = damage.physical
	resolution.physical_damage_reduction = damage.physical_reduction
	resolution.physical_feedback_sound_id = 694 if damage.physical_reduction > 0 else 0
	resolution.weapon_effects = damage.effects
	if attempt.attack.special != 0:
		resolution.special_code = attempt.attack.special
		var potency_low := int(float(attacker.hit_dice) / 2.0)
		resolution.special_potency = maxi(1, rng.draw_between(potency_low, attacker.hit_dice, &"combat.monster-attack.special-potency"))
	_apply_character_target_special(resolution, attempt.attack, attacker, defender, race, caste, rng, charm_save_bonus)
	resolution.damage_deferred = resolution.aging != null and resolution.aging.changed_group()
	if resolution.damage_deferred:
		_record_weapon_condition_character(defender, attempt.condition_roll, resolution)
	else:
		_apply_weapon_condition_character(defender, attempt.condition_roll, resolution)
	if not resolution.damage_deferred and not resolution.physical_damage_skipped:
		defender.current_health -= damage.physical + damage.elemental + resolution.special_damage_amount
		resolution.killed = defender.current_health <= 0
	defender.lifetime_record.add_damage_taken(resolution.total_damage(), true)
	return resolution


func _roll_character_target_damage(attacker: MonsterState, attacker_definition: MonsterDefinition, defender: CharacterState, rng: RealmzRng, attempt: MonsterAttackAttempt) -> MonsterDamageRoll:
	var result := MonsterDamageRoll.new()
	var damage := attacker_definition.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	if attempt.helpless:
		damage = defender.current_health + rng.draw(10, &"combat.monster-attack.helpless-damage")
	elif attempt.context.attacker_weapon != null:
		damage += attempt.context.attacker_weapon.damage_bonus
		damage += rng.draw(maxi(1, attempt.context.attacker_weapon.vs_small), &"combat.monster-attack.weapon-physical")
		result.elemental = _roll_weapon_elements_character(attempt.context.attacker_weapon, defender, rng, result.effects)
	else:
		damage += rng.draw_between(attempt.attack.damage_min, attempt.attack.damage_max, &"combat.monster-attack.damage")
	damage = maxi(0, damage)
	if attempt.context.party_dragon_hide and damage > 1:
		var damage_before_dragon_hide := damage
		damage = maxi(1, damage - 5)
		result.physical_reduction = damage_before_dragon_hide - damage
	result.physical = damage
	return result


func _apply_character_target_special(resolution: AttackResolution, attack: MonsterAttackDefinition, attacker: MonsterState, defender: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng, charm_save_bonus: int) -> void:
	if _is_status_special(attack.special):
		_apply_party_status_special(resolution, defender, rng)
	elif _is_resource_special(attack.special):
		_apply_party_resource_special(resolution, attacker, defender, rng)
	elif attack.special == 10:
		_apply_party_charm_special(resolution, attacker, defender, rng, charm_save_bonus)
	elif _is_elemental_special(attack.special):
		_apply_party_elemental_special(resolution, attack, defender, rng)
	elif attack.special == 17:
		resolution.special_handled = true
		resolution.special_save_index = 7
		resolution.special_save_chance = defender.save_value(7)
		resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
		resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
		if not resolution.special_saved:
			resolution.special_applied = true
			var age_factor := AttackPolicy.signed_16(attack.damage_max * attacker.hit_dice)
			resolution.special_age_days = int(float(race.max_age) * 0.01 * float(age_factor)) if race != null else 0
			if race != null and caste != null:
				resolution.aging = _characters.advance_age_days(defender, race, caste, resolution.special_age_days)
	elif attack.special in [18, 19]:
		_apply_party_permanent_affliction(resolution, defender, rng)


func resolve_monster_attack_monster(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, context: MonsterAttackContext = null, allow_fumbles: bool = false) -> AttackResolution:
	if attacker == null or attacker_definition == null or defender == null or defender_definition == null or rng == null:
		return null
	var attempt_value: Variant = _prepare_monster_target_attempt(attacker, attacker_definition, attack_index, defender, defender_definition, rng, context, allow_fumbles)
	if attempt_value is AttackResolution:
		return attempt_value
	return _resolve_monster_target_hit(attacker, attacker_definition, defender, defender_definition, rng, attempt_value)


func _prepare_monster_target_attempt(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, context: MonsterAttackContext, allow_fumbles: bool) -> Variant:
	var attempt := MonsterAttackAttempt.new()
	attempt.context = context if context != null else MonsterAttackContext.new()
	var invalid_weapon := AttackPolicy.invalid_weapon_reason(attempt.context.attacker_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_monster_attack(invalid_weapon)
	attempt.condition_roll = _roll_weapon_condition_monster(attempt.context.attacker_weapon, defender, defender_definition, rng)
	if attempt.condition_roll.get("blocked", false):
		return _blocked_monster_attack(StringName(attempt.condition_roll.get("reason", "invalid_weapon_condition")))
	var chance := _monster_attack_base_chance(attacker, attacker_definition, attempt.context)
	chance += AttackPolicy.attacker_condition_modifier(attacker.conditions)
	if attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance -= defender.armor
	chance += AttackPolicy.defender_condition_modifier(defender.conditions, false)
	if attacker_definition.type_flag(4) and defender.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance -= 10
	attempt.chance = maxi(10, chance)
	attempt.roll = rng.draw(100, &"combat.monster-attack.hit")
	var hit := attempt.roll <= attempt.chance or _monster_weapon_auto_hits(attempt.context.attacker_weapon)
	attempt.helpless = defender.conditions.is_active(ConditionRules.HELPLESS)
	hit = hit or attempt.helpless
	attempt.fumble_roll = _monster_fumble_roll(attacker, rng, allow_fumbles)
	if _monster_fumbled(attempt.context.attacker_weapon, attempt.fumble_roll):
		return AttackPolicy.fumbled_attack(attempt.chance, attempt.roll, attempt.fumble_roll)
	if not hit:
		return _with_monster_fumble_roll(AttackResolution.new(false, false, attempt.chance, attempt.roll, 0), attempt.fumble_roll)
	var weapon_requirement := _monster_required_weapon_reason(attempt.context.attacker_weapon, defender_definition)
	if not weapon_requirement.is_empty():
		return _with_monster_fumble_roll(_blocked_monster_attack(weapon_requirement, attempt.chance, attempt.roll), attempt.fumble_roll)
	attempt.attack = _monster_attack_row(attacker_definition.attacks(), attack_index)
	return attempt


func _resolve_monster_target_hit(attacker: MonsterState, attacker_definition: MonsterDefinition, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, attempt: MonsterAttackAttempt) -> AttackResolution:
	var damage := _roll_monster_target_damage(attacker, attacker_definition, defender, defender_definition, rng, attempt)
	var resolution := AttackResolution.new(true, defender.current_health - damage.physical - damage.elemental <= 0, attempt.chance, attempt.roll, damage.physical + damage.elemental)
	_with_monster_fumble_roll(resolution, attempt.fumble_roll)
	resolution.physical_damage = damage.physical
	resolution.weapon_effects = damage.effects
	if attempt.attack.special != 0 and _prepare_monster_special(resolution, attempt.attack.special, attacker, defender, rng):
		return resolution
	_apply_monster_target_special(resolution, attempt.attack, attacker, defender, defender_definition, rng)
	_apply_weapon_condition_monster(defender, attempt.condition_roll, resolution)
	if not resolution.physical_damage_skipped:
		defender.current_health -= damage.physical + damage.elemental + resolution.special_damage_amount
		resolution.killed = defender.current_health <= 0
	return resolution


func _roll_monster_target_damage(attacker: MonsterState, attacker_definition: MonsterDefinition, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, attempt: MonsterAttackAttempt) -> MonsterDamageRoll:
	var result := MonsterDamageRoll.new()
	var damage := attacker_definition.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	if attempt.helpless:
		damage = defender.current_health
	elif attempt.context.attacker_weapon != null:
		damage += attempt.context.attacker_weapon.damage_bonus
		damage += rng.draw(maxi(1, attempt.context.attacker_weapon.vs_small), &"combat.monster-attack.weapon-physical")
		result.elemental = _roll_weapon_elements_monster(attempt.context.attacker_weapon, defender, defender_definition, rng, result.effects)
		result.elemental += _roll_monster_weapon_type_damage(attempt.context.attacker_weapon, defender_definition, rng, result.effects)
	else:
		damage += rng.draw_between(attempt.attack.damage_min, attempt.attack.damage_max, &"combat.monster-attack.damage")
	result.physical = maxi(0, damage)
	return result


func _apply_monster_target_special(resolution: AttackResolution, attack: MonsterAttackDefinition, attacker: MonsterState, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	if _is_status_special(attack.special):
		_apply_monster_status_special(resolution, defender, defender_definition, rng)
	elif attack.special == 8:
		_apply_monster_spell_drain(resolution, attacker, defender, defender_definition, rng)
	elif attack.special == 9:
		resolution.special_blocked = true
		resolution.special_block_reason = &"party_target_only"
	elif attack.special == 10:
		_apply_monster_charm_special(resolution, attacker, defender, defender_definition, rng)
	elif _is_elemental_special(attack.special):
		_apply_monster_elemental_special(resolution, attack, defender, defender_definition, rng)
	elif attack.special == 17:
		resolution.special_handled = true
	elif attack.special in [18, 19]:
		_apply_monster_permanent_affliction(resolution, defender, defender_definition, rng)


func _prepare_monster_special(resolution: AttackResolution, special: int, attacker: MonsterState, defender: MonsterState, rng: RealmzRng) -> bool:
	resolution.special_code = special
	var potency_low := int(float(attacker.hit_dice) / 2.0)
	resolution.special_potency = maxi(1, rng.draw_between(potency_low, attacker.hit_dice, &"combat.monster-attack.special-potency"))
	if _is_status_special(special):
		resolution.special_handled = true
		resolution.special_save_index = _status_save_index(special)
		resolution.special_condition_index = _status_condition_index(special)
		resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
		resolution.special_condition_after = resolution.special_condition_before
	elif _is_resource_special(special):
		resolution.special_handled = true
		resolution.special_save_index = _resource_save_index(special)
		resolution.special_resource = &"spell_points" if special == 8 else &"experience"
	elif special == 17:
		resolution.special_handled = true
	elif special == 10:
		resolution.special_handled = true
		resolution.special_save_index = 0
		resolution.special_allegiance_before = defender.traitor
		resolution.special_allegiance_after = defender.traitor
	elif _is_elemental_special(special):
		resolution.special_handled = true
		resolution.special_save_index = special - 10
		resolution.special_condition_index = _elemental_condition_index(special)
		resolution.special_element = _elemental_name(special)
	elif special in [18, 19]:
		resolution.special_handled = true
		resolution.special_save_index = 7
		resolution.special_condition_index = ConditionRules.BLIND if special == 18 else ConditionRules.TURNED_TO_STONE
	if defender.magic_resistance <= 100:
		return false
	resolution.special_blocked = true
	resolution.special_block_reason = &"magic_resistance"
	resolution.hit = false
	resolution.damage = 0
	resolution.killed = false
	return true


static func _blocked_monster_attack(reason: StringName, chance: int = 0, roll: int = 0) -> AttackResolution:
	var resolution := AttackResolution.new(false, false, chance, roll, 0)
	resolution.blocked = true
	resolution.block_reason = reason
	return resolution


static func _monster_fumble_roll(attacker: MonsterState, rng: RealmzRng, allow_fumbles: bool) -> int:
	return rng.draw(600 + 50 * attacker.hit_dice, &"combat.monster-attack.fumble") if allow_fumbles else 0


static func _monster_fumbled(weapon: ItemDefinition, roll: int) -> bool:
	return weapon != null and roll > 20 and roll < 35


static func _with_monster_fumble_roll(resolution: AttackResolution, roll: int) -> AttackResolution:
	if resolution != null:
		resolution.fumble_roll = roll
	return resolution


static func _monster_attack_base_chance(attacker: MonsterState, definition: MonsterDefinition, context: MonsterAttackContext) -> int:
	var chance := 50 + 5 * attacker.hit_dice + 5 * definition.damage_bonus
	chance += 20 if context.behind else 0
	chance += int(float(context.realmz_day) / 70.0)
	if context.attacker_weapon != null:
		chance += 5 * context.attacker_weapon.damage_bonus
		if context.attacker_weapon.special_1 == 121:
			chance += 5 * context.attacker_weapon.damage_bonus
	return chance


static func _monster_weapon_auto_hits(weapon: ItemDefinition) -> bool:
	return weapon != null and weapon.special_1 == 120


static func _monster_attack_row(attacks: Array[MonsterAttackDefinition], attack_index: int) -> MonsterAttackDefinition:
	if attacks.is_empty():
		return MonsterAttackDefinition.new(1, 1)
	var selected := attacks[clampi(attack_index, 0, attacks.size() - 1)]
	if selected.damage_min == 0:
		return attacks[0]
	return selected


static func _monster_required_weapon_reason(weapon: ItemDefinition, defender: MonsterDefinition) -> StringName:
	if defender.required_weapon == 0:
		return &""
	if weapon == null:
		if defender.required_weapon == -1:
			return &"classic_blunt_weapon_required"
		if defender.required_weapon == -2:
			return &"classic_sharp_weapon_required"
		return &"classic_specific_weapon_required"
	if defender.required_weapon == -1:
		return &"" if weapon.blunt == -1 else &"classic_blunt_weapon_required"
	if defender.required_weapon == -2:
		return &"" if weapon.blunt == -2 else &"classic_sharp_weapon_required"
	var required_item_id := defender.required_weapon & 0xff
	return &"" if weapon.classic_id == required_item_id else &"classic_specific_weapon_required"


static func _roll_monster_weapon_type_damage(weapon: ItemDefinition, defender: MonsterDefinition, rng: RealmzRng, effects: Array[Dictionary]) -> int:
	var total := 0
	var ranges: Array[int] = [weapon.vs_undead, weapon.vs_demon_devil, weapon.vs_evil]
	var names: Array[StringName] = [&"undead", &"demon-devil", &"evil"]
	var flags: Array[int] = [1, 2, 4]
	for index: int in 3:
		if ranges[index] == 0 or not defender.type_flag(flags[index]):
			continue
		var amount := rng.draw(ranges[index], StringName("combat.monster-attack.weapon-versus-%s" % names[index]))
		effects.append({"targetType": String(names[index]), "amount": amount})
		total += amount
	return total


func _apply_party_charm_special(resolution: AttackResolution, attacker: MonsterState, defender: CharacterState, rng: RealmzRng, save_bonus: int) -> void:
	resolution.special_handled = true
	resolution.special_save_index = 0
	resolution.special_save_chance = defender.save_value(0) + save_bonus
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	resolution.special_allegiance_before = defender.traitor
	resolution.special_allegiance_after = defender.traitor
	if resolution.special_saved:
		return
	defender.traitor = attacker.traitor
	resolution.special_allegiance_after = defender.traitor
	resolution.special_applied = resolution.special_allegiance_after != resolution.special_allegiance_before
	# Castle reports party charm only while incrementing the original loyal-party count.
	resolution.special_announced = not resolution.special_allegiance_before


func _apply_monster_charm_special(resolution: AttackResolution, attacker: MonsterState, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = 0
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender, defender_definition, 0)
	resolution.special_saved = _monster_saved(defender, defender_definition, 0, resolution.special_save_roll, resolution.special_save_chance)
	resolution.special_allegiance_before = defender.traitor
	resolution.special_allegiance_after = defender.traitor
	if resolution.special_saved:
		return
	defender.traitor = attacker.traitor
	resolution.special_allegiance_after = defender.traitor
	resolution.special_applied = resolution.special_allegiance_after != resolution.special_allegiance_before
	resolution.special_announced = true


func _apply_party_elemental_special(resolution: AttackResolution, attack: MonsterAttackDefinition, defender: CharacterState, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = resolution.special_code - 10
	resolution.special_condition_index = _elemental_condition_index(resolution.special_code)
	resolution.special_element = _elemental_name(resolution.special_code)
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_damage_rolled = rng.draw(maxi(1, attack.damage_max), &"combat.monster-attack.special-damage")
	resolution.special_save_chance = defender.save_value(resolution.special_save_index)
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	var effective := resolution.special_damage_rolled
	if resolution.special_saved:
		effective = int(float(effective) / 2.0)
	if defender.conditions.is_active(resolution.special_condition_index):
		effective = int(float(effective) / 2.0)
	resolution.special_amount = effective
	resolution.special_damage_amount = effective
	resolution.special_display_amount = effective
	resolution.special_applied = effective != 0
	resolution.special_announced = effective != 0


func _apply_monster_elemental_special(resolution: AttackResolution, attack: MonsterAttackDefinition, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = resolution.special_code - 10
	resolution.special_condition_index = _elemental_condition_index(resolution.special_code)
	resolution.special_element = _elemental_name(resolution.special_code)
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_damage_rolled = rng.draw(maxi(1, attack.damage_max), &"combat.monster-attack.special-damage")
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender, defender_definition, resolution.special_save_index)
	resolution.special_saved = _monster_saved(defender, defender_definition, resolution.special_save_index, resolution.special_save_roll, resolution.special_save_chance)
	var after_save := resolution.special_damage_rolled
	if resolution.special_saved:
		after_save = int(float(after_save) / 2.0)
	var displayed := after_save
	if defender.conditions.is_active(resolution.special_condition_index):
		displayed = int(float(displayed) / 2.0)
	# FD-COMBAT-001 corrects Castle's monster-target copy/paste ordering so protection
	# changes committed damage as well as the number reported to the player.
	resolution.special_amount = displayed
	resolution.special_damage_amount = displayed
	resolution.special_display_amount = displayed
	resolution.special_applied = resolution.special_amount != 0
	resolution.special_announced = displayed != 0


func _apply_party_permanent_affliction(resolution: AttackResolution, defender: CharacterState, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = 7
	resolution.special_condition_index = ConditionRules.BLIND if resolution.special_code == 18 else ConditionRules.TURNED_TO_STONE
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_save_chance = defender.save_value(7)
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	if resolution.special_saved:
		return
	resolution.special_condition_after = -1
	defender.conditions.set_value(resolution.special_condition_index, -1)
	resolution.special_applied = resolution.special_condition_after != resolution.special_condition_before
	resolution.special_announced = true
	if resolution.special_code == 19:
		resolution.special_target_before = defender.current_health
		defender.current_health = 0
		resolution.special_target_after = 0
		resolution.physical_damage_skipped = true
		resolution.killed = true


func _apply_monster_permanent_affliction(resolution: AttackResolution, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = 7
	resolution.special_condition_index = ConditionRules.BLIND if resolution.special_code == 18 else ConditionRules.TURNED_TO_STONE
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender, defender_definition, 7)
	resolution.special_saved = _monster_saved(defender, defender_definition, 7, resolution.special_save_roll, resolution.special_save_chance)
	if resolution.special_saved:
		return
	var sentinel := -1 if resolution.special_code == 18 else 1
	resolution.special_condition_after = sentinel
	defender.conditions.set_value(resolution.special_condition_index, sentinel)
	resolution.special_applied = resolution.special_condition_after != resolution.special_condition_before
	resolution.special_announced = true
	if resolution.special_code == 19:
		resolution.special_target_before = defender.current_health
		defender.current_health = 0
		resolution.special_target_after = 0
		resolution.physical_damage_skipped = true
		resolution.killed = true


func _apply_party_status_special(resolution: AttackResolution, defender: CharacterState, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = _status_save_index(resolution.special_code)
	resolution.special_condition_index = _status_condition_index(resolution.special_code)
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_save_chance = defender.save_value(resolution.special_save_index)
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	if resolution.special_saved:
		return
	if resolution.special_condition_before < 0:
		resolution.special_blocked = true
		resolution.special_block_reason = &"permanent_condition"
		return
	resolution.special_announced = true
	resolution.special_sound_id = 630
	if resolution.special_condition_before >= 30:
		resolution.special_blocked = true
		resolution.special_block_reason = &"party_condition_cap"
		return
	resolution.special_condition_after = AttackPolicy.signed_16(resolution.special_condition_before + absi(resolution.special_potency))
	defender.conditions.set_value(resolution.special_condition_index, resolution.special_condition_after)
	resolution.special_applied = resolution.special_condition_after != resolution.special_condition_before


func _apply_monster_status_special(resolution: AttackResolution, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = _status_save_index(resolution.special_code)
	resolution.special_condition_index = _status_condition_index(resolution.special_code)
	resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
	resolution.special_condition_after = resolution.special_condition_before
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender, defender_definition, resolution.special_save_index)
	resolution.special_saved = _monster_saved(defender, defender_definition, resolution.special_save_index, resolution.special_save_roll, resolution.special_save_chance)
	if resolution.special_saved:
		return
	if resolution.special_condition_before < 0:
		resolution.special_blocked = true
		resolution.special_block_reason = &"permanent_condition"
		return
	resolution.special_condition_after = AttackPolicy.signed_16(resolution.special_condition_before + absi(resolution.special_potency))
	defender.conditions.set_value(resolution.special_condition_index, resolution.special_condition_after)
	resolution.special_applied = resolution.special_condition_after != resolution.special_condition_before
	resolution.special_announced = true
	resolution.special_sound_id = 684 if resolution.special_code == 16 else 630


func _apply_party_resource_special(resolution: AttackResolution, attacker: MonsterState, defender: CharacterState, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = _resource_save_index(resolution.special_code)
	resolution.special_resource = &"spell_points" if resolution.special_code == 8 else &"experience"
	resolution.special_save_chance = defender.save_value(resolution.special_save_index)
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_saved = resolution.special_save_roll <= resolution.special_save_chance
	if resolution.special_code == 8:
		resolution.special_target_before = defender.spell_points
		resolution.special_target_after = defender.spell_points
		resolution.special_actor_before = attacker.spell_points
		resolution.special_actor_after = attacker.spell_points
	else:
		resolution.special_target_before = defender.experience
		resolution.special_target_after = defender.experience
	if resolution.special_saved:
		return
	if resolution.special_code == 8:
		if defender.spell_points == 0:
			return
		var drained := attacker.hit_dice * 3
		if drained > defender.spell_points:
			drained = defender.spell_points
		defender.spell_points = AttackPolicy.signed_16(defender.spell_points - drained)
		attacker.spell_points = AttackPolicy.signed_16(attacker.spell_points + drained)
		resolution.special_amount = drained
		resolution.special_target_after = defender.spell_points
		resolution.special_actor_after = attacker.spell_points
		resolution.special_applied = drained != 0
		resolution.special_announced = resolution.special_applied
		return
	var removed := attacker.maximum_health * 20
	defender.experience = AttackPolicy.signed_32(defender.experience - removed)
	resolution.special_amount = removed
	resolution.special_target_after = defender.experience
	resolution.special_applied = removed != 0
	resolution.special_announced = true
	resolution.special_sound_id = 630


func _apply_monster_spell_drain(resolution: AttackResolution, attacker: MonsterState, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> void:
	resolution.special_handled = true
	resolution.special_save_index = 6
	resolution.special_resource = &"spell_points"
	resolution.special_target_before = defender.spell_points
	resolution.special_target_after = defender.spell_points
	resolution.special_actor_before = attacker.spell_points
	resolution.special_actor_after = attacker.spell_points
	resolution.special_save_roll = rng.draw(100, &"combat.monster-attack.special-save")
	resolution.special_save_chance = _monster_save_chance(defender, defender_definition, resolution.special_save_index)
	resolution.special_saved = _monster_saved(defender, defender_definition, resolution.special_save_index, resolution.special_save_roll, resolution.special_save_chance)
	if resolution.special_saved or defender.spell_points == 0:
		return
	var drained := attacker.hit_dice * 3
	if drained > defender.spell_points:
		drained = defender.spell_points
	defender.spell_points = AttackPolicy.signed_16(defender.spell_points - drained)
	attacker.spell_points = AttackPolicy.signed_16(attacker.spell_points + drained)
	resolution.special_amount = drained
	resolution.special_target_after = defender.spell_points
	resolution.special_actor_after = attacker.spell_points
	resolution.special_applied = drained != 0
	resolution.special_announced = resolution.special_applied


static func _is_status_special(special_code: int) -> bool:
	return special_code in [1, 2, 3, 4, 5, 6, 7, 16]


static func _is_resource_special(special_code: int) -> bool:
	return special_code in [8, 9]


static func _is_elemental_special(special_code: int) -> bool:
	return special_code >= 11 and special_code <= 15


static func _elemental_condition_index(special_code: int) -> int:
	return ConditionRules.FIRE_PROTECTION + special_code - 11


static func _elemental_name(special_code: int) -> StringName:
	match special_code:
		11:
			return &"fire"
		12:
			return &"cold"
		13:
			return &"electrical"
		14:
			return &"chemical"
		15:
			return &"mental"
	return &""


static func _resource_save_index(special_code: int) -> int:
	return 6 if special_code == 8 else 5


static func _status_condition_index(special_code: int) -> int:
	match special_code:
		1:
			return ConditionRules.RUNS_AWAY
		2:
			return ConditionRules.HELPLESS
		3:
			return ConditionRules.CURSED
		4:
			return ConditionRules.STUPID
		5:
			return ConditionRules.SLOW
		6:
			return ConditionRules.POISONED
		7:
			return ConditionRules.CONFUSED
		16:
			return ConditionRules.DISEASED
	return -1


static func _status_save_index(special_code: int) -> int:
	match special_code:
		3, 5:
			return 7
		6, 16:
			return 4
	return 5
