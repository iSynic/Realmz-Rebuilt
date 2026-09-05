## Resolves monster-cast combat spells and targeting sequences.

class_name MonsterSpellResolver
extends SpellResolutionSupport

func resolve_monster_targeted_spell(caster: MonsterState, caster_definition: MonsterDefinition, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
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
	var resolution := _resolve_monster_selection(caster, effective, spell, power_level, cast_level, damage, duration, spell_cost, rng, &"magic.monster-spell.damage-save", polymorph_context)
	result.append_target(effective.id, effective.kind, resolution, effective.original_target_id, effective.reflected)
	return result


func resolve_monster_group_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_empty: bool = false, spend_spell_points: bool = true, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
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
		var resolution := _resolve_monster_selection(caster, selection, spell, power_level, cast_level, damage, duration, 0, rng, &"magic.monster-group.damage-save", polymorph_context)
		result.append_target(selection.id, selection.kind, resolution, selection.original_target_id, false)
	return result


func resolve_monster_repeated_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, before_selection: Callable = Callable()) -> RepeatedSpellResolution:
	if caster == null or caster_definition == null or spell == null or rng == null or power_level < 1 or selections.is_empty() or selections.size() > power_level:
		return null
	return _resolve_monster_selection_sequence(caster, caster_definition, selections, spell, power_level, cast_level, rng, true, &"magic.monster-repeated", before_selection)


func resolve_monster_ray_spell(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> RepeatedSpellResolution:
	if caster == null or caster_definition == null or spell == null or rng == null or power_level < 1 or selections.is_empty():
		return null
	return _resolve_monster_selection_sequence(caster, caster_definition, selections, spell, power_level, cast_level, rng, false, &"magic.monster-ray")


func _resolve_monster_selection_sequence(caster: MonsterState, caster_definition: MonsterDefinition, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_reflection: bool, rng_tag: StringName, before_selection: Callable = Callable()) -> RepeatedSpellResolution:
	for selection: SpellTargetSelection in selections:
		if not _selection_is_valid(selection):
			return null
	var spell_cost := spell.cost * power_level
	if spell_cost < 0 or caster.spell_points < spell_cost:
		return RepeatedSpellResolution.new(false, maxi(0, spell_cost), selections.size())
	caster.spell_points -= spell_cost
	var result := RepeatedSpellResolution.new(true, spell_cost, selections.size())
	for index: int in selections.size():
		if before_selection.is_valid():
			before_selection.call(index)
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
