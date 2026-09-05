## Resolves character-cast combat spell targeting and repeated casts.

class_name CharacterSpellResolver
extends SpellResolutionSupport

func resolve_character_targeted_spell(caster: CharacterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
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
	var resolution := _resolve_character_selection(caster, effective, spell, power_level, cast_level, damage, duration, spell_cost, rng, [], polymorph_context)
	result.append_target(effective.id, effective.kind, resolution, effective.original_target_id, effective.reflected)
	return result


func roll_persistent_field_duration(spell: SpellDefinition, power_level: int, rng: RealmzRng, tag: StringName) -> int:
	if spell == null or rng == null or spell.queue_icon == 0 or power_level < 1:
		return 0
	return _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, tag)


func resolve_character_group_spell(caster: CharacterState, character_targets: Array[CharacterState], monster_targets: Array[MonsterState], monster_definitions: Array[MonsterDefinition], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, allow_empty: bool = false, spend_spell_points: bool = true, polymorph_context: MonsterPolymorphContext = null) -> GroupSpellResolution:
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
		result.append_target(target.id, &"monster", _resolve_character_spell_monster_target(caster, target, definition, spell, power_level, cast_level, damage, duration, 0, rng, polymorph_context))
	return result


func resolve_character_area_projectile_item(caster: CharacterState, caste: CasteDefinition, projectile_item: ItemDefinition, character_targets: Array[CharacterState], monster_targets: Array[MonsterState], monster_definitions: Array[MonsterDefinition], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng) -> GroupSpellResolution:
	if caster == null or projectile_item == null or spell == null or rng == null or power_level < 1 or monster_targets.size() != monster_definitions.size() or not ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell):
		return null
	for target: CharacterState in character_targets:
		if target == null:
			return null
	for index: int in monster_targets.size():
		if monster_targets[index] == null or monster_definitions[index] == null:
			return null
	var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, &"combat.item-projectile.duration")
	var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, &"combat.item-projectile.damage") + projectile_item.damage_bonus
	if caste != null and caste.gets_missile_bonus:
		damage += rng.draw_between(1, maxi(1, caster.level / 2), &"combat.item-projectile.caste-bonus")
	var extra_to_hit_bonus := 5 * projectile_item.damage_bonus
	var result := GroupSpellResolution.new(true, 0, duration, damage)
	for target: CharacterState in character_targets:
		result.append_target(target.id, &"character", _resolve_character_spell_character_target(caster, target, spell, power_level, cast_level, damage, duration, rng, [], extra_to_hit_bonus))
	for index: int in monster_targets.size():
		var target := monster_targets[index]
		result.append_target(target.id, &"monster", _resolve_character_spell_monster_target(caster, target, monster_definitions[index], spell, power_level, cast_level, damage, duration, 0, rng, null, extra_to_hit_bonus, true))
	return result


func resolve_character_repeated_spell(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true, before_selection: Callable = Callable(), item_definitions: Array[ItemDefinition] = []) -> RepeatedSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or selections.is_empty() or selections.size() > power_level:
		return null
	return _resolve_character_selection_sequence(caster, selections, spell, power_level, cast_level, rng, spend_spell_points, true, &"magic.repeated", before_selection, item_definitions)


func resolve_character_ray_spell(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool = true) -> RepeatedSpellResolution:
	if caster == null or spell == null or rng == null or power_level < 1 or selections.is_empty():
		return null
	return _resolve_character_selection_sequence(caster, selections, spell, power_level, cast_level, rng, spend_spell_points, false, &"magic.ray")


func _resolve_character_selection_sequence(caster: CharacterState, selections: Array[SpellTargetSelection], spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, spend_spell_points: bool, allow_reflection: bool, rng_tag: StringName, before_selection: Callable = Callable(), item_definitions: Array[ItemDefinition] = []) -> RepeatedSpellResolution:
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
		if before_selection.is_valid():
			before_selection.call(index)
		var selection := selections[index]
		if allow_reflection and not is_condition_cure_spell(spell):
			selection = _reflect_to_character_caster(caster, selection, rng, StringName("%s.reflect.%d" % [rng_tag, index]))
		var duration := _scaled_roll(spell.duration_min, spell.duration_max, spell.power_duration_min, spell.power_duration_max, power_level, rng, StringName("%s.duration.%d" % [rng_tag, index]))
		var damage := _scaled_roll(spell.damage_min, spell.damage_max, spell.power_damage_min, spell.power_damage_max, power_level, rng, StringName("%s.damage.%d" % [rng_tag, index]))
		if not selection.reflected and selection.kind == &"monster" and selection.monster.magic_resistance > 100:
			result.exclude_target(selection.original_target_id)
			continue
		var resolution := _resolve_character_selection(caster, selection, spell, power_level, cast_level, damage, duration, 0, rng, item_definitions)
		result.append_target(selection.id, selection.kind, resolution, selection.original_target_id, selection.reflected)
	return result
