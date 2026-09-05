## Resolves field and scenario spell effects outside combat targeting flow.

class_name FieldScenarioSpellResolver
extends SpellResolutionSupport


class NoncombatEffectRoll:
	extends RefCounted

	var damage: int
	var saved: bool
	var terminal_resolution: SpellResolution

	func _init(next_damage: int, did_save: bool = false, terminal: SpellResolution = null) -> void:
		damage = next_damage
		saved = did_save
		terminal_resolution = terminal

func resolve_field_spell(caster: CharacterState, targets: Array[CharacterState], spell: SpellDefinition, power_level: int, rng: RealmzRng, castes: Array[CasteDefinition] = [], races: Array[RaceDefinition] = [], spend_spell_points: bool = true, allow_empty: bool = false, item_definitions: Array[ItemDefinition] = [], ally_targets: Array[MonsterState] = [], ally_definitions: Array[MonsterDefinition] = []) -> GroupSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or ally_targets.size() != ally_definitions.size() or not allow_empty and targets.is_empty() and ally_targets.is_empty():
		return null
	if not castes.is_empty() and castes.size() != targets.size() or not races.is_empty() and races.size() != targets.size():
		return null
	for target: CharacterState in targets:
		if target == null:
			return null
	for index: int in ally_targets.size():
		if ally_targets[index] == null or ally_definitions[index] == null:
			return null
	var spell_cost := absi(spell.cost * power_level)
	if spend_spell_points and caster.spell_points < spell_cost:
		return GroupSpellResolution.new(false, spell_cost, 0, 0)
	if spend_spell_points:
		caster.spell_points -= spell_cost
	else:
		spell_cost = 0
	var tag_prefix := "field-spell.%d" % spell.classic_id
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration" % tag_prefix))
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage" % tag_prefix))
	var result := GroupSpellResolution.new(true, spell_cost, duration, damage)
	for index: int in targets.size():
		var target := targets[index]
		var caste: CasteDefinition = null if castes.is_empty() else castes[index]
		var race: RaceDefinition = null if races.is_empty() else races[index]
		var resolution := _resolve_noncombat_character_effect(target, spell, power_level, 0, false, rng, caste, race, duration, damage, "%s.%s" % [tag_prefix, target.id], item_definitions)
		result.append_target(target.id, &"character", resolution)
	for index: int in ally_targets.size():
		var ally_resolution := _resolve_character_spell_monster_target(caster, ally_targets[index], ally_definitions[index], spell, power_level, 0, damage, duration, 0, rng, null, 0, false, true)
		result.append_target(ally_targets[index].id, &"monster", ally_resolution)
	return result


func resolve_scenario_spell(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, caste: CasteDefinition = null, race: RaceDefinition = null) -> SpellResolution:
	if target == null or spell == null or rng == null or power_level < 0:
		return null
	var tag_prefix := "scenario-spell.%d.%s" % [spell.classic_id, target.id]
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration" % tag_prefix))
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage" % tag_prefix))
	return _resolve_noncombat_character_effect(target, spell, power_level, extra_save_adjust, force_affect, rng, caste, race, duration, damage, tag_prefix)


func resolve_scenario_group_spell(targets: Array[CharacterState], spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, castes: Array[CasteDefinition] = [], races: Array[RaceDefinition] = []) -> GroupSpellResolution:
	if spell == null or rng == null or power_level < 0 or targets.is_empty() or not castes.is_empty() and castes.size() != targets.size() or not races.is_empty() and races.size() != targets.size():
		return null
	for target: CharacterState in targets:
		if target == null:
			return null
	var tag_prefix := "scenario-group-spell.%d" % spell.classic_id
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration" % tag_prefix))
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage" % tag_prefix))
	var result := GroupSpellResolution.new(true, 0, duration, damage)
	for index: int in targets.size():
		var target := targets[index]
		var caste: CasteDefinition = null if castes.is_empty() else castes[index]
		var race: RaceDefinition = null if races.is_empty() else races[index]
		result.append_target(target.id, &"character", _resolve_noncombat_character_effect(target, spell, power_level, extra_save_adjust, force_affect, rng, caste, race, duration, damage, "%s.%s" % [tag_prefix, target.id]))
	return result


func _resolve_noncombat_character_effect(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, caste: CasteDefinition, race: RaceDefinition, duration: int, damage: int, tag_prefix: String, item_definitions: Array[ItemDefinition] = []) -> SpellResolution:
	var special := absi(spell.special)
	if special == 62:
		return _remove_curse_character(target, 0, duration, item_definitions)
	var roll := _apply_noncombat_save_and_protection(target, spell, power_level, extra_save_adjust, force_affect, rng, duration, damage, tag_prefix)
	if roll.terminal_resolution != null:
		return roll.terminal_resolution
	damage = roll.damage
	_apply_noncombat_condition(target, spell, duration)
	damage = _apply_noncombat_special(target, spell, caste, rng, tag_prefix, duration, damage)
	var aging := _resolve_noncombat_aging(target, spell, power_level, duration, race, caste, rng, tag_prefix)
	_apply_noncombat_health(target, damage)
	var result := SpellResolution.new(true, false, roll.saved, 0, damage, duration, target.current_health <= -10)
	result.cleared_condition = condition_cure_index(spell) if special > 99 else -1
	result.aging = aging
	return result


func _apply_noncombat_save_and_protection(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, duration: int, damage: int, tag_prefix: String) -> NoncombatEffectRoll:
	var damage_type := absi(spell.damage_type)
	var saved := false
	if damage_type > 0 and damage_type < 8 and not force_affect and spell.cannot < 2:
		var save_target := target.save_value(damage_type) + power_level * (spell.save_adjust + extra_save_adjust) + spell.save_bonus
		saved = rng.draw(100, StringName("%s.save" % tag_prefix)) <= save_target
		if saved:
			if damage == 0:
				return NoncombatEffectRoll.new(0, true, SpellResolution.new(true, false, true, 0, 0, duration))
			damage /= 2
	if damage != 0 and damage_type > 0 and damage_type <= 6 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
		damage /= 2
	return NoncombatEffectRoll.new(damage, saved)


func _apply_noncombat_condition(target: CharacterState, spell: SpellDefinition, duration: int) -> void:
	var special := absi(spell.special)
	if special > 0 and special < 41:
		var condition_index := special - 1
		var current_condition := target.conditions.value(condition_index)
		if current_condition > -1 and current_condition + duration < 100:
			target.conditions.add(condition_index, duration)
	elif special > 99:
		var cured_condition := condition_cure_index(spell)
		if cured_condition >= 0:
			target.conditions.set_value(cured_condition, 0)


func _apply_noncombat_special(target: CharacterState, spell: SpellDefinition, caste: CasteDefinition, rng: RealmzRng, tag_prefix: String, duration: int, damage: int) -> int:
	var special := absi(spell.special)
	if special == 28:
		damage = duration
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
			target.conditions.clear_positive()
		64:
			if not target.conditions.is_active(ConditionRules.TURNED_TO_STONE) and (target.current_health < -9 or target.conditions.is_active(ConditionRules.ANIMATED)):
				target.conditions.set_value(ConditionRules.ANIMATED, 0)
				target.current_health = -9
		66:
			_apply_attribute_increase(target, spell.size, caste, rng, tag_prefix)
	return damage


func _resolve_noncombat_aging(target: CharacterState, spell: SpellDefinition, power_level: int, duration: int, race: RaceDefinition, caste: CasteDefinition, rng: RealmzRng, tag_prefix: String) -> CharacterAgingResult:
	var special := absi(spell.special)
	if race != null and caste != null and special in [24, 91]:
		var age_percent_months := power_level * 30 if special == 24 else duration * 30
		var added_days := int(float(race.max_age) * 0.01 * float(age_percent_months))
		return _characters.advance_age_days(target, race, caste, added_days)
	elif race != null and caste != null and special == 92:
		var youth_months := duration * 30
		var removed_days := int(float(race.max_age) * 0.01 * float(youth_months))
		var next_age := maxi(3_650, target.age_days - removed_days)
		var stamina_loss := rng.draw(3, StringName("%s.youth-stamina" % tag_prefix))
		target.maximum_health = maxi(1, target.maximum_health - stamina_loss)
		target.current_health = maxi(1, target.current_health - stamina_loss)
		return _characters.advance_age_days(target, race, caste, next_age - target.age_days)
	return null


func _apply_noncombat_health(target: CharacterState, damage: int) -> void:
	if damage < 0:
		target.current_health = mini(target.maximum_health, target.current_health - damage)
	elif damage > 0 and target.current_health >= 0 and target.current_health > -10:
		target.current_health -= damage
