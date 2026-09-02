class_name CombatRules
extends RefCounted

var _conditions: ConditionRules
var _characters: CharacterRules


func _init(condition_rules: ConditionRules, character_rules: CharacterRules) -> void:
	_conditions = condition_rules
	_characters = character_rules


func resolve_character_attack(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, realmz_day: int = 0, behind: bool = false, allow_fumbles: bool = false, can_queue_fumble: bool = true) -> AttackResolution:
	if attacker == null or equipment == null or not equipment.valid or defender == null or defender_definition == null or rng == null:
		return null
	var invalid_weapon := _invalid_weapon_reason(equipment.melee_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_character_attack(invalid_weapon)
	var condition_roll := _roll_weapon_condition_monster(equipment.melee_weapon, defender, defender_definition, rng)
	if condition_roll.get("blocked", false):
		return _blocked_character_attack(StringName(condition_roll.get("reason", "invalid_weapon_condition")))
	var type_damage := 0
	var chance := 50 + attacker.to_hit + (20 if behind else 0) + 5 * equipment.equipped_damage_bonus
	if equipment.melee_weapon != null and equipment.melee_weapon.special_1 == 121:
		chance += 5 * equipment.melee_weapon.damage_bonus
	chance += _attacker_condition_modifier(attacker.conditions)
	if defender_definition.type_flag(4) and attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance += rng.draw_classic(equipment.effective_luck, &"combat.attack.luck")
	for index: int in 8:
		if defender_definition.type_flag(index):
			chance += 5 * attacker.special_value(index)
			type_damage += attacker.special_value(index)
	chance -= defender.armor
	chance += _defender_condition_modifier(defender.conditions, true)
	chance -= int(float(maxi(0, realmz_day)) / 120.0)
	chance = maxi(5, chance)
	var roll := rng.draw(100, &"combat.attack.hit")
	var hit := roll <= chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	var fumble := _character_fumble(attacker, equipment, rng, allow_fumbles, can_queue_fumble)
	if fumble.get("fumbled", false):
		return _fumbled_attack(chance, roll, int(fumble["roll"]))
	var magic_requirement := _magic_weapon_requirement_reason(attacker, equipment, defender_definition, hit)
	if not magic_requirement.is_empty():
		return _with_fumble_observation(_blocked_character_attack(magic_requirement, chance, roll), fumble)
	var weapon_requirement := _required_weapon_reason(equipment, defender_definition, hit)
	if not weapon_requirement.is_empty():
		return _with_fumble_observation(_blocked_character_attack(weapon_requirement, chance, roll), fumble)
	if equipment.melee_weapon != null and equipment.melee_weapon.special_1 == 120:
		hit = true
	if not hit:
		attacker.lifetime_record.add_damage_given(0, false, false)
		return _with_fumble_observation(AttackResolution.new(false, false, chance, roll, 0), fumble)
	var reflected := defender.conditions.is_active(ConditionRules.REFLECTING_ATTACKS) and rng.draw(100, &"combat.attack.reflect") < 34
	var physical_damage := type_damage + equipment.effective_damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		physical_damage += 3
	var effects: Array[Dictionary] = []
	var elemental_damage := 0
	if equipment.is_armed():
		if reflected:
			elemental_damage = _roll_weapon_elements_character(equipment.melee_weapon, attacker, rng, effects)
		else:
			elemental_damage = _roll_weapon_elements_monster(equipment.melee_weapon, defender, defender_definition, rng, effects)
		physical_damage += _roll_weapon_physical(equipment.melee_weapon, defender_definition if not reflected else null, rng)
	else:
		physical_damage += rng.draw(maxi(1, attacker.hand_to_hand), &"combat.attack.unarmed-damage")
	var critical_rolls: Array[int] = [rng.draw(100, &"combat.attack.sneak-critical"), rng.draw(100, &"combat.attack.major-wound-critical")]
	physical_damage = maxi(0, physical_damage)
	if not reflected and defender.conditions.is_active(ConditionRules.HELPLESS):
		physical_damage = defender.current_health
	elif reflected and attacker.conditions.is_active(ConditionRules.HELPLESS):
		physical_damage = attacker.current_health
	var total_damage := physical_damage + elemental_damage
	var resolution := AttackResolution.new(true, false, chance, roll, total_damage, reflected)
	_with_fumble_observation(resolution, fumble)
	resolution.physical_damage = physical_damage
	resolution.weapon_effects = effects
	resolution.critical_rolls = critical_rolls
	if reflected:
		_apply_weapon_condition_character(attacker, condition_roll, resolution)
		attacker.current_health -= total_damage
		resolution.killed = attacker.current_health <= 0
		attacker.lifetime_record.add_damage_taken(total_damage, true)
		return resolution
	_apply_weapon_condition_monster(defender, condition_roll, resolution)
	defender.current_health -= total_damage
	resolution.killed = defender.current_health <= 0
	attacker.lifetime_record.add_damage_given(total_damage, true, resolution.killed)
	return resolution


func resolve_character_attack_character(attacker: CharacterState, attacker_equipment: CharacterCombatEquipment, defender: CharacterState, defender_equipment: CharacterCombatEquipment, rng: RealmzRng, behind: bool = false, allow_fumbles: bool = false, can_queue_fumble: bool = true) -> AttackResolution:
	if attacker == null or attacker_equipment == null or not attacker_equipment.valid or defender == null or defender_equipment == null or not defender_equipment.valid or rng == null:
		return null
	var invalid_weapon := _invalid_weapon_reason(attacker_equipment.melee_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_character_attack(invalid_weapon)
	var condition_roll := _roll_weapon_condition_character(attacker_equipment.melee_weapon, defender, rng)
	if condition_roll.get("blocked", false):
		return _blocked_character_attack(StringName(condition_roll.get("reason", "invalid_weapon_condition")))
	var chance := 50 + attacker.to_hit + (20 if behind else 0) + 5 * attacker_equipment.equipped_damage_bonus
	if attacker_equipment.melee_weapon != null and attacker_equipment.melee_weapon.special_1 == 121:
		chance += 5 * attacker_equipment.melee_weapon.damage_bonus
	chance += _attacker_condition_modifier(attacker.conditions)
	chance += rng.draw_classic(attacker_equipment.effective_luck, &"combat.attack.luck")
	chance -= defender_equipment.effective_armor
	chance += _defender_condition_modifier(defender.conditions, false)
	chance = maxi(5, chance)
	var roll := rng.draw(100, &"combat.attack.hit")
	var hit := roll <= chance or defender.conditions.is_active(ConditionRules.HELPLESS)
	var fumble := _character_fumble(attacker, attacker_equipment, rng, allow_fumbles, can_queue_fumble)
	if fumble.get("fumbled", false):
		return _fumbled_attack(chance, roll, int(fumble["roll"]))
	if attacker_equipment.melee_weapon != null and attacker_equipment.melee_weapon.special_1 == 120:
		hit = true
	if not hit:
		return _with_fumble_observation(AttackResolution.new(false, false, chance, roll, 0), fumble)
	var reflected := defender.conditions.is_active(ConditionRules.REFLECTING_ATTACKS) and rng.draw(100, &"combat.attack.reflect") < 34
	var target := attacker if reflected else defender
	var physical_damage := attacker_equipment.effective_damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		physical_damage += 3
	var effects: Array[Dictionary] = []
	var elemental_damage := 0
	if attacker_equipment.is_armed():
		elemental_damage = _roll_weapon_elements_character(attacker_equipment.melee_weapon, target, rng, effects)
		physical_damage += _roll_weapon_physical(attacker_equipment.melee_weapon, null, rng)
	else:
		physical_damage += rng.draw(maxi(1, attacker.hand_to_hand), &"combat.attack.unarmed-damage")
	var critical_rolls: Array[int] = [rng.draw(100, &"combat.attack.sneak-critical"), rng.draw(100, &"combat.attack.major-wound-critical")]
	physical_damage = maxi(0, physical_damage)
	if target.conditions.is_active(ConditionRules.HELPLESS):
		physical_damage = target.current_health
	var total_damage := physical_damage + elemental_damage
	var resolution := AttackResolution.new(true, false, chance, roll, total_damage, reflected)
	_with_fumble_observation(resolution, fumble)
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


static func _character_fumble(attacker: CharacterState, equipment: CharacterCombatEquipment, rng: RealmzRng, allow_fumbles: bool, can_queue_fumble: bool) -> Dictionary:
	if not allow_fumbles:
		return {}
	var roll := rng.draw(1000 + 100 * attacker.level, &"combat.attack.fumble")
	if roll <= 50 or roll >= 60 or not equipment.is_armed():
		return {"roll": roll}
	if not equipment.melee_weapon.cursed_item_id.is_empty():
		return {"roll": roll, "blockedReason": &"cursed_weapon"}
	if not can_queue_fumble:
		return {"roll": roll, "blockedReason": &"fumble_queue_full"}
	return {"roll": roll, "fumbled": true}


static func _fumbled_attack(chance: int, roll: int, fumble_roll: int) -> AttackResolution:
	var resolution := AttackResolution.new(false, false, chance, roll, 0)
	resolution.fumbled = true
	resolution.fumble_roll = fumble_roll
	return resolution


static func _with_fumble_observation(resolution: AttackResolution, fumble: Dictionary) -> AttackResolution:
	if resolution == null or fumble.is_empty():
		return resolution
	resolution.fumble_roll = int(fumble.get("roll", 0))
	resolution.fumble_block_reason = StringName(fumble.get("blockedReason", &""))
	return resolution


static func _magic_weapon_requirement_reason(attacker: CharacterState, equipment: CharacterCombatEquipment, defender: MonsterDefinition, hit: bool) -> StringName:
	if defender.magic_to_hit <= 0:
		return &""
	if equipment.is_armed():
		if hit and defender.magic_to_hit > equipment.melee_weapon.damage_bonus:
			return &"classic_magic_weapon_required"
		return &""
	if defender.magic_to_hit > attacker.level / 8:
		return &"classic_magic_weapon_required"
	return &""


static func _required_weapon_reason(equipment: CharacterCombatEquipment, defender: MonsterDefinition, hit: bool) -> StringName:
	if not hit or defender.required_weapon == 0:
		return &""
	if not equipment.is_armed():
		if defender.required_weapon == -1:
			return &"classic_blunt_weapon_required"
		if defender.required_weapon == -2:
			return &"classic_sharp_weapon_required"
		return &"classic_specific_weapon_required"
	if defender.required_weapon == -1:
		return &"" if equipment.melee_weapon.blunt == -1 else &"classic_blunt_weapon_required"
	if defender.required_weapon == -2:
		return &"" if equipment.melee_weapon.blunt == -2 else &"classic_sharp_weapon_required"
	# FD-COMBAT-003: Castle's minus-1024 comparison cannot match the shipped
	# 1..999 item IDs. Divinity defines this byte as the ordinary Item Number.
	var required_item_id := defender.required_weapon & 0xff
	return &"" if equipment.melee_weapon.classic_id == required_item_id else &"classic_specific_weapon_required"


static func _invalid_weapon_reason(weapon: ItemDefinition) -> StringName:
	if weapon == null:
		return &""
	if weapon.vs_small < 0 or weapon.vs_large < 0 or weapon.heat < 0 or weapon.cold < 0 or weapon.electric < 0 or weapon.vs_undead < 0 or weapon.vs_demon_devil < 0 or weapon.vs_evil < 0:
		return &"unsupported_negative_weapon_range"
	if weapon.special_1 == -10:
		if weapon.special_3 < 20 or weapon.special_3 >= 60:
			return &"invalid_weapon_condition"
		if weapon.special_2 == 1 and (weapon.special_4 < 0 or weapon.special_4 >= 8):
			return &"invalid_weapon_condition_save"
	return &""


func _roll_weapon_condition_monster(weapon: ItemDefinition, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng) -> Dictionary:
	if weapon == null or weapon.special_1 != -10:
		return {}
	var result := {"index": weapon.special_3 - 20, "amount": weapon.special_5, "applies": false}
	match weapon.special_2:
		1:
			var roll := rng.draw(100, &"combat.attack.weapon-condition-save")
			var chance := _monster_save_chance(defender, defender_definition, weapon.special_4)
			result["saveIndex"] = weapon.special_4
			result["saveChance"] = chance
			result["saveRoll"] = roll
			result["applies"] = not _monster_saved(defender, defender_definition, weapon.special_4, roll, chance)
		2:
			var roll := rng.draw(100, &"combat.attack.weapon-condition-chance")
			result["chance"] = weapon.special_4
			result["roll"] = roll
			result["applies"] = roll <= weapon.special_4
		_:
			result["applies"] = true
	return result


static func _roll_weapon_condition_character(weapon: ItemDefinition, defender: CharacterState, rng: RealmzRng) -> Dictionary:
	if weapon == null or weapon.special_1 != -10:
		return {}
	var result := {"index": weapon.special_3 - 20, "amount": weapon.special_5, "applies": false}
	match weapon.special_2:
		1:
			var roll := rng.draw(100, &"combat.attack.weapon-condition-save")
			result["saveIndex"] = weapon.special_4
			result["saveChance"] = defender.save_value(weapon.special_4)
			result["saveRoll"] = roll
			result["applies"] = roll > defender.save_value(weapon.special_4)
		2:
			var roll := rng.draw(100, &"combat.attack.weapon-condition-chance")
			result["chance"] = weapon.special_4
			result["roll"] = roll
			result["applies"] = roll <= weapon.special_4
		_:
			result["applies"] = true
	return result


static func _apply_weapon_condition_monster(defender: MonsterState, condition_roll: Dictionary, resolution: AttackResolution) -> void:
	if condition_roll.is_empty() or not condition_roll.get("applies", false):
		return
	var index := int(condition_roll["index"])
	resolution.weapon_condition_index = index
	resolution.weapon_condition_before = defender.conditions.value(index)
	resolution.weapon_condition_after = resolution.weapon_condition_before
	if resolution.weapon_condition_before > -1:
		resolution.weapon_condition_after += int(condition_roll["amount"])
		defender.conditions.set_value(index, resolution.weapon_condition_after)


static func _apply_weapon_condition_character(defender: CharacterState, condition_roll: Dictionary, resolution: AttackResolution) -> void:
	_record_weapon_condition_character(defender, condition_roll, resolution)
	if resolution.weapon_condition_index >= 0:
		defender.conditions.set_value(resolution.weapon_condition_index, resolution.weapon_condition_after)


static func _record_weapon_condition_character(defender: CharacterState, condition_roll: Dictionary, resolution: AttackResolution) -> void:
	if condition_roll.is_empty() or not condition_roll.get("applies", false):
		return
	var index := int(condition_roll["index"])
	resolution.weapon_condition_index = index
	resolution.weapon_condition_before = defender.conditions.value(index)
	resolution.weapon_condition_after = resolution.weapon_condition_before
	if resolution.weapon_condition_before > -1:
		resolution.weapon_condition_after += int(condition_roll["amount"])


static func _roll_weapon_physical(weapon: ItemDefinition, defender_definition: MonsterDefinition, rng: RealmzRng) -> int:
	var damage := 0
	if defender_definition != null:
		if weapon.vs_undead != 0 and defender_definition.type_flag(1):
			damage += rng.draw(maxi(1, weapon.vs_undead), &"combat.attack.weapon-versus-undead")
		if weapon.vs_demon_devil != 0 and defender_definition.type_flag(2):
			damage += rng.draw(maxi(1, weapon.vs_demon_devil), &"combat.attack.weapon-versus-demon-devil")
		if weapon.vs_evil != 0 and defender_definition.type_flag(4):
			damage += rng.draw(maxi(1, weapon.vs_evil), &"combat.attack.weapon-versus-evil")
	# Castle's player melee path always uses the small-target weapon die, including Rand(0).
	damage += rng.draw(maxi(1, weapon.vs_small), &"combat.attack.weapon-physical")
	return damage


func _roll_weapon_elements_monster(weapon: ItemDefinition, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, effects: Array[Dictionary]) -> int:
	var total := 0
	var ranges: Array[int] = [weapon.heat, weapon.cold, weapon.electric]
	var names: Array[StringName] = [&"fire", &"cold", &"electrical"]
	var save_indexes: Array[int] = [1, 2, 3]
	var conditions: Array[int] = [ConditionRules.FIRE_PROTECTION, ConditionRules.COLD_PROTECTION, ConditionRules.ELECTRICAL_PROTECTION]
	for index: int in 3:
		if ranges[index] == 0 or defender_definition.spell_immune(save_indexes[index]):
			continue
		var rolled := rng.draw(ranges[index], StringName("combat.attack.weapon-%s" % names[index]))
		var effective := rolled
		var protected := defender.conditions.is_active(conditions[index])
		if protected:
			effective = int(float(effective) / 2.0)
		var save_roll := rng.draw(100, StringName("combat.attack.weapon-%s-save" % names[index]))
		var save_chance := _monster_save_chance(defender, defender_definition, save_indexes[index])
		var saved := _monster_saved(defender, defender_definition, save_indexes[index], save_roll, save_chance)
		if saved:
			effective = int(float(effective) / 2.0)
		effects.append({"element": String(names[index]), "rolled": rolled, "saveIndex": save_indexes[index], "saveChance": save_chance, "saveRoll": save_roll, "saved": saved, "protected": protected, "amount": effective})
		total += effective
	return total


static func _roll_weapon_elements_character(weapon: ItemDefinition, defender: CharacterState, rng: RealmzRng, effects: Array[Dictionary]) -> int:
	var total := 0
	var ranges: Array[int] = [weapon.heat, weapon.cold, weapon.electric]
	var names: Array[StringName] = [&"fire", &"cold", &"electrical"]
	var save_indexes: Array[int] = [1, 2, 3]
	var conditions: Array[int] = [ConditionRules.FIRE_PROTECTION, ConditionRules.COLD_PROTECTION, ConditionRules.ELECTRICAL_PROTECTION]
	for index: int in 3:
		if ranges[index] == 0:
			continue
		var rolled := rng.draw(ranges[index], StringName("combat.attack.weapon-%s" % names[index]))
		var save_roll := rng.draw(100, StringName("combat.attack.weapon-%s-save" % names[index]))
		var save_chance := defender.save_value(save_indexes[index])
		var saved := save_roll <= save_chance
		var effective := int(float(rolled) / 2.0) if saved else rolled
		var protected := defender.conditions.is_active(conditions[index])
		if protected:
			effective = int(float(effective) / 2.0)
		effects.append({"element": String(names[index]), "rolled": rolled, "saveIndex": save_indexes[index], "saveChance": save_chance, "saveRoll": save_roll, "saved": saved, "protected": protected, "amount": effective})
		total += effective
	return total


func resolve_monster_attack(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: CharacterState, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng, charm_save_bonus: int = 0, context: MonsterAttackContext = null, allow_fumbles: bool = false) -> AttackResolution:
	if attacker == null or attacker_definition == null or defender == null or rng == null:
		return null
	var attack_context := context if context != null else MonsterAttackContext.new(null, 0, false, defender.luck)
	var invalid_weapon := _invalid_weapon_reason(attack_context.attacker_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_monster_attack(invalid_weapon)
	var condition_roll := _roll_weapon_condition_character(attack_context.attacker_weapon, defender, rng)
	if condition_roll.get("blocked", false):
		return _blocked_monster_attack(StringName(condition_roll.get("reason", "invalid_weapon_condition")))
	var chance := _monster_attack_base_chance(attacker, attacker_definition, attack_context)
	chance += _attacker_condition_modifier(attacker.conditions)
	if attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance -= rng.draw_classic(attack_context.defender_luck, &"combat.monster-attack.defender-luck")
	chance -= attack_context.defender_armor if attack_context.defender_armor >= 0 else defender.armor
	chance += _defender_condition_modifier(defender.conditions, false)
	if attacker_definition.type_flag(4) and defender.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance -= 10
	chance = maxi(10, chance)
	var roll := rng.draw(100, &"combat.monster-attack.hit")
	var hit := roll <= chance or _monster_weapon_auto_hits(attack_context.attacker_weapon)
	var helpless := defender.conditions.is_active(ConditionRules.HELPLESS)
	if helpless:
		hit = true
	var fumble_roll := _monster_fumble_roll(attacker, rng, allow_fumbles)
	if _monster_fumbled(attack_context.attacker_weapon, fumble_roll):
		return _fumbled_attack(chance, roll, fumble_roll)
	if not hit:
		defender.lifetime_record.add_damage_taken(0, false)
		return _with_monster_fumble_roll(AttackResolution.new(false, false, chance, roll, 0), fumble_roll)
	var attacks := attacker_definition.attacks()
	var attack := _monster_attack_row(attacks, attack_index)
	var damage := attacker_definition.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	var effects: Array[Dictionary] = []
	var elemental_damage := 0
	if helpless:
		damage = defender.current_health + rng.draw(10, &"combat.monster-attack.helpless-damage")
	elif attack_context.attacker_weapon != null:
		damage += attack_context.attacker_weapon.damage_bonus
		damage += rng.draw(maxi(1, attack_context.attacker_weapon.vs_small), &"combat.monster-attack.weapon-physical")
		elemental_damage = _roll_weapon_elements_character(attack_context.attacker_weapon, defender, rng, effects)
	else:
		damage += rng.draw_between(attack.damage_min, attack.damage_max, &"combat.monster-attack.damage")
	damage = maxi(0, damage)
	var resolution_physical_damage_reduction := 0
	if attack_context.party_dragon_hide and damage > 1:
		var damage_before_dragon_hide := damage
		damage = maxi(1, damage - 5)
		resolution_physical_damage_reduction = damage_before_dragon_hide - damage
	var resolution := AttackResolution.new(true, defender.current_health - damage - elemental_damage <= 0, chance, roll, damage + elemental_damage)
	_with_monster_fumble_roll(resolution, fumble_roll)
	resolution.physical_damage = damage
	resolution.physical_damage_reduction = resolution_physical_damage_reduction
	resolution.physical_feedback_sound_id = 694 if resolution_physical_damage_reduction > 0 else 0
	resolution.weapon_effects = effects
	if attack.special != 0:
		resolution.special_code = attack.special
		var potency_low := int(float(attacker.hit_dice) / 2.0)
		resolution.special_potency = maxi(1, rng.draw_between(potency_low, attacker.hit_dice, &"combat.monster-attack.special-potency"))
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
			var age_factor := _signed_16(attack.damage_max * attacker.hit_dice)
			resolution.special_age_days = int(float(race.max_age) * 0.01 * float(age_factor)) if race != null else 0
			if race != null and caste != null:
				resolution.aging = _characters.advance_age_days(defender, race, caste, resolution.special_age_days)
	elif attack.special in [18, 19]:
		_apply_party_permanent_affliction(resolution, defender, rng)
	resolution.damage_deferred = resolution.aging != null and resolution.aging.changed_group()
	if resolution.damage_deferred:
		_record_weapon_condition_character(defender, condition_roll, resolution)
	else:
		_apply_weapon_condition_character(defender, condition_roll, resolution)
	if not resolution.damage_deferred and not resolution.physical_damage_skipped:
		defender.current_health -= damage + elemental_damage + resolution.special_damage_amount
		resolution.killed = defender.current_health <= 0
	defender.lifetime_record.add_damage_taken(resolution.total_damage(), true)
	return resolution


func resolve_monster_attack_monster(attacker: MonsterState, attacker_definition: MonsterDefinition, attack_index: int, defender: MonsterState, defender_definition: MonsterDefinition, rng: RealmzRng, context: MonsterAttackContext = null, allow_fumbles: bool = false) -> AttackResolution:
	if attacker == null or attacker_definition == null or defender == null or defender_definition == null or rng == null:
		return null
	var attack_context := context if context != null else MonsterAttackContext.new()
	var invalid_weapon := _invalid_weapon_reason(attack_context.attacker_weapon)
	if not invalid_weapon.is_empty():
		return _blocked_monster_attack(invalid_weapon)
	var condition_roll := _roll_weapon_condition_monster(attack_context.attacker_weapon, defender, defender_definition, rng)
	if condition_roll.get("blocked", false):
		return _blocked_monster_attack(StringName(condition_roll.get("reason", "invalid_weapon_condition")))
	var chance := _monster_attack_base_chance(attacker, attacker_definition, attack_context)
	chance += _attacker_condition_modifier(attacker.conditions)
	if attacker.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance += 10
	chance -= defender.armor
	chance += _defender_condition_modifier(defender.conditions, false)
	if attacker_definition.type_flag(4) and defender.conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL):
		chance -= 10
	chance = maxi(10, chance)
	var roll := rng.draw(100, &"combat.monster-attack.hit")
	var hit := roll <= chance or _monster_weapon_auto_hits(attack_context.attacker_weapon)
	var helpless := defender.conditions.is_active(ConditionRules.HELPLESS)
	if helpless:
		hit = true
	var fumble_roll := _monster_fumble_roll(attacker, rng, allow_fumbles)
	if _monster_fumbled(attack_context.attacker_weapon, fumble_roll):
		return _fumbled_attack(chance, roll, fumble_roll)
	if not hit:
		return _with_monster_fumble_roll(AttackResolution.new(false, false, chance, roll, 0), fumble_roll)
	var weapon_requirement := _monster_required_weapon_reason(attack_context.attacker_weapon, defender_definition)
	if not weapon_requirement.is_empty():
		return _with_monster_fumble_roll(_blocked_monster_attack(weapon_requirement, chance, roll), fumble_roll)
	var attacks := attacker_definition.attacks()
	var attack := _monster_attack_row(attacks, attack_index)
	var damage := attacker_definition.damage_bonus + attacker.conditions.value(ConditionRules.ATTACK_BONUS)
	if attacker.conditions.is_active(ConditionRules.STRONG):
		damage += 3
	var effects: Array[Dictionary] = []
	var elemental_damage := 0
	if helpless:
		damage = defender.current_health
	elif attack_context.attacker_weapon != null:
		damage += attack_context.attacker_weapon.damage_bonus
		damage += rng.draw(maxi(1, attack_context.attacker_weapon.vs_small), &"combat.monster-attack.weapon-physical")
		elemental_damage = _roll_weapon_elements_monster(attack_context.attacker_weapon, defender, defender_definition, rng, effects)
		elemental_damage += _roll_monster_weapon_type_damage(attack_context.attacker_weapon, defender_definition, rng, effects)
	else:
		damage += rng.draw_between(attack.damage_min, attack.damage_max, &"combat.monster-attack.damage")
	damage = maxi(0, damage)
	var resolution := AttackResolution.new(true, defender.current_health - damage - elemental_damage <= 0, chance, roll, damage + elemental_damage)
	_with_monster_fumble_roll(resolution, fumble_roll)
	resolution.physical_damage = damage
	resolution.weapon_effects = effects
	if attack.special != 0:
		resolution.special_code = attack.special
		var potency_low := int(float(attacker.hit_dice) / 2.0)
		resolution.special_potency = maxi(1, rng.draw_between(potency_low, attacker.hit_dice, &"combat.monster-attack.special-potency"))
		if _is_status_special(attack.special):
			resolution.special_handled = true
			resolution.special_save_index = _status_save_index(attack.special)
			resolution.special_condition_index = _status_condition_index(attack.special)
			resolution.special_condition_before = defender.conditions.value(resolution.special_condition_index)
			resolution.special_condition_after = resolution.special_condition_before
		elif _is_resource_special(attack.special):
			resolution.special_handled = true
			resolution.special_save_index = _resource_save_index(attack.special)
			resolution.special_resource = &"spell_points" if attack.special == 8 else &"experience"
		elif attack.special == 17:
			resolution.special_handled = true
		elif attack.special == 10:
			resolution.special_handled = true
			resolution.special_save_index = 0
			resolution.special_allegiance_before = defender.traitor
			resolution.special_allegiance_after = defender.traitor
		elif _is_elemental_special(attack.special):
			resolution.special_handled = true
			resolution.special_save_index = attack.special - 10
			resolution.special_condition_index = _elemental_condition_index(attack.special)
			resolution.special_element = _elemental_name(attack.special)
		elif attack.special in [18, 19]:
			resolution.special_handled = true
			resolution.special_save_index = 7
			resolution.special_condition_index = ConditionRules.BLIND if attack.special == 18 else ConditionRules.TURNED_TO_STONE
		if defender.magic_resistance > 100:
			resolution.special_blocked = true
			resolution.special_block_reason = &"magic_resistance"
			resolution.hit = false
			resolution.damage = 0
			resolution.killed = false
			return resolution
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
	_apply_weapon_condition_monster(defender, condition_roll, resolution)
	if not resolution.physical_damage_skipped:
		defender.current_health -= damage + elemental_damage + resolution.special_damage_amount
		resolution.killed = defender.current_health <= 0
	return resolution


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
	resolution.special_condition_after = _signed_16(resolution.special_condition_before + absi(resolution.special_potency))
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
	resolution.special_condition_after = _signed_16(resolution.special_condition_before + absi(resolution.special_potency))
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
		defender.spell_points = _signed_16(defender.spell_points - drained)
		attacker.spell_points = _signed_16(attacker.spell_points + drained)
		resolution.special_amount = drained
		resolution.special_target_after = defender.spell_points
		resolution.special_actor_after = attacker.spell_points
		resolution.special_applied = drained != 0
		resolution.special_announced = resolution.special_applied
		return
	var removed := attacker.maximum_health * 20
	defender.experience = _signed_32(defender.experience - removed)
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
	defender.spell_points = _signed_16(defender.spell_points - drained)
	attacker.spell_points = _signed_16(attacker.spell_points + drained)
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


static func _monster_save_chance(monster: MonsterState, definition: MonsterDefinition, save_index: int) -> int:
	if save_index == 7:
		var total := 0
		for index: int in 6:
			total += monster.save_value(index) if monster.has_runtime_saves() else definition.save_value(index)
		return int(float(total) / 6.0)
	return (monster.save_value(save_index - 1) if monster.has_runtime_saves() else definition.save_value(save_index - 1)) if save_index > 0 else 0


static func _monster_saved(_monster: MonsterState, definition: MonsterDefinition, save_index: int, roll: int, chance: int) -> bool:
	if save_index < 6 and definition.spell_immune(save_index):
		return true
	if save_index > 0 and roll <= chance:
		return true
	return definition.type_flag(1) and save_index in [0, 4, 5]


func initiative_order(characters: Array[CharacterState], monsters: Array[MonsterState], surprise: int, rng: RealmzRng) -> Array[String]:
	var order: Array[String] = []
	for character: CharacterState in characters:
		if character.current_health > 0:
			order.append(character.id)
	for monster: MonsterState in monsters:
		if monster.current_health > 0:
			order.append(monster.id)
	if surprise > 0:
		return _party_first(order, characters)
	if surprise < 0:
		return _monsters_first(order, monsters)
	for index: int in range(order.size() - 1, 0, -1):
		var swap_index := rng.draw_between(0, index, &"combat.initiative.slot")
		var held := order[index]
		order[index] = order[swap_index]
		order[swap_index] = held
	for left: int in order.size():
		for right: int in range(left, order.size() - 1):
			if _agility(order[right + 1], characters, monsters) > _agility(order[right], characters, monsters):
				var held := order[right]
				order[right] = order[right + 1]
				order[right + 1] = held
	return order


func _attacker_condition_modifier(conditions: ConditionSet) -> int:
	var modifier := 0
	modifier -= absi(conditions.value(ConditionRules.TANGLED))
	modifier += 15 if conditions.is_active(ConditionRules.STRONG) else 0
	modifier -= 15 if conditions.is_active(ConditionRules.SLOW) else 0
	modifier -= 10 if conditions.is_active(ConditionRules.CONFUSED) else 0
	modifier -= 15 if conditions.is_active(ConditionRules.BLIND) else 0
	modifier += 5 if conditions.is_active(ConditionRules.MAGIC_AURA) else 0
	modifier -= 5 if conditions.is_active(ConditionRules.CURSED) else 0
	modifier -= absi(conditions.value(ConditionRules.HINDERED_ATTACKS))
	return modifier


func _defender_condition_modifier(conditions: ConditionSet, include_protection_from_evil: bool = true) -> int:
	var modifier := -2 * absi(conditions.value(ConditionRules.SHIELD_FROM_HITS))
	modifier += 10 if conditions.is_active(ConditionRules.CONFUSED) else 0
	modifier += 15 if conditions.is_active(ConditionRules.BLIND) else 0
	modifier += 15 if conditions.is_active(ConditionRules.SLOW) else 0
	modifier -= 5 if conditions.is_active(ConditionRules.MAGIC_AURA) else 0
	modifier += 5 if conditions.is_active(ConditionRules.CURSED) else 0
	modifier -= 10 if conditions.is_active(ConditionRules.INVISIBLE) else 0
	modifier += absi(conditions.value(ConditionRules.TANGLED))
	modifier += absi(conditions.value(ConditionRules.HINDERED_DEFENSE))
	modifier -= absi(conditions.value(ConditionRules.DEFENSE_BONUS))
	modifier -= 10 if include_protection_from_evil and conditions.is_active(ConditionRules.PROTECTION_FROM_EVIL) else 0
	return modifier


func _agility(id: String, characters: Array[CharacterState], monsters: Array[MonsterState]) -> int:
	for character: CharacterState in characters:
		if character.id == id:
			return character.agility
	for monster: MonsterState in monsters:
		if monster.id == id:
			return monster.agility
	return 0


func _party_first(order: Array[String], characters: Array[CharacterState]) -> Array[String]:
	var party_ids: Dictionary = {}
	for character: CharacterState in characters:
		party_ids[character.id] = true
	var first: Array[String] = []
	var last: Array[String] = []
	for id: String in order:
		if party_ids.has(id):
			first.append(id)
		else:
			last.append(id)
	first.append_array(last)
	return first


func _monsters_first(order: Array[String], monsters: Array[MonsterState]) -> Array[String]:
	var monster_ids: Dictionary = {}
	for monster: MonsterState in monsters:
		monster_ids[monster.id] = true
	var first: Array[String] = []
	var last: Array[String] = []
	for id: String in order:
		if monster_ids.has(id):
			first.append(id)
		else:
			last.append(id)
	first.append_array(last)
	return first


static func _signed_16(value: int) -> int:
	var wrapped := value & 0xffff
	return wrapped - 0x10000 if wrapped >= 0x8000 else wrapped


static func _signed_32(value: int) -> int:
	var wrapped := value & 0xffffffff
	return wrapped - 0x100000000 if wrapped >= 0x80000000 else wrapped
