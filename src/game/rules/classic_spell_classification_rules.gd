## Derives mechanical families and behavior signatures from Classic spell records.

class_name ClassicSpellClassificationRules
extends RefCounted

const FAMILY_RESERVED: StringName = &"reserved"
const FAMILY_ORDINARY: StringName = &"ordinary"
const FAMILY_HEALING: StringName = &"healing"
const FAMILY_CONDITION_CURE: StringName = &"condition-cure"
const FAMILY_SUMMONING: StringName = &"summoning"
const FAMILY_BATTLEFIELD_FIELD: StringName = &"battlefield-field"
const FAMILY_PROJECTILE: StringName = &"projectile"
const FAMILY_SPECIAL_EFFECT: StringName = &"special-effect"


static func mechanical_family(spell: SpellDefinition) -> StringName:
	if spell == null:
		return FAMILY_SPECIAL_EFFECT
	if ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return FAMILY_RESERVED
	if spell.queue_icon != 0:
		return FAMILY_BATTLEFIELD_FIELD
	if ClassicSpellSourceRules.is_physical_projectile_profile(spell) or ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell) or ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		return FAMILY_PROJECTILE
	var special := absi(spell.special)
	if ClassicSpellSpecialEffectRules.is_combat_summon_spell(spell):
		return FAMILY_SUMMONING
	if special == 57:
		return FAMILY_HEALING
	if ClassicSpellConditionRules.condition_cure_index(spell) >= 0:
		return FAMILY_CONDITION_CURE
	if special == 0:
		return FAMILY_ORDINARY
	return FAMILY_SPECIAL_EFFECT


static func behavior_signature(spell: SpellDefinition) -> Dictionary:
	return {
		"canRotate": spell.can_rotate,
		"cannot": spell.cannot,
		"cost": spell.cost,
		"damage": {
			"maximum": spell.damage_max,
			"minimum": spell.damage_min,
			"powerMaximum": spell.power_damage_max,
			"powerMinimum": spell.power_damage_min,
			"type": spell.damage_type,
		},
		"duration": {
			"maximum": spell.duration_max,
			"minimum": spell.duration_min,
			"powerMaximum": spell.power_duration_max,
			"powerMinimum": spell.power_duration_min,
		},
		"fixedTargetCount": spell.fixed_target_count,
		"inCamp": spell.in_camp,
		"inCombat": spell.in_combat,
		"queueIcon": spell.queue_icon,
		"range": {"maximum": spell.range_max, "minimum": spell.range_min},
		"resistanceAdjust": spell.resistance_adjust,
		"saveAdjust": spell.save_adjust,
		"saveBonus": spell.save_bonus,
		"size": spell.size,
		"special": spell.special,
		"spellClass": spell.spell_class,
		"targetType": spell.target_type,
		"toHitBonus": spell.to_hit_bonus,
	}
