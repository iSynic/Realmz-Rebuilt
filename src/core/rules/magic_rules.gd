class_name MagicRules
extends RefCounted


func resolve_character_spell(caster: CharacterState, target: MonsterState, target_definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> SpellResolution:
	if caster == null or target == null or target_definition == null or spell == null or rng == null or power_level < 1:
		return null
	var spell_cost := absi(spell.cost * power_level)
	if caster.spell_points < spell_cost:
		return SpellResolution.new(false, false, false, spell_cost, 0, 0)
	caster.spell_points -= spell_cost
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"magic.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"magic.damage")
	var resisted := _monster_resists(caster, target, target_definition, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type <= 6:
		saved = rng.draw(100, &"magic.damage-save") <= target_definition.save_value(damage_type - 1)
		if saved and spell.cannot < 2:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	var save_modifier := target_definition.save_value(damage_type - 1) if damage_type > 0 and damage_type <= 6 else 0
	if save_modifier < 0:
		damage = int(float(damage) * (1.0 + float(absi(save_modifier)) / 100.0))
	target.current_health -= damage
	return SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)


func character_resists(caster_level: int, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> bool:
	if spell.spell_class == 0:
		return rng.draw(100, &"magic.charm-save") <= target.save_value(0) + power_level * spell.save_adjust
	if spell.damage_type < 0 and absi(spell.damage_type) != 9:
		var direct_chance := 35 + 5 * target.level - 5 * caster_level + power_level * spell.save_adjust
		if rng.draw(100, &"magic.direct-resist") <= direct_chance:
			return true
	for level: int in range(cast_level, 5):
		if target.conditions.is_active(16 + level):
			return true
	if (spell.spell_class == 0 or spell.spell_class == 5) and target.conditions.is_active(ConditionRules.ANIMATED):
		return true
	if absi(spell.spell_class) == 9:
		if target.conditions.is_active(ConditionRules.SHIELD_FROM_PROJECTILES):
			return true
		return rng.draw(100, &"magic.missile-dodge") <= target.dodge - spell.to_hit_bonus
	return rng.draw(100, &"magic.resistance") <= target.magic_resistance + power_level * spell.resistance_adjust


func resolve_scenario_spell(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, caste: CasteDefinition = null) -> SpellResolution:
	if target == null or spell == null or rng == null or power_level < 0:
		return null
	var tag_prefix := "scenario-spell.%d.%s" % [spell.classic_id, target.id]
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration" % tag_prefix))
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage" % tag_prefix))
	var special := absi(spell.special)
	var damage_type := absi(spell.damage_type)
	var saved := false
	if damage_type > 0 and damage_type < 8 and not force_affect and spell.cannot < 2:
		var save_target := target.save_value(damage_type) + power_level * (spell.save_adjust + extra_save_adjust) + spell.save_bonus
		saved = rng.draw(100, StringName("%s.save" % tag_prefix)) <= save_target
		if saved:
			if damage == 0:
				return SpellResolution.new(true, false, true, 0, 0, duration)
			damage /= 2
	if damage != 0 and damage_type > 0 and damage_type <= 6 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
		damage /= 2
	if special > 0 and special < 41:
		if special == 28:
			damage = duration
		var condition_index := special - 1
		var current_condition := target.conditions.value(condition_index)
		if current_condition > -1 and current_condition + duration < 100:
			target.conditions.add(condition_index, duration)
	elif special > 99:
		target.conditions.set_value(special - 101, 0)
	match special:
		2:
			target.movement = 0
		3, 7:
			target.movement /= 2
		10:
			if target.conditions.value(ConditionRules.ANIMATED) < 0:
				target.conditions.set_value(ConditionRules.POISONED, 0)
		26:
			if target.current_health < -9:
				target.conditions.set_value(ConditionRules.ANIMATED, -1)
			target.current_health = int(float(target.maximum_health) / 4.0)
		27, 49:
			damage = 10 + target.current_health
			if special == 27:
				target.conditions.set_value(ConditionRules.TURNED_TO_STONE, -1)
		48:
			for item: ItemInstance in target.inventory():
				item.identified = true
		57:
			damage = -damage
		59:
			target.spell_points = mini(target.maximum_spell_points, target.spell_points + damage)
			damage = 0
		60:
			target.spell_points = maxi(0, target.spell_points - damage)
			damage = 0
		61:
			for index: int in target.conditions.size():
				if target.conditions.value(index) > 0:
					target.conditions.set_value(index, 0)
		62:
			target.conditions.set_value(ConditionRules.CURSED, 0)
		64:
			if not target.conditions.is_active(ConditionRules.TURNED_TO_STONE) and (target.current_health < -9 or target.conditions.is_active(ConditionRules.ANIMATED)):
				target.conditions.set_value(ConditionRules.ANIMATED, 0)
				target.current_health = -9
		66:
			_apply_attribute_increase(target, spell.size, caste, rng, tag_prefix)
	if damage < 0:
		target.current_health = mini(target.maximum_health, target.current_health - damage)
	elif damage > 0 and target.current_health >= 0 and target.current_health > -10:
		target.current_health -= damage
	return SpellResolution.new(true, false, saved, 0, damage, duration, target.current_health <= -10)


func _monster_resists(caster: CharacterState, target: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> bool:
	if spell.spell_class == 0:
		var charm_chance := 35 + 4 * target.hit_dice
		charm_chance += 5 if definition.type_flag(0) else 0
		charm_chance += 5 if definition.type_flag(5) else 0
		return rng.draw(100, &"magic.monster-charm") <= charm_chance + power_level * spell.save_adjust
	if spell.damage_type < 0 and absi(spell.damage_type) != 9:
		var direct_chance := 35 + 5 * target.hit_dice - 5 * caster.level + power_level * spell.save_adjust
		if rng.draw(100, &"magic.monster-direct-resist") <= direct_chance:
			return true
	if spell.spell_class >= 0 and spell.spell_class < 6 and (definition.spell_immune(spell.spell_class) or target.magic_resistance > 100):
		return true
	for level: int in range(cast_level, 5):
		if target.conditions.is_active(16 + level):
			return true
	if (spell.spell_class == 0 or spell.spell_class == 5) and target.conditions.is_active(ConditionRules.ANIMATED):
		return true
	return rng.draw(100, &"magic.monster-resistance") <= target.magic_resistance + power_level * spell.resistance_adjust


func _scaled_roll(base_min: int, base_max: int, power_min: int, power_max: int, power_level: int, rng: RealmzRng, tag: StringName) -> int:
	var total := rng.draw_between(base_min, base_max, tag) if base_max >= base_min else 0
	if power_min != 0:
		for index: int in power_level:
			if power_max >= power_min:
				total += rng.draw_between(power_min, power_max, StringName("%s.power.%d" % [tag, index]))
	return total


func _apply_attribute_increase(character: CharacterState, requested_attribute: int, caste: CasteDefinition, rng: RealmzRng, tag_prefix: String) -> void:
	var attribute := requested_attribute if requested_attribute != 0 else rng.draw(5, StringName("%s.attribute" % tag_prefix))
	match attribute:
		1:
			if character.brawn >= 25:
				return
			var maximum_bonus := caste.maximum_damage_bonus() if caste != null else 32_767
			var rules := CharacterRules.new()
			var before := rules.strength_bonuses(character.brawn, maximum_bonus)
			character.brawn += 1
			var after := rules.strength_bonuses(character.brawn, maximum_bonus)
			character.damage_bonus += after.damage_bonus - before.damage_bonus
			character.to_hit += after.to_hit_bonus - before.to_hit_bonus
			character.maximum_load = maxi(500, character.brawn * character.brawn * 20)
		2:
			if character.knowledge < 25:
				character.knowledge += 1
				if character.knowledge > 15 and caste != null:
					character.magic_resistance += caste.magic_resistance_multiplier
		3:
			if character.judgment < 25:
				character.judgment += 1
				if character.judgment > 15 and caste != null:
					character.magic_resistance += caste.magic_resistance_multiplier
		4:
			if character.agility < 25:
				character.agility += 1
				if character.agility > 14:
					character.armor += 2
		5:
			if character.vitality < 25:
				character.vitality += 1
				if character.vitality > 18:
					for index: int in 8:
						character.set_save_value(index, character.save_value(index) + 5)
		10:
			character.maximum_health += rng.draw(8, StringName("%s.stamina" % tag_prefix))
		11:
			if character.maximum_spell_points > 0:
				character.maximum_spell_points += rng.draw(20, StringName("%s.spell-points" % tag_prefix))
