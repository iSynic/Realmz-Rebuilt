class_name MagicRules
extends RefCounted

var _characters: CharacterRules
var _arithmetic: RealmzArithmetic


func _init(character_rules: CharacterRules = null, realmz_arithmetic: RealmzArithmetic = null) -> void:
	_characters = character_rules if character_rules != null else CharacterRules.new()
	_arithmetic = realmz_arithmetic if realmz_arithmetic != null else RealmzArithmetic.new()


func resolve_character_targeted_spell(caster: CharacterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true) -> GroupSpellResolution:
	if caster == null or not _selection_is_valid(selection) or spell == null or rng == null or power_level < 1:
		return null
	var spell_cost := absi(spell.cost * power_level)
	if spend_spell_points and caster.spell_points < spell_cost:
		return GroupSpellResolution.new(false, spell_cost, 0, 0)
	if spend_spell_points:
		caster.spell_points -= spell_cost
	else:
		spell_cost = 0
	var effective := selection if is_condition_cure_spell(spell) else _reflect_to_character_caster(caster, selection, rng, &"magic.reflect")
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"magic.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"magic.damage")
	var result := GroupSpellResolution.new(true, spell_cost, duration, damage)
	if not effective.reflected and effective.kind == &"monster" and effective.monster.magic_resistance > 100:
		return result
	var resolution := _resolve_character_selection(caster, effective, spell, power_level, cast_level, damage, duration, spell_cost, rng)
	result.append_target(effective.id, effective.kind, resolution, effective.original_target_id, effective.reflected)
	return result


func roll_persistent_field_duration(spell: SpellDefinition, power_level: int, rng: RealmzRng, tag: StringName) -> int:
	if spell == null or rng == null or spell.queue_icon == 0 or power_level < 1:
		return 0
	return _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, tag)


func resolve_character_group_spell(caster: CharacterState, character_targets: Array[CharacterState], monster_targets: Array[MonsterState], monster_definitions: Array[MonsterDefinition], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_empty: bool = false, spend_spell_points: bool = true) -> GroupSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or monster_targets.size() != monster_definitions.size() or not allow_empty and character_targets.is_empty() and monster_targets.is_empty():
		return null
	for target: CharacterState in character_targets:
		if target == null:
			return null
	for index: int in monster_targets.size():
		if monster_targets[index] == null or monster_definitions[index] == null:
			return null
	var spell_cost := absi(spell.cost * power_level)
	if spend_spell_points and caster.spell_points < spell_cost:
		return GroupSpellResolution.new(false, spell_cost, 0, 0)
	if spend_spell_points:
		caster.spell_points -= spell_cost
	else:
		spell_cost = 0
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"magic.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"magic.damage")
	var result := GroupSpellResolution.new(true, spell_cost, duration, damage)
	for target: CharacterState in character_targets:
		result.append_target(target.id, &"character", _resolve_character_spell_character_target(caster, target, spell, power_level, cast_level, damage, duration, rng))
	for index: int in monster_targets.size():
		var target := monster_targets[index]
		var definition := monster_definitions[index]
		result.append_target(target.id, &"monster", _resolve_character_spell_monster_target(caster.level, target, definition, spell, power_level, cast_level, damage, duration, 0, rng))
	return result


func resolve_character_repeated_spell(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true) -> RepeatedSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or selections.is_empty() or selections.size() > power_level:
		return null
	return _resolve_character_selection_sequence(caster, selections, spell, power_level, cast_level, rng, spend_spell_points, true, &"magic.repeated")


func resolve_character_ray_spell(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true) -> RepeatedSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or selections.is_empty():
		return null
	return _resolve_character_selection_sequence(caster, selections, spell, power_level, cast_level, rng, spend_spell_points, false, &"magic.ray")


func _resolve_character_selection_sequence(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool, allow_reflection: bool, rng_tag: StringName) -> RepeatedSpellResolution:
	for selection: SpellTargetSelection in selections:
		if selection == null or (selection.character == null and (selection.monster == null or selection.monster_definition == null)):
			return null
	var spell_cost := absi(spell.cost * power_level)
	if spend_spell_points and caster.spell_points < spell_cost:
		return RepeatedSpellResolution.new(false, spell_cost, selections.size())
	if spend_spell_points:
		caster.spell_points -= spell_cost
	else:
		spell_cost = 0
	var result := RepeatedSpellResolution.new(true, spell_cost, selections.size())
	for index: int in selections.size():
		var selection := selections[index]
		if allow_reflection and not is_condition_cure_spell(spell):
			selection = _reflect_to_character_caster(caster, selection, rng, StringName("%s.reflect.%d" % [rng_tag, index]))
		var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration.%d" % [rng_tag, index]))
		var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage.%d" % [rng_tag, index]))
		if not selection.reflected and selection.kind == &"monster" and selection.monster.magic_resistance > 100:
			result.exclude_target(selection.original_target_id)
			continue
		var resolution := _resolve_character_selection(caster, selection, spell, power_level, cast_level, damage, duration, 0, rng)
		result.append_target(selection.id, selection.kind, resolution, selection.original_target_id, selection.reflected)
	return result


func _resolve_character_spell_monster_target(caster_level: int, target: MonsterState, target_definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng) -> SpellResolution:
	var rolled_damage := damage
	var resisted := _monster_resists(caster_level, target, target_definition, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	if absi(spell.special) == 57:
		return _heal_monster(target, damage, duration, spell_cost)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, spell_cost, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type <= 6:
		var save_roll := rng.draw(100, &"magic.damage-save")
		# savevs consumes its roll first, then forces failure when cannot > 1.
		saved = spell.cannot <= 1 and save_roll <= (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1))
		if saved and rolled_damage == 0:
			return SpellResolution.new(true, false, true, spell_cost, 0, duration)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	var save_modifier := (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1)) if damage_type > 0 and damage_type <= 6 else 0
	if save_modifier < 0:
		damage = int(float(damage) * (1.0 + float(absi(save_modifier)) / 100.0))
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, true)
	target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	return result


func _resolve_character_spell_character_target(caster: CharacterState, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, rng: RealmzRng) -> SpellResolution:
	var rolled_damage := damage
	var resisted := character_resists(caster.level, target, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, 0, 0, duration)
	if absi(spell.special) == 57:
		return _heal_character(target, damage, duration, 0)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, 0, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type <= 6:
		var save_roll := rng.draw(100, &"magic.damage-save")
		saved = spell.cannot <= 1 and save_roll <= target.save_value(damage_type - 1)
		if saved and rolled_damage == 0:
			return SpellResolution.new(true, false, true, 0, 0, duration)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, false)
	target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, 0, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	return result


func resolve_character_projectile(caster: CharacterState, caste: CasteDefinition, projectile_item: ItemDefinition, target: MonsterState, spell: SpellDefinition, power_level: int, rng: RealmzRng) -> ProjectileResolution:
	if caster == null or projectile_item == null or target == null or spell == null or rng == null or power_level < 0 or absi(spell.spell_class) != 9 or absi(spell.damage_type) != 9 or spell.special != 0:
		return null
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"combat.projectile.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"combat.projectile.damage")
	damage += projectile_item.damage_bonus
	var effective_to_hit := spell.to_hit_bonus + 5 * projectile_item.damage_bonus
	if caste != null and caste.gets_missile_bonus:
		damage += rng.draw_between(1, maxi(1, caster.level / 2), &"combat.projectile.caste-bonus")
	var hit_count := 0
	var miss_count := 0
	var total_damage := 0
	var maximum_hits := maxi(1, spell.fixed_target_count)
	for hit_index: int in maximum_hits:
		if target.conditions.is_active(ConditionRules.SHIELD_FROM_PROJECTILES):
			miss_count += 1
			break
		var miss_chance := 10 + 5 * target.agility - caster.missile - effective_to_hit
		if rng.draw(100, StringName("combat.projectile.miss.%d" % hit_index)) <= miss_chance:
			miss_count += 1
			break
		target.current_health -= damage
		hit_count += 1
		total_damage += damage
		if target.current_health <= 0:
			break
	return ProjectileResolution.new(true, hit_count, miss_count, total_damage, damage, duration, target.current_health <= 0)


func resolve_monster_projectile(caster: MonsterState, projectile_item: ItemDefinition, target: CharacterState, spell: SpellDefinition, power_level: int, rng: RealmzRng) -> ProjectileResolution:
	if caster == null or projectile_item == null or target == null or spell == null or rng == null or power_level < 0 or absi(spell.spell_class) != 9 or absi(spell.damage_type) != 9 or spell.special != 0:
		return null
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"combat.monster-projectile.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"combat.monster-projectile.damage")
	damage += projectile_item.damage_bonus
	var effective_to_hit := spell.to_hit_bonus + 5 * projectile_item.damage_bonus
	var miss_count := 0
	if target.conditions.is_active(ConditionRules.SHIELD_FROM_PROJECTILES):
		miss_count = 1
	elif rng.draw(100, &"combat.monster-projectile.miss") <= target.dodge - effective_to_hit:
		miss_count = 1
	if miss_count > 0:
		return ProjectileResolution.new(true, 0, miss_count, 0, damage, duration, false)
	target.current_health -= damage
	return ProjectileResolution.new(true, 1, 0, damage, damage, duration, target.current_health <= 0)


func character_resists(caster_level: int, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> bool:
	if spell.spell_class == 0:
		if rng.draw(100, &"magic.charm-save") <= target.save_value(0) + power_level * spell.save_adjust:
			return true
	if spell.damage_type < 0 and absi(spell.damage_type) != 9:
		var direct_chance := 35 + 5 * target.level - 5 * caster_level + power_level * spell.save_adjust
		if rng.draw(100, &"magic.direct-resist") <= direct_chance:
			return true
	if (spell.cannot == 1 or spell.cannot > 2) and absi(spell.spell_class) != 9:
		return false
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


func resolve_monster_targeted_spell(caster: MonsterState, caster_definition: MonsterDefinition, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> GroupSpellResolution:
	if caster == null or caster_definition == null or not _selection_is_valid(selection) or spell == null or rng == null or power_level < 1:
		return null
	var spell_cost := spell.cost * power_level
	if spell_cost < 0 or caster.spell_points < spell_cost:
		return GroupSpellResolution.new(false, maxi(0, spell_cost), 0, 0)
	caster.spell_points -= spell_cost
	var effective := selection if is_condition_cure_spell(spell) else _reflect_to_monster_caster(caster, caster_definition, selection, rng, &"magic.monster-spell.reflect")
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"magic.monster-spell.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"magic.monster-spell.damage")
	var result := GroupSpellResolution.new(true, spell_cost, duration, damage)
	if not effective.reflected and effective.kind == &"monster" and effective.monster.magic_resistance > 100:
		return result
	var resolution := _resolve_monster_selection(caster, effective, spell, power_level, cast_level, damage, duration, spell_cost, rng, &"magic.monster-spell.damage-save")
	result.append_target(effective.id, effective.kind, resolution, effective.original_target_id, effective.reflected)
	return result


func resolve_monster_group_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_empty: bool = false, spend_spell_points: bool = true) -> GroupSpellResolution:
	if caster == null or caster_definition == null or spell == null or rng == null or power_level < 1 or not allow_empty and selections.is_empty():
		return null
	for selection: SpellTargetSelection in selections:
		if not _selection_is_valid(selection):
			return null
	var spell_cost := spell.cost * power_level
	if spell_cost < 0 or spend_spell_points and caster.spell_points < spell_cost:
		return GroupSpellResolution.new(false, maxi(0, spell_cost), 0, 0)
	if spend_spell_points:
		caster.spell_points -= spell_cost
	else:
		spell_cost = 0
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"magic.monster-group.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"magic.monster-group.damage")
	var result := GroupSpellResolution.new(true, spell_cost, duration, damage)
	for selection: SpellTargetSelection in selections:
		if selection.kind == &"monster" and selection.monster.magic_resistance > 100:
			continue
		var resolution := _resolve_monster_selection(caster, selection, spell, power_level, cast_level, damage, duration, 0, rng, &"magic.monster-group.damage-save")
		result.append_target(selection.id, selection.kind, resolution, selection.original_target_id, false)
	return result


func resolve_monster_repeated_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> RepeatedSpellResolution:
	if caster == null or caster_definition == null or spell == null or rng == null or power_level < 1 or selections.is_empty() or selections.size() > power_level:
		return null
	return _resolve_monster_selection_sequence(caster, caster_definition, selections, spell, power_level, cast_level, rng, true, &"magic.monster-repeated")


func resolve_monster_ray_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> RepeatedSpellResolution:
	if caster == null or caster_definition == null or spell == null or rng == null or power_level < 1 or selections.is_empty():
		return null
	return _resolve_monster_selection_sequence(caster, caster_definition, selections, spell, power_level, cast_level, rng, false, &"magic.monster-ray")


func _resolve_monster_selection_sequence(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_reflection: bool, rng_tag: StringName) -> RepeatedSpellResolution:
	for selection: SpellTargetSelection in selections:
		if not _selection_is_valid(selection):
			return null
	var spell_cost := spell.cost * power_level
	if spell_cost < 0 or caster.spell_points < spell_cost:
		return RepeatedSpellResolution.new(false, maxi(0, spell_cost), selections.size())
	caster.spell_points -= spell_cost
	var result := RepeatedSpellResolution.new(true, spell_cost, selections.size())
	for index: int in selections.size():
		var selection := selections[index]
		if allow_reflection and not is_condition_cure_spell(spell):
			selection = _reflect_to_monster_caster(caster, caster_definition, selection, rng, StringName("%s.reflect.%d" % [rng_tag, index]))
		var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration.%d" % [rng_tag, index]))
		var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage.%d" % [rng_tag, index]))
		if not selection.reflected and selection.kind == &"monster" and selection.monster.magic_resistance > 100:
			result.exclude_target(selection.original_target_id)
			continue
		var save_tag := StringName("%s.damage-save.%d" % [rng_tag, index])
		var resolution := _resolve_monster_selection(caster, selection, spell, power_level, cast_level, damage, duration, 0, rng, save_tag)
		result.append_target(selection.id, selection.kind, resolution, selection.original_target_id, selection.reflected)
	return result


func _resolve_character_selection(caster: CharacterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng) -> SpellResolution:
	if selection.kind == &"character":
		return _resolve_character_spell_character_target(caster, selection.character, spell, power_level, cast_level, damage, duration, rng)
	return _resolve_character_spell_monster_target(caster.level, selection.monster, selection.monster_definition, spell, power_level, cast_level, damage, duration, spell_cost, rng)


func _resolve_monster_selection(caster: MonsterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, save_tag: StringName) -> SpellResolution:
	if selection.kind == &"character":
		return _resolve_monster_spell_character_target(caster.hit_dice, selection.character, spell, power_level, cast_level, damage, duration, spell_cost, rng, save_tag)
	return _resolve_monster_spell_monster_target(caster.hit_dice, selection.monster, selection.monster_definition, spell, power_level, cast_level, damage, duration, spell_cost, rng, save_tag)


func _resolve_monster_spell_character_target(caster_level: int, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, save_tag: StringName) -> SpellResolution:
	var rolled_damage := damage
	var resisted := character_resists(caster_level, target, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	if absi(spell.special) == 57:
		return _heal_character(target, damage, duration, spell_cost)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, spell_cost, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type <= 6:
		var save_roll := rng.draw(100, save_tag)
		saved = spell.cannot <= 1 and save_roll <= target.save_value(damage_type - 1)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, false)
	target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	return result


func _resolve_monster_spell_monster_target(caster_level: int, target: MonsterState, target_definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, save_tag: StringName) -> SpellResolution:
	var rolled_damage := damage
	var resisted := _monster_resists(caster_level, target, target_definition, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	if absi(spell.special) == 57:
		return _heal_monster(target, damage, duration, spell_cost)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, spell_cost, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type <= 6:
		var save_roll := rng.draw(100, save_tag)
		saved = spell.cannot <= 1 and save_roll <= (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1))
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	var save_modifier := (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1)) if damage_type > 0 and damage_type <= 6 else 0
	if save_modifier < 0:
		damage = int(float(damage) * (1.0 + float(absi(save_modifier)) / 100.0))
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, true)
	target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	return result


static func _selection_is_valid(selection: SpellTargetSelection) -> bool:
	return selection != null and ((selection.kind == &"character" and selection.character != null) or (selection.kind == &"monster" and selection.monster != null and selection.monster_definition != null))


static func _heal_character(target: CharacterState, amount: int, duration: int, spell_cost: int) -> SpellResolution:
	if target.conditions.is_active(ConditionRules.TURNED_TO_STONE) or target.current_health <= -10:
		return SpellResolution.new(true, false, false, spell_cost, 0, duration)
	var before := target.current_health
	target.current_health = mini(target.maximum_health, target.current_health + maxi(0, amount))
	return SpellResolution.new(true, false, false, spell_cost, -(target.current_health - before), duration)


func _heal_monster(target: MonsterState, amount: int, duration: int, spell_cost: int) -> SpellResolution:
	var healed := maxi(0, amount)
	target.current_health = _arithmetic.signed_16(target.current_health + healed)
	return SpellResolution.new(true, false, false, spell_cost, -healed, duration)


static func condition_cure_index(spell: SpellDefinition) -> int:
	if spell == null:
		return -1
	var index := absi(spell.special) - 101
	return index if index >= 0 and index < ConditionSet.CHARACTER_COUNT else -1


static func is_condition_cure_spell(spell: SpellDefinition) -> bool:
	return ClassicSpellCapabilityCatalog.is_combat_condition_cure_spell(spell)


static func _clear_condition(conditions: ConditionSet, condition_index: int, spell_cost: int, duration: int) -> SpellResolution:
	conditions.set_value(condition_index, 0)
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	result.cleared_condition = condition_index
	return result


static func _apply_combat_condition(conditions: ConditionSet, spell: SpellDefinition, duration: int, monster_target: bool) -> int:
	var special := absi(spell.special) if spell != null else 0
	if special < 1 or special >= 41 or special == 28 or duration <= 0:
		return -1
	var condition_index := special - 1
	var current := conditions.value(condition_index)
	var updated := current + duration
	if current < 0 or monster_target and absi(updated) >= 125 or not monster_target and updated >= 100:
		return -1
	conditions.set_value(condition_index, updated)
	return condition_index


static func _selection_reflects(selection: SpellTargetSelection, rng: RealmzRng, tag: StringName) -> bool:
	if selection.kind == &"character":
		return selection.character.conditions.is_active(ConditionRules.REFLECTING_SPELLS) and rng.draw(100, tag) < 34
	return selection.monster.conditions.is_active(ConditionRules.REFLECTING_SPELLS) and rng.draw(100, tag) < 34


static func _reflect_to_character_caster(caster: CharacterState, selection: SpellTargetSelection, rng: RealmzRng, tag: StringName) -> SpellTargetSelection:
	if not _selection_reflects(selection, rng, tag):
		return selection
	return SpellTargetSelection.for_character(caster, selection.original_target_id, true)


static func _reflect_to_monster_caster(caster: MonsterState, caster_definition: MonsterDefinition, selection: SpellTargetSelection, rng: RealmzRng, tag: StringName) -> SpellTargetSelection:
	if not _selection_reflects(selection, rng, tag):
		return selection
	return SpellTargetSelection.for_monster(caster, caster_definition, selection.original_target_id, true)


func resolve_field_spell(caster: CharacterState, targets: Array[CharacterState], spell: SpellDefinition, power_level: int, rng: RealmzRng, castes: Array[CasteDefinition] = [], races: Array[RaceDefinition] = [], spend_spell_points: bool = true, allow_empty: bool = false) -> GroupSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or not allow_empty and targets.is_empty():
		return null
	if not castes.is_empty() and castes.size() != targets.size() or not races.is_empty() and races.size() != targets.size():
		return null
	for target: CharacterState in targets:
		if target == null:
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
		var resolution := _resolve_noncombat_character_effect(target, spell, power_level, 0, false, rng, caste, race, duration, damage, "%s.%s" % [tag_prefix, target.id])
		result.append_target(target.id, &"character", resolution)
	return result


func resolve_scenario_spell(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, caste: CasteDefinition = null, race: RaceDefinition = null) -> SpellResolution:
	if target == null or spell == null or rng == null or power_level < 0:
		return null
	var tag_prefix := "scenario-spell.%d.%s" % [spell.classic_id, target.id]
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration" % tag_prefix))
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage" % tag_prefix))
	return _resolve_noncombat_character_effect(target, spell, power_level, extra_save_adjust, force_affect, rng, caste, race, duration, damage, tag_prefix)


func _resolve_noncombat_character_effect(target: CharacterState, spell: SpellDefinition, power_level: int, extra_save_adjust: int, force_affect: bool, rng: RealmzRng, caste: CasteDefinition, race: RaceDefinition, duration: int, damage: int, tag_prefix: String) -> SpellResolution:
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
		var cured_condition := condition_cure_index(spell)
		if cured_condition >= 0:
			target.conditions.set_value(cured_condition, 0)
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
	var aging: CharacterAgingResult = null
	if race != null and caste != null and special in [24, 91]:
		var age_percent_months := power_level * 30 if special == 24 else duration * 30
		var added_days := int(float(race.max_age) * 0.01 * float(age_percent_months))
		aging = _characters.advance_age_days(target, race, caste, added_days)
	elif race != null and caste != null and special == 92:
		var youth_months := duration * 30
		var removed_days := int(float(race.max_age) * 0.01 * float(youth_months))
		var next_age := maxi(3_650, target.age_days - removed_days)
		var stamina_loss := rng.draw(3, StringName("%s.youth-stamina" % tag_prefix))
		target.maximum_health = maxi(1, target.maximum_health - stamina_loss)
		target.current_health = maxi(1, target.current_health - stamina_loss)
		aging = _characters.advance_age_days(target, race, caste, next_age - target.age_days)
	if damage < 0:
		target.current_health = mini(target.maximum_health, target.current_health - damage)
	elif damage > 0 and target.current_health >= 0 and target.current_health > -10:
		target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, 0, damage, duration, target.current_health <= -10)
	result.cleared_condition = condition_cure_index(spell) if special > 99 else -1
	result.aging = aging
	return result


func _monster_resists(caster_level: int, target: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> bool:
	if spell.spell_class == 0:
		var charm_chance := 35 + 4 * target.hit_dice
		charm_chance += 5 if definition.type_flag(0) else 0
		charm_chance += 5 if definition.type_flag(5) else 0
		if rng.draw(100, &"magic.monster-charm") <= charm_chance + power_level * spell.save_adjust:
			return true
	if spell.damage_type < 0 and absi(spell.damage_type) != 9:
		var direct_chance := 35 + 5 * target.hit_dice - 5 * caster_level + power_level * spell.save_adjust
		if rng.draw(100, &"magic.monster-direct-resist") <= direct_chance:
			return true
	if spell.spell_class >= 0 and spell.spell_class < 6 and (definition.spell_immune(spell.spell_class) or target.magic_resistance > 100):
		return true
	if (spell.cannot == 1 or spell.cannot > 2) and absi(spell.spell_class) != 9:
		return false
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
