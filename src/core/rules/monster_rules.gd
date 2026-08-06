class_name MonsterRules
extends RefCounted


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
	result.weapon_id = _random_weapon(definition.random_weapon_table, instance_id, rng) if definition.random_weapon_table > 0 else definition.weapon_id
	return result


func _random_weapon(table_id: int, instance_id: String, rng: RealmzRng) -> String:
	var table_index := 8 if table_id == 10 else table_id - 1
	var tables: Array[Array] = [
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
	if table_index < 0 or table_index >= tables.size():
		return ""
	var roll := rng.draw(100, StringName("monster.%s.random-weapon" % instance_id))
	for range_row: Array in tables[table_index]:
		if roll >= int(range_row[0]) and roll <= int(range_row[1]):
			return "classic.item.%d" % int(range_row[2])
	return ""


func choose_action(monster: MonsterState, definition: MonsterDefinition, rng: RealmzRng) -> StringName:
	if monster.conditions.is_active(ConditionRules.RUNS_AWAY):
		return &"retreat"
	if rng.draw(100, &"monster.ai.missile") <= definition.missile_percent:
		return &"missile"
	if not monster.conditions.is_active(ConditionRules.STUPID) and not monster.conditions.is_active(ConditionRules.CONFUSED) and not monster.conditions.is_active(ConditionRules.SILENCED) and not monster.conditions.is_active(ConditionRules.HELPLESS) and rng.draw(100, &"monster.ai.cast") <= definition.cast_percent:
		return &"cast"
	return &"advance"


func morale_action(monster: MonsterState, definition: MonsterDefinition) -> StringName:
	if monster.current_health <= 0:
		return &"defeated"
	# Castle getup.c computes current/current before the thresholds; preserve the observable 100 percent result.
	var percent := 100
	if percent < definition.surrender_percent:
		return &"panic" if definition.surrender_percent == 101 else &"surrender"
	if percent < definition.run_percent:
		return &"retreat"
	return &"fight"
