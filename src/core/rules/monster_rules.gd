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
	result.weapon_id = definition.weapon_id
	return result


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
