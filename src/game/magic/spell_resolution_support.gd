## Shares deterministic spell targeting, effects, resistance, and scaling mechanics.

class_name SpellResolutionSupport
extends RefCounted



var _characters: CharacterRules
var _arithmetic: RealmzArithmetic
var _monsters: MonsterRules


func _init(character_rules: CharacterRules = null, realmz_arithmetic: RealmzArithmetic = null, monster_rules: MonsterRules = null) -> void:
	_characters = character_rules if character_rules != null else CharacterRules.new()
	_arithmetic = realmz_arithmetic if realmz_arithmetic != null else RealmzArithmetic.new()
	_monsters = monster_rules if monster_rules != null else MonsterRules.new()


func _resolve_character_spell_monster_target(caster: CharacterState, target: MonsterState, target_definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, polymorph_context: MonsterPolymorphContext = null, extra_to_hit_bonus: int = 0, use_projectile_defense: bool = false, ignore_magic_resistance: bool = false) -> SpellResolution:
	var rolled_damage := damage
	var resisted := false if ignore_magic_resistance else _monster_resists(caster.level, target, target_definition, spell, power_level, cast_level, rng, extra_to_hit_bonus, caster.missile, use_projectile_defense)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	if absi(spell.special) == 57:
		return _heal_monster(target, damage, duration, spell_cost)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, spell_cost, duration)
	if ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell):
		return _destroy_magic_monster(target, spell_cost, duration)
	if ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell):
		return _detect_monster_magic(target, spell_cost, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type < 8:
		var save_roll := rng.draw(100, &"magic.damage-save")
		# savevs consumes its roll first, then forces failure when cannot > 1.
		saved = spell.cannot <= 1 and save_roll <= (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1))
		if saved and rolled_damage == 0:
			return SpellResolution.new(true, false, true, spell_cost, 0, duration)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	var save_modifier := (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1)) if damage_type > 0 and damage_type < 8 else 0
	if save_modifier < 0:
		damage = int(float(damage) * (1.0 + float(absi(save_modifier)) / 100.0))
	if ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell):
		return _polymorph_monster(target, target_definition, spell_cost, duration, polymorph_context, rng)
	if ClassicSpellSpecialEffectRules.is_combat_destroy_turn_undead_spell(spell):
		return _destroy_or_turn_undead(caster, target, target_definition, spell_cost, duration, power_level, rng)
	if absi(spell.special) == 28:
		damage = duration
	if absi(spell.special) in [27, 49]:
		damage = _combat_death_damage(target.conditions, absi(spell.special), target.current_health)
	if absi(spell.special) == 59:
		return _restore_monster_spell_points(target, damage, duration, spell_cost, saved)
	if absi(spell.special) == 60:
		return _drain_monster_spell_points(target, damage, duration, spell_cost, saved)
	var traitor_before := target.traitor
	if ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell):
		target.traitor = caster.traitor
		target.target_id = ""
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, true)
	target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	_record_allegiance_change(result, traitor_before, target.traitor)
	return result


func _resolve_character_spell_character_target(caster: CharacterState, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, rng: RealmzRng, item_definitions: Array[ItemDefinition] = [], extra_to_hit_bonus: int = 0) -> SpellResolution:
	var rolled_damage := damage
	var resisted := character_resists(caster.level, target, spell, power_level, cast_level, rng, extra_to_hit_bonus)
	if resisted:
		return SpellResolution.new(true, true, false, 0, 0, duration)
	if absi(spell.special) == 57:
		return _heal_character(target, damage, duration, 0)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, 0, duration)
	if ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell):
		return _destroy_magic_character(target, 0, duration)
	if ClassicSpellSpecialEffectRules.is_combat_remove_curse_spell(spell):
		return _remove_curse_character(target, 0, duration, item_definitions)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type < 8:
		var save_roll := rng.draw(100, &"magic.damage-save")
		saved = spell.cannot <= 1 and save_roll <= target.save_value(damage_type - 1)
		if saved and rolled_damage == 0:
			return SpellResolution.new(true, false, true, 0, 0, duration)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	if absi(spell.special) == 28:
		damage = duration
	if absi(spell.special) in [27, 49]:
		damage = _combat_death_damage(target.conditions, absi(spell.special), target.current_health)
	if absi(spell.special) == 59:
		return _restore_character_spell_points(target, damage, duration, 0, saved)
	if absi(spell.special) == 60:
		return _drain_character_spell_points(target, damage, duration, 0, saved)
	var traitor_before := target.traitor
	if ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell):
		target.traitor = caster.traitor
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, false)
	_apply_combat_movement_effect(target, spell)
	target.current_health -= damage
	if absi(spell.special) == 28 and damage < 0:
		target.current_health = mini(target.maximum_health, target.current_health)
	var result := SpellResolution.new(true, false, saved, 0, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	_record_allegiance_change(result, traitor_before, target.traitor)
	return result


func character_resists(caster_level: int, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, extra_to_hit_bonus: int = 0) -> bool:
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
		return rng.draw(100, &"magic.missile-dodge") <= target.dodge - spell.to_hit_bonus - extra_to_hit_bonus
	return rng.draw(100, &"magic.resistance") <= target.magic_resistance + power_level * spell.resistance_adjust


func _resolve_character_selection(caster: CharacterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, item_definitions: Array[ItemDefinition] = [], polymorph_context: MonsterPolymorphContext = null) -> SpellResolution:
	if selection.kind == &"character":
		return _resolve_character_spell_character_target(caster, selection.character, spell, power_level, cast_level, damage, duration, rng, item_definitions)
	return _resolve_character_spell_monster_target(caster, selection.monster, selection.monster_definition, spell, power_level, cast_level, damage, duration, spell_cost, rng, polymorph_context)


func _resolve_monster_selection(caster: MonsterState, selection: SpellTargetSelection, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, save_tag: StringName, polymorph_context: MonsterPolymorphContext = null) -> SpellResolution:
	if selection.kind == &"character":
		return _resolve_monster_spell_character_target(caster, selection.character, spell, power_level, cast_level, damage, duration, spell_cost, rng, save_tag)
	return _resolve_monster_spell_monster_target(caster, selection.monster, selection.monster_definition, spell, power_level, cast_level, damage, duration, spell_cost, rng, save_tag, polymorph_context)


func _resolve_monster_spell_character_target(caster: MonsterState, target: CharacterState, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, save_tag: StringName) -> SpellResolution:
	var rolled_damage := damage
	var resisted := character_resists(caster.hit_dice, target, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	if absi(spell.special) == 57:
		return _heal_character(target, damage, duration, spell_cost)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, spell_cost, duration)
	if ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell):
		return _destroy_magic_character(target, spell_cost, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type < 8:
		var save_roll := rng.draw(100, save_tag)
		saved = spell.cannot <= 1 and save_roll <= target.save_value(damage_type - 1)
		if saved and rolled_damage == 0:
			return SpellResolution.new(true, false, true, spell_cost, 0, duration)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	if absi(spell.special) == 28:
		damage = duration
	if absi(spell.special) in [27, 49]:
		damage = _combat_death_damage(target.conditions, absi(spell.special), target.current_health)
	if absi(spell.special) == 59:
		return _restore_character_spell_points(target, damage, duration, spell_cost, saved)
	if absi(spell.special) == 60:
		return _drain_character_spell_points(target, damage, duration, spell_cost, saved)
	var traitor_before := target.traitor
	if ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell):
		target.traitor = caster.traitor
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, false)
	_apply_combat_movement_effect(target, spell)
	target.current_health -= damage
	if absi(spell.special) == 28 and damage < 0:
		target.current_health = mini(target.maximum_health, target.current_health)
	var result := SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	_record_allegiance_change(result, traitor_before, target.traitor)
	return result


func _resolve_monster_spell_monster_target(caster: MonsterState, target: MonsterState, target_definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, damage: int, duration: int, spell_cost: int, rng: RealmzRng, save_tag: StringName, polymorph_context: MonsterPolymorphContext = null) -> SpellResolution:
	var rolled_damage := damage
	var resisted := _monster_resists(caster.hit_dice, target, target_definition, spell, power_level, cast_level, rng)
	if resisted:
		return SpellResolution.new(true, true, false, spell_cost, 0, duration)
	if absi(spell.special) == 57:
		return _heal_monster(target, damage, duration, spell_cost)
	var cured_condition := condition_cure_index(spell)
	if cured_condition >= 0:
		return _clear_condition(target.conditions, cured_condition, spell_cost, duration)
	if ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell):
		return _destroy_magic_monster(target, spell_cost, duration)
	if ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell):
		return _detect_monster_magic(target, spell_cost, duration)
	var saved := false
	var damage_type := absi(spell.damage_type)
	if damage_type > 0 and damage_type < 8:
		var save_roll := rng.draw(100, save_tag)
		saved = spell.cannot <= 1 and save_roll <= (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1))
		if saved and rolled_damage == 0:
			return SpellResolution.new(true, false, true, spell_cost, 0, duration)
		if saved:
			damage /= 2
		if damage > 0 and target.conditions.is_active(ConditionRules.FIRE_PROTECTION + damage_type - 1):
			damage /= 2
	var save_modifier := (target.save_value(damage_type - 1) if target.has_runtime_saves() else target_definition.save_value(damage_type - 1)) if damage_type > 0 and damage_type < 8 else 0
	if save_modifier < 0:
		damage = int(float(damage) * (1.0 + float(absi(save_modifier)) / 100.0))
	if ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell):
		return _polymorph_monster(target, target_definition, spell_cost, duration, polymorph_context, rng)
	if absi(spell.special) == 28:
		damage = duration
	if absi(spell.special) in [27, 49]:
		damage = _combat_death_damage(target.conditions, absi(spell.special), target.current_health)
	if absi(spell.special) == 59:
		return _restore_monster_spell_points(target, damage, duration, spell_cost, saved)
	if absi(spell.special) == 60:
		return _drain_monster_spell_points(target, damage, duration, spell_cost, saved)
	var traitor_before := target.traitor
	if ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell):
		target.traitor = caster.traitor
		target.target_id = ""
	if rolled_damage != 0 and damage == 0:
		damage = 1
	var applied_condition := _apply_combat_condition(target.conditions, spell, duration, true)
	target.current_health -= damage
	var result := SpellResolution.new(true, false, saved, spell_cost, damage, duration, target.current_health <= 0)
	result.applied_condition = applied_condition
	_record_allegiance_change(result, traitor_before, target.traitor)
	return result


static func _selection_is_valid(selection: SpellTargetSelection) -> bool:
	return selection != null and ((selection.kind == &"character" and selection.character != null) or (selection.kind == &"monster" and selection.monster != null and selection.monster_definition != null))


func _polymorph_monster(target: MonsterState, target_definition: MonsterDefinition, spell_cost: int, duration: int, context: MonsterPolymorphContext, rng: RealmzRng) -> SpellResolution:
	var before := _monsters.polymorph_monster(target, target_definition, context, rng)
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	if not before.is_empty():
		result.transformed_definition_before = before
		result.transformed_definition_after = target.definition_id
	return result


static func _destroy_or_turn_undead(caster: CharacterState, target: MonsterState, definition: MonsterDefinition, spell_cost: int, duration: int, power_level: int, rng: RealmzRng) -> SpellResolution:
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	if not target.traitor or target.current_health <= 0 or definition.can_summon == -1 or not (definition.type_flag(1) or definition.type_flag(2)):
		return result
	result.special_threshold = maxi(25, 100 - (5 * power_level + 3 * caster.level) + 5 * target.hit_dice)
	result.special_roll = rng.draw(100, &"magic.destroy-turn-undead")
	var margin := result.special_roll - result.special_threshold
	if margin <= 0:
		result.special_result = &"resisted"
	elif margin < 30:
		result.special_result = &"destroyed"
		target.current_health = 0
		result.target_defeated = true
	else:
		result.special_result = &"turned"
		var traitor_before := target.traitor
		target.traitor = caster.traitor
		target.target_id = ""
		_record_allegiance_change(result, traitor_before, target.traitor)
	return result


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


static func _restore_character_spell_points(target: CharacterState, amount: int, duration: int, spell_cost: int, saved: bool) -> SpellResolution:
	var before := target.spell_points
	target.spell_points = mini(target.maximum_spell_points, target.spell_points + maxi(0, amount))
	var result := SpellResolution.new(true, false, saved, spell_cost, 0, duration)
	result.spell_point_delta = target.spell_points - before
	return result


static func _restore_monster_spell_points(target: MonsterState, amount: int, duration: int, spell_cost: int, saved: bool) -> SpellResolution:
	var before := target.spell_points
	target.spell_points = mini(target.maximum_spell_points, target.spell_points + maxi(0, amount))
	var result := SpellResolution.new(true, false, saved, spell_cost, 0, duration)
	result.spell_point_delta = target.spell_points - before
	return result


static func _drain_character_spell_points(target: CharacterState, amount: int, duration: int, spell_cost: int, saved: bool) -> SpellResolution:
	var before := target.spell_points
	target.spell_points = maxi(0, target.spell_points - maxi(0, amount))
	var result := SpellResolution.new(true, false, saved, spell_cost, 0, duration)
	result.spell_point_delta = target.spell_points - before
	return result


static func _drain_monster_spell_points(target: MonsterState, amount: int, duration: int, spell_cost: int, saved: bool) -> SpellResolution:
	var before := target.spell_points
	target.spell_points = maxi(0, target.spell_points - maxi(0, amount))
	var result := SpellResolution.new(true, false, saved, spell_cost, 0, duration)
	result.spell_point_delta = target.spell_points - before
	return result


static func _combat_death_damage(conditions: ConditionSet, special: int, current_health: int) -> int:
	if special == 27:
		conditions.set_value(ConditionRules.TURNED_TO_STONE, -1)
	return 10 + current_health


static func condition_cure_index(spell: SpellDefinition) -> int:
	if spell == null:
		return -1
	var index := absi(spell.special) - 101
	return index if index >= 0 and index < ConditionSet.CHARACTER_COUNT else -1


static func is_condition_cure_spell(spell: SpellDefinition) -> bool:
	return ClassicSpellConditionRules.is_combat_condition_cure_spell(spell)


static func _clear_condition(conditions: ConditionSet, condition_index: int, spell_cost: int, duration: int) -> SpellResolution:
	conditions.set_value(condition_index, 0)
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	result.cleared_condition = condition_index
	return result


static func _destroy_magic_character(target: CharacterState, spell_cost: int, duration: int) -> SpellResolution:
	var traitor_before := target.traitor
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	result.cleared_condition_count = target.conditions.clear_positive()
	# Castle stores charmed character allegiance outside the condition array; special 61 resets only character slots, not summoned or NPC monster slots.
	target.traitor = false
	_record_allegiance_change(result, traitor_before, target.traitor)
	return result


static func _remove_curse_character(target: CharacterState, spell_cost: int, duration: int, item_definitions: Array[ItemDefinition]) -> SpellResolution:
	target.conditions.set_value(ConditionRules.CURSED, 0)
	var definitions: Dictionary = {}
	for definition: ItemDefinition in item_definitions:
		definitions[definition.id] = definition
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	for instance: ItemInstance in target.inventory():
		var definition: ItemDefinition = definitions.get(instance.definition_id)
		if instance.equipped and definition != null and not definition.cursed_item_id.is_empty():
			instance.equipped = false
			result.unequipped_item_ids.append(instance.id)
	return result


static func _destroy_magic_monster(target: MonsterState, spell_cost: int, duration: int) -> SpellResolution:
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	result.cleared_condition_count = target.conditions.clear_positive()
	return result


static func _detect_monster_magic(target: MonsterState, spell_cost: int, duration: int) -> SpellResolution:
	var result := SpellResolution.new(true, false, false, spell_cost, 0, duration)
	result.detected_magic_item_count = target.mark_loot_magic_detected()
	return result


static func _apply_combat_condition(conditions: ConditionSet, spell: SpellDefinition, duration: int, monster_target: bool) -> int:
	var special := absi(spell.special) if spell != null else 0
	if special in [53, 54] and duration > 0:
		conditions.add(ConditionRules.HELPLESS, duration)
		return ConditionRules.HELPLESS
	var condition_index := ClassicSpellConditionRules.resolved_combat_condition_index(spell)
	if condition_index < 0 or duration == 0 and special != 28:
		return -1
	var current := conditions.value(condition_index)
	var updated := current + duration
	if current < 0 or monster_target and absi(updated) >= 125 or not monster_target and updated >= 100:
		return -1
	conditions.set_value(condition_index, updated)
	return condition_index


static func _apply_combat_movement_effect(target: CharacterState, spell: SpellDefinition) -> void:
	match ClassicSpellConditionRules.resolved_combat_condition_index(spell):
		ConditionRules.HELPLESS:
			target.movement = 0
		ConditionRules.TANGLED, ConditionRules.SLOW:
			target.movement /= 2
	if spell != null and absi(spell.special) in [53, 54]:
		target.attacks_remaining = 0


static func _record_allegiance_change(result: SpellResolution, before: bool, after: bool) -> void:
	result.target_traitor_before = before
	result.target_traitor_after = after
	result.allegiance_changed = before != after


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


func _monster_resists(caster_level: int, target: MonsterState, definition: MonsterDefinition, spell: SpellDefinition, power_level: int, cast_level: int, rng: RealmzRng, extra_to_hit_bonus: int = 0, caster_missile: int = 0, use_projectile_defense: bool = false) -> bool:
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
	if use_projectile_defense and absi(spell.spell_class) == 9:
		if target.conditions.is_active(ConditionRules.SHIELD_FROM_PROJECTILES):
			return true
		return rng.draw(100, &"magic.monster-missile-dodge") <= 10 + 5 * target.agility - caster_missile - spell.to_hit_bonus - extra_to_hit_bonus
	return rng.draw(100, &"magic.monster-resistance") <= target.magic_resistance + power_level * spell.resistance_adjust


func _scaled_roll(base_min: int, base_max: int, power_min: int, power_max: int, power_level: int, rng: RealmzRng, tag: StringName) -> int:
	return SpellRolls.scaled(base_min, base_max, power_min, power_max, power_level, rng, tag)


func _apply_attribute_increase(character: CharacterState, requested_attribute: int, caste: CasteDefinition, rng: RealmzRng, tag_prefix: String) -> void:
	var attribute := requested_attribute if requested_attribute != 0 else rng.draw(5, StringName("%s.attribute" % tag_prefix))
	match attribute:
		1:
			if character.brawn >= 25:
				return
			var maximum_bonus := caste.attributes.maximum_damage_bonus() if caste != null else 32_767
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
