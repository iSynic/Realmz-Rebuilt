class_name MonsterRules
extends RefCounted

const PolymorphContextType = preload("res://src/core/rules/monster_polymorph_context.gd")

const RANDOM_WEAPON_TABLES: Array = [
	[[0, 50, 10], [51, 60, 20], [61, 70, 71], [71, 95, 75], [96, 100, 24]],
	[[0, 35, 65], [36, 70, 37], [71, 85, 125], [85, 94, 137], [95, 100, 138]],
	[[0, 40, 120], [41, 60, 37], [61, 90, 125], [91, 95, 65], [96, 100, 138]],
	[[0, 40, 81], [41, 80, 92], [81, 85, 81], [86, 93, 92], [94, 100, 136]],
	[[0, 35, 81], [36, 70, 75], [71, 90, 81], [91, 95, 75], [96, 100, 136]],
	[[0, 20, 37], [21, 40, 65], [41, 60, 75], [61, 80, 120], [81, 100, 120]],
	[[0, 15, 140], [16, 30, 142], [31, 45, 120], [46, 75, 140], [76, 100, 120]],
	[[0, 25, 92], [26, 50, 81], [51, 75, 120], [76, 90, 120], [91, 100, 120]],
	[[0, 20, 1], [21, 40, 31], [41, 65, 75], [66, 90, 44], [91, 100, 31]],
]


func build_monster(definition: MonsterDefinition, instance_id: String, traitor_override: int, difficulty: int, realmz_day: int, rng: RealmzRng) -> MonsterState:
	if definition == null or rng == null:
		return null
	var stamina := definition.stamina_bonus
	for die: int in definition.hit_dice:
		stamina += rng.draw(8, StringName("monster.%s.stamina.%d" % [instance_id, die]))
	var armor := definition.armor + rng.draw(3, StringName("monster.%s.armor" % instance_id)) - 2
	var agility := maxi(1, definition.agility + rng.draw(3, StringName("monster.%s.agility" % instance_id)) - 2)
	var spell_points := definition.spell_points
	var variation := int(float(spell_points) / 10.0)
	if variation > 0:
		spell_points += rng.draw_between(-variation, variation, StringName("monster.%s.spell-points" % instance_id))
	var magic_resistance := definition.magic_resistance
	if magic_resistance < 99 and magic_resistance > 9:
		magic_resistance += 3 * difficulty
	if magic_resistance < 99:
		magic_resistance += 3 * difficulty
	magic_resistance = maxi(0, magic_resistance)
	armor -= 2 * difficulty
	agility += difficulty
	var multiplier := 1.0 + float(difficulty) * 0.33
	spell_points = int(float(spell_points) * multiplier)
	stamina = maxi(1, int(float(stamina) * multiplier))
	var denominator := 180 - 30 * difficulty
	if denominator > 0:
		stamina += int(float(realmz_day) / float(denominator))
	var traitor := definition.traitor if traitor_override < 0 else traitor_override != 0
	var result := MonsterState.new(instance_id, definition.id, definition.name, stamina, stamina, definition.hit_dice, agility, armor, magic_resistance, spell_points, traitor)
	result.icon_id = definition.icon_id
	for index: int in 8:
		result.set_save_value(index, definition.save_value(index) + (7 * difficulty if index < 6 else 0))
	_apply_starting_conditions(result, definition)
	result.surrender_percent = definition.surrender_percent
	result.weapon_id = _random_weapon(definition.random_weapon_table, instance_id, rng) if definition.random_weapon_table > 0 else definition.weapon_id
	_set_runtime_loot(result, definition)
	return result


func build_battle_monster(definition: MonsterDefinition, instance_id: String, invert_traitor: bool, difficulty: int, realmz_day: int, rng: RealmzRng) -> MonsterState:
	if definition == null or rng == null:
		return null
	# combatsetup.c places the footprint before these draws, then randomizes AC,
	# DX, spell points, stamina, and an optional carried weapon in this order.
	var armor := definition.armor + rng.draw(3, StringName("battle.monster.%s.armor" % instance_id)) - 2
	var agility := maxi(1, definition.agility + rng.draw(3, StringName("battle.monster.%s.agility" % instance_id)) - 2)
	var spell_points := definition.spell_points
	var variation := int(float(spell_points) / 10.0)
	spell_points += rng.draw_between(-variation, variation, StringName("battle.monster.%s.spell-points" % instance_id))
	var stamina := definition.stamina_bonus
	for die: int in definition.hit_dice:
		stamina += rng.draw(8, StringName("battle.monster.%s.stamina.%d" % [instance_id, die]))
	var magic_resistance := definition.magic_resistance
	if magic_resistance < 99 and magic_resistance > 9:
		magic_resistance += 3 * difficulty
	armor -= 3 * difficulty
	agility += difficulty
	var multiplier := 1.0 + float(difficulty) * 0.40
	spell_points = int(float(spell_points) * multiplier)
	stamina = maxi(1, int(float(stamina) * multiplier))
	var denominator := 180 - 30 * difficulty
	if denominator > 0:
		stamina += int(float(realmz_day) / float(denominator))
	var traitor := definition.traitor
	if invert_traitor:
		traitor = not traitor
	var result := MonsterState.new(instance_id, definition.id, definition.name, stamina, stamina, definition.hit_dice, agility, armor, magic_resistance, spell_points, traitor)
	result.icon_id = definition.icon_id
	for index: int in 8:
		result.set_save_value(index, definition.save_value(index) + (10 * difficulty if index < 6 else 0))
	_apply_starting_conditions(result, definition)
	result.surrender_percent = definition.surrender_percent
	result.weapon_id = _battle_random_weapon(definition.random_weapon_table, instance_id, rng) if definition.random_weapon_table > 0 else definition.weapon_id
	_set_runtime_loot(result, definition)
	return result


func polymorph_monster(target: MonsterState, target_definition: MonsterDefinition, context: PolymorphContextType, rng: RealmzRng) -> String:
	if target == null or target_definition == null or context == null or rng == null or not context.has_eligible_definition(target_definition.size):
		return ""
	var definition: MonsterDefinition = null
	while definition == null:
		var candidate: MonsterDefinition = context.definition_for_classic_roll(rng.draw(200, &"magic.polymorph.candidate"))
		if candidate != null and candidate.size == target_definition.size and candidate.hit_dice > 0 and candidate.can_summon == 1:
			definition = candidate
	var old_definition_id := target.definition_id
	var old_traitor := target.traitor
	var old_summoned := target.summoned
	var old_conditions := target.conditions.values()
	var agility := definition.agility + rng.draw(3, &"magic.polymorph.agility-before-stamina") - 2
	var stamina := definition.stamina_bonus
	for die: int in definition.hit_dice:
		stamina += rng.draw(8, StringName("magic.polymorph.stamina.%d" % die))
	var armor := definition.armor + rng.draw(3, &"magic.polymorph.armor") - 2
	agility = maxi(1, agility + rng.draw(3, &"magic.polymorph.agility") - 2)
	var magic_resistance: int = definition.magic_resistance + 3 * context.difficulty
	armor -= 2 * context.difficulty
	agility += context.difficulty
	var multiplier := 1.0 + float(context.difficulty) * 0.33
	var spell_points := int(float(definition.spell_points) * multiplier)
	stamina = maxi(1, int(float(stamina) * multiplier))
	var denominator: int = 180 - 30 * context.difficulty
	if denominator > 0:
		stamina += int(float(context.realmz_day) / float(denominator))
	target.definition_id = definition.id
	target.name = definition.name
	target.hit_dice = definition.hit_dice
	target.current_health = stamina
	target.maximum_health = stamina
	target.agility = agility
	target.armor = armor
	target.magic_resistance = magic_resistance
	target.spell_points = spell_points
	target.maximum_spell_points = definition.spell_points
	target.traitor = old_traitor
	target.summoned = old_summoned
	target.icon_id = definition.icon_id
	target.surrender_percent = definition.surrender_percent
	target.weapon_id = ""
	target.target_id = ""
	for index: int in 8:
		target.set_save_value(index, definition.save_value(index) + (7 * context.difficulty if index < 6 else 0))
	target.conditions = ConditionSet.new()
	_apply_starting_conditions(target, definition)
	for index: int in mini(old_conditions.size(), target.conditions.size()):
		if int(old_conditions[index]) > -1:
			target.conditions.set_value(index, int(old_conditions[index]))
	target.set_loot_item_ids(definition.item_ids())
	return old_definition_id


static func _set_runtime_loot(monster: MonsterState, definition: MonsterDefinition) -> void:
	var item_ids := definition.item_ids()
	if not item_ids.is_empty() and definition.random_weapon_table > 0:
		item_ids[0] = monster.weapon_id
	monster.set_loot_item_ids(item_ids)


func _apply_starting_conditions(monster: MonsterState, definition: MonsterDefinition) -> void:
	var values := definition.starting_conditions()
	for index: int in mini(values.size(), monster.conditions.size()):
		monster.conditions.set_value(index, values[index])


func _random_weapon(table_id: int, instance_id: String, rng: RealmzRng) -> String:
	var table_index := 8 if table_id == 10 else table_id - 1
	if table_index < 0 or table_index >= RANDOM_WEAPON_TABLES.size():
		return ""
	var roll := rng.draw(100, StringName("monster.%s.random-weapon" % instance_id))
	for range_row: Array in RANDOM_WEAPON_TABLES[table_index]:
		if roll >= int(range_row[0]) and roll <= int(range_row[1]):
			return "classic.item.%d" % int(range_row[2])
	return ""


func _battle_random_weapon(table_id: int, instance_id: String, rng: RealmzRng) -> String:
	var table_index := 8 if table_id == 10 else table_id - 1
	if table_index < 0 or table_index >= RANDOM_WEAPON_TABLES.size():
		return ""
	var roll := rng.draw(100, StringName("battle.monster.%s.random-weapon" % instance_id))
	var result := ""
	# Authored battle construction does not return from the table scan. Its
	# overlapping roll 85 in table 2 is therefore owned by the later row.
	for range_row: Array in RANDOM_WEAPON_TABLES[table_index]:
		if roll >= int(range_row[0]) and roll <= int(range_row[1]):
			result = "classic.item.%d" % int(range_row[2])
	return result


static func random_weapon_item_ids(table_id: int) -> Array[String]:
	var table_index := 8 if table_id == 10 else table_id - 1
	var result: Array[String] = []
	if table_index < 0 or table_index >= RANDOM_WEAPON_TABLES.size():
		return result
	for range_row: Array in RANDOM_WEAPON_TABLES[table_index]:
		var item_id := "classic.item.%d" % int(range_row[2])
		if not result.has(item_id):
			result.append(item_id)
	return result


func choose_action(monster: MonsterState, definition: MonsterDefinition, rng: RealmzRng, has_adjacent_enemy: bool = false) -> StringName:
	if monster.conditions.is_active(ConditionRules.RUNS_AWAY):
		return &"retreat"
	if rng.draw(100, &"monster.ai.missile") <= definition.missile_percent and not has_adjacent_enemy:
		return &"missile"
	return choose_action_after_missile(monster, definition, rng)


func choose_action_after_missile(monster: MonsterState, definition: MonsterDefinition, rng: RealmzRng) -> StringName:
	# Castle consumes the casting-choice roll after an adjacent missile fallback,
	# an out-of-range missile, or a missile whose power cannot be afforded, and
	# before checking conditions that prevent the cast.
	var cast_roll := rng.draw(100, &"monster.ai.cast")
	if cast_roll <= definition.cast_percent and not monster.conditions.is_active(ConditionRules.STUPID) and not monster.conditions.is_active(ConditionRules.CONFUSED) and not monster.conditions.is_active(ConditionRules.SILENCED) and not monster.conditions.is_active(ConditionRules.HELPLESS):
		return &"cast"
	return &"advance"


func morale_action(monster: MonsterState, definition: MonsterDefinition) -> StringName:
	if monster.current_health <= 0:
		return &"defeated"
	# Castle getup.c computes current/current before the thresholds; preserve the observable 100 percent result.
	var percent := 100
	var surrender_percent := monster.surrender_percent if monster.surrender_percent != 0 else definition.surrender_percent
	if percent < surrender_percent:
		return &"panic" if surrender_percent == 101 else &"surrender"
	if percent < definition.run_percent:
		return &"retreat"
	return &"fight"
