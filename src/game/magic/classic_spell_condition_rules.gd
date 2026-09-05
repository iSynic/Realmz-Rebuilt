## Recognizes Classic healing, condition, and persistent battlefield spell structures.

class_name ClassicSpellConditionRules
extends RefCounted


static func is_combat_persistent_field_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.queue_icon == 0 or spell.queue_icon < -128 or spell.queue_icon > 127 or spell.target_type not in [3, 4, 5] or spell.target_type == 3 and spell.size < 1:
		return false
	var special := absi(spell.special)
	var has_damage := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0
	var maximum_duration := maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max)
	var supported_condition := is_combat_helpless_spell(spell) if special in [53, 54] else resolved_combat_condition_index(spell) >= 0
	var supported_effect := special == 0 and has_damage and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 8 or supported_condition or ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell)
	return maximum_duration > 0 and supported_effect


static func is_combat_helpless_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or absi(spell.special) not in [53, 54] or spell.target_type not in [0, 4, 10] or spell.target_type == 0 and spell.size != 0:
		return false
	return maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max) > 0


static func is_combat_repeated_field_spell(spell: SpellDefinition) -> bool:
	return is_combat_actor_field_spell(spell) and spell.target_type == 0


static func is_combat_single_actor_field_spell(spell: SpellDefinition) -> bool:
	return is_combat_actor_field_spell(spell) and spell.target_type == 1


static func is_combat_actor_field_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.target_type not in [0, 1] or spell.size != 0 or spell.queue_icon == 0 or spell.queue_icon < -128 or spell.queue_icon > 127:
		return false
	var special := absi(spell.special)
	var maximum_duration := maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max)
	var has_damage := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0
	var supported_condition := is_combat_helpless_spell(spell) if special in [53, 54] else resolved_combat_condition_index(spell) >= 0
	return maximum_duration > 0 and (special == 0 and has_damage and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 7 or supported_condition or ClassicSpellSpecialEffectRules.is_combat_magic_detection_spell(spell))


static func is_combat_healing_spell(spell: SpellDefinition) -> bool:
	if spell == null or absi(spell.special) != 57 or not spell.in_combat or spell.queue_icon != 0 or spell.target_type not in [1, 5]:
		return false
	if spell.target_type == 1 and (spell.cannot != 4 or spell.cost <= 0 or absi(spell.spell_class) != 8) or spell.target_type == 5 and (spell.cannot != 3 or spell.cost != 0 or absi(spell.spell_class) != 7) or absi(spell.damage_type) != 8:
		return false
	if spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0:
		return false
	if spell.damage_min < 0 or spell.damage_max < 0 or spell.power_damage_min < 0 or spell.power_damage_max < 0:
		return false
	return spell.damage_min > 0 or spell.damage_max > 0 or spell.power_damage_min > 0 or spell.power_damage_max > 0


static func is_combat_condition_cure_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [0, 1, 5] and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and condition_cure_index(spell) >= 0


static func is_combat_condition_effect_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or combat_spell_uses_persistent_field_queue(spell):
		return false
	if absi(spell.special) == 28:
		return spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0
	var has_damage := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0
	var has_duration := spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0
	var supported_condition := is_combat_helpless_spell(spell) if absi(spell.special) in [53, 54] else resolved_combat_condition_index(spell) >= 0
	return supported_condition and (has_damage or has_duration)


static func combat_condition_effect_index(spell: SpellDefinition) -> int:
	return resolved_combat_condition_index(spell) if is_combat_condition_effect_spell(spell) or is_combat_actor_field_spell(spell) else -1


static func resolved_combat_condition_index(spell: SpellDefinition) -> int:
	var special := absi(spell.special) if spell != null else 0
	if special == 253:
		special = 3
	if special in [53, 54]:
		return ConditionRules.HELPLESS
	return special - 1 if special >= 1 and special < 41 else -1


static func condition_cure_index(spell: SpellDefinition) -> int:
	var index := absi(spell.special) - 101 if spell != null else -1
	return index if index >= 0 and index < ConditionSet.CHARACTER_COUNT else -1


static func combat_persistent_field_condition_index(spell: SpellDefinition) -> int:
	return resolved_combat_condition_index(spell) if is_combat_persistent_field_spell(spell) else -1


static func combat_spell_uses_persistent_field_queue(spell: SpellDefinition) -> bool:
	return spell != null and spell.queue_icon != 0 and spell.target_type != 6 and spell.target_type <= 8
