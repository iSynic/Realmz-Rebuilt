## Recognizes source-backed Classic spell records with non-condition special effects.

class_name ClassicSpellSpecialEffectRules
extends RefCounted


static func is_combat_summon_spell(spell: SpellDefinition) -> bool:
	return spell != null and absi(spell.special) == 58 and spell.target_type == 0 and spell.queue_icon == 0


static func is_combat_polymorph_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.queue_icon != 0 or spell.size != 0 or spell.cannot != 0 or spell.cost <= 0 or absi(spell.spell_class) != 7 or absi(spell.damage_type) != 7 or absi(spell.special) != 46 or spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0 or spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0 or spell.range_min != 8 or spell.range_max != 0 or spell.save_adjust != 0 or spell.to_hit_bonus != 0 or spell.can_rotate or spell.fixed_target_count != 0:
		return false
	return spell.target_type == 1 and spell.cost == 20 and spell.save_bonus == 10 and spell.resistance_adjust == -3 or spell.target_type == 4 and spell.cost == 80 and spell.save_bonus == 5 and spell.resistance_adjust == 0


static func is_combat_destroy_turn_undead_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and not spell.in_camp and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 10 and spell.cannot == 2 and spell.cost == 30 and absi(spell.spell_class) == 7 and absi(spell.damage_type) == 7 and absi(spell.special) == 90 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == 0 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == 0 and not spell.can_rotate and spell.fixed_target_count == 0


static func is_combat_death_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and absi(spell.special) in [27, 49]


static func is_combat_spell_point_restore_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [1, 5] and absi(spell.special) == 59 and maxi(spell.damage_max, spell.power_damage_max) > 0


static func is_combat_spell_point_drain_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [0, 1, 6] and spell.cannot == 0 and spell.cost > 0 and absi(spell.spell_class) == 7 and absi(spell.damage_type) == 7 and absi(spell.special) == 60


static func is_combat_destroy_magic_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 0 and spell.cannot in [3, 4] and spell.cost > 0 and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and absi(spell.special) == 61 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0


static func is_combat_remove_curse_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_camp and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 0 and spell.cannot == 4 and spell.cost > 0 and absi(spell.spell_class) == 7 and absi(spell.damage_type) == 7 and absi(spell.special) == 62 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == 1 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == 0 and not spell.can_rotate and spell.fixed_target_count == 0


static func is_combat_magic_detection_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon != 0 and spell.queue_icon >= -128 and spell.queue_icon <= 127 and spell.size == 0 and spell.target_type in [1, 4] and spell.cannot == 3 and spell.cost >= 0 and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and absi(spell.special) == 63 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max) > 0


static func is_combat_charm_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and absi(spell.special) in [51, 52]


static func is_combat_phase_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.target_type == 8 and absi(spell.special) == 56
