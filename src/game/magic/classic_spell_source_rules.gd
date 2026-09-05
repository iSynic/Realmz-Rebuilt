## Recognizes Classic spell structures that are legal only from particular casting sources.

class_name ClassicSpellSourceRules
extends RefCounted


static func is_physical_projectile_profile(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.target_type == 1 and absi(spell.spell_class) == 9 and absi(spell.damage_type) == 9 and spell.special == 0


static func is_application_area_projectile_item_profile(spell: SpellDefinition) -> bool:
	return spell != null and ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_APPLICATION_EFFECT and spell.in_combat and spell.target_type == 3 and spell.size > 0 and spell.queue_icon == 0 and spell.cost == 0 and absi(spell.spell_class) == 9 and absi(spell.damage_type) == 9 and spell.special == 0 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func is_application_salt_item_profile(spell: SpellDefinition) -> bool:
	return spell != null and ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_APPLICATION_EFFECT and spell.in_combat and not spell.in_camp and spell.queue_icon == 0 and spell.target_type == 3 and spell.size == 4 and spell.cannot == 0 and spell.cost == -10 and absi(spell.spell_class) == 4 and absi(spell.damage_type) == 4 and absi(spell.special) == 28 and spell.damage_min == 5 and spell.damage_max == 5 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 2 and spell.duration_max == 2 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == -4 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == -10 and not spell.can_rotate and spell.fixed_target_count == 0


static func is_application_transport_projectile_item_profile(spell: SpellDefinition) -> bool:
	return spell != null and ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_APPLICATION_EFFECT and spell.in_combat and spell.target_type == -1 and spell.size == 1 and spell.queue_icon == 0 and spell.cost == 0 and absi(spell.spell_class) == 9 and absi(spell.damage_type) == 9 and absi(spell.special) == 56 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0


static func is_ordinary_combat_spell(spell: SpellDefinition) -> bool:
	var projectile_spell := absi(spell.spell_class) == 9
	var source_defined_projectile_spell := projectile_spell and spell.cost > 0 and absi(spell.damage_type) != 9
	return spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 8 and (not projectile_spell or source_defined_projectile_spell) and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func is_inert_self_duration_effect(spell: SpellDefinition) -> bool:
	return spell != null and ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_APPLICATION_EFFECT and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 5 and spell.cannot == 3 and spell.cost == 0 and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and spell.special == 0 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min > 0 and spell.duration_max >= spell.duration_min and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == 0 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == 0 and not spell.can_rotate and spell.fixed_target_count == 0


static func is_combat_application_elemental_attack(spell: SpellDefinition) -> bool:
	return spell != null and ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_APPLICATION_EFFECT and spell.in_combat and spell.queue_icon == 0 and spell.target_type in [1, 6] and spell.special == 0 and spell.cost == 0 and absi(spell.spell_class) == 9 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func is_field_encounter_utility_spell(spell: SpellDefinition) -> bool:
	return spell.in_camp and not spell.in_combat and spell.cost < 0 and spell.target_type in [0, 11] and spell.special == 0 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0
