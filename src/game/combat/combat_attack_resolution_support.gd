## Shares source-backed monster saving-throw calculations between attack resolvers.

class_name CombatAttackResolutionSupport
extends RefCounted


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
