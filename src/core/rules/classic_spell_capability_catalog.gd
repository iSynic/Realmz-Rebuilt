class_name ClassicSpellCapabilityCatalog
extends RefCounted

const ROLE_STOCK_PLAYER: StringName = &"stock-player"
const ROLE_APPLICATION_EFFECT: StringName = &"application-effect"
const ROLE_RESERVED_STANDARD: StringName = &"reserved-standard-slot"
const ROLE_UNKNOWN: StringName = &"unknown"
const FAMILY_RESERVED: StringName = &"reserved"
const FAMILY_ORDINARY: StringName = &"ordinary"
const FAMILY_HEALING: StringName = &"healing"
const FAMILY_CONDITION_CURE: StringName = &"condition-cure"
const FAMILY_SUMMONING: StringName = &"summoning"
const FAMILY_BATTLEFIELD_FIELD: StringName = &"battlefield-field"
const FAMILY_SPECIAL_EFFECT: StringName = &"special-effect"
const DISPOSITION_EXECUTABLE: StringName = &"executable"
const DISPOSITION_PENDING: StringName = &"unsupported-pending"
const DISPOSITION_NOT_APPLICABLE: StringName = &"not-applicable"


static func packed_family(spell: SpellDefinition) -> int:
	return spell.classic_id / 1000


static func packed_level(spell: SpellDefinition) -> int:
	return spell.classic_id % 1000 / 100


static func packed_slot(spell: SpellDefinition) -> int:
	return spell.classic_id % 100


static func application_role(spell: SpellDefinition) -> StringName:
	var family := packed_family(spell)
	var level := packed_level(spell)
	var slot := packed_slot(spell)
	if family in [1, 2, 3] and level in range(1, 8):
		return ROLE_STOCK_PLAYER if slot in range(1, 13) else ROLE_RESERVED_STANDARD if slot in range(13, 16) else ROLE_UNKNOWN
	if family == 4 and level in range(1, 8) and slot in range(1, 16):
		return ROLE_APPLICATION_EFFECT
	return ROLE_UNKNOWN


static func mechanical_family(spell: SpellDefinition) -> StringName:
	if spell == null:
		return FAMILY_SPECIAL_EFFECT
	if application_role(spell) == ROLE_RESERVED_STANDARD:
		return FAMILY_RESERVED
	if spell.queue_icon != 0:
		return FAMILY_BATTLEFIELD_FIELD
	var special := absi(spell.special)
	if special == 58 and spell.target_type == 0:
		return FAMILY_SUMMONING
	if special == 57:
		return FAMILY_HEALING
	if _condition_cure_index(spell) >= 0:
		return FAMILY_CONDITION_CURE
	if special == 0:
		return FAMILY_ORDINARY
	return FAMILY_SPECIAL_EFFECT


static func runtime_contexts(spell: SpellDefinition) -> Dictionary:
	return {
		"combatCharacter": String(_combat_character_disposition(spell)),
		"combatItem": String(_combat_item_disposition(spell)),
		"combatMonster": String(_combat_monster_disposition(spell)),
		"combatScroll": String(_combat_scroll_disposition(spell)),
		"fieldCharacter": String(_field_character_disposition(spell)),
	}


static func combat_character_disposition(spell: SpellDefinition) -> StringName:
	return _combat_character_disposition(spell)


static func combat_scroll_disposition(spell: SpellDefinition) -> StringName:
	return _combat_scroll_disposition(spell)


static func combat_item_disposition(spell: SpellDefinition) -> StringName:
	return _combat_item_disposition(spell)


static func combat_monster_disposition(spell: SpellDefinition) -> StringName:
	return _combat_monster_disposition(spell)


static func field_character_disposition(spell: SpellDefinition) -> StringName:
	return _field_character_disposition(spell)


static func is_ordinary_combat_spell(spell: SpellDefinition) -> bool:
	return _ordinary_combat_spell(spell)


static func is_combat_healing_spell(spell: SpellDefinition) -> bool:
	return _combat_healing_spell(spell)


static func is_combat_condition_cure_spell(spell: SpellDefinition) -> bool:
	return _combat_condition_cure_spell(spell)


static func is_combat_summon_spell(spell: SpellDefinition) -> bool:
	return _combat_summon_spell(spell)


static func is_combat_persistent_field_spell(spell: SpellDefinition) -> bool:
	return _combat_persistent_field_spell(spell)


static func unsupported_reason(spell: SpellDefinition, context_name: StringName) -> String:
	if spell == null:
		return "The spell definition is unavailable."
	if application_role(spell) == ROLE_RESERVED_STANDARD:
		return "This is a reserved Classic spell slot, not an executable spell."
	if String(context_name).begins_with("field-") and not spell.in_camp:
		return "This spell is not available in the Classic field/camp context."
	if context_name != &"field-character" and not spell.in_combat:
		return "This spell is not available in Classic combat."
	if spell.queue_icon != 0:
		return "This persistent battlefield-field spell is waiting for its collision and expiry lifecycle."
	if spell.can_rotate and spell.target_type in [3, 4] and context_name not in [&"combat-character", &"combat-scroll", &"combat-item"]:
		return "This casting source is waiting for the Classic rotatable-area orientation contract."
	var family := String(mechanical_family(spell)).replace("-", " ")
	var context_label := String(context_name).replace("-", " ")
	return "This Classic %s family is not executable for %s yet (special %d, target type %d)." % [family, context_label, absi(spell.special), spell.target_type]


static func _combat_character_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if spell.queue_icon != 0:
		return DISPOSITION_EXECUTABLE if _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 3, 4, 6, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) or _combat_summon_spell(spell) else DISPOSITION_PENDING


static func _combat_scroll_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if spell.queue_icon != 0:
		return DISPOSITION_EXECUTABLE if _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 2, 3, 4, 5, 6, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) or _combat_summon_spell(spell) else DISPOSITION_PENDING


static func _combat_item_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if spell.queue_icon != 0:
		return DISPOSITION_EXECUTABLE if _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [1, 2, 3, 4, 5, 6, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _combat_healing_spell(spell) else DISPOSITION_PENDING


static func _combat_monster_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if spell.queue_icon != 0:
		return DISPOSITION_EXECUTABLE if spell.cost > 0 and _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 3, 4, 6] or spell.target_type == 0 and spell.size != 0 or spell.cost <= 0:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) else DISPOSITION_PENDING


static func _field_character_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_camp or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	var special := absi(spell.special)
	if spell.target_type == 7:
		return DISPOSITION_EXECUTABLE if special == 50 or special >= 1 and special < ConditionSet.PARTY_COUNT else DISPOSITION_PENDING
	if special == 68:
		return DISPOSITION_EXECUTABLE
	if special > 0 and special < 41 or special in [48, 57, 59, 60, 61, 64, 66, 91, 92] or special > 99:
		return DISPOSITION_EXECUTABLE
	if special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0):
		return DISPOSITION_EXECUTABLE
	return DISPOSITION_PENDING


static func _ordinary_combat_spell(spell: SpellDefinition) -> bool:
	return spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 6 and absi(spell.spell_class) != 9 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func _combat_summon_spell(spell: SpellDefinition) -> bool:
	return spell != null and absi(spell.special) == 58 and spell.target_type == 0 and spell.queue_icon == 0


static func _combat_persistent_field_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.queue_icon == 0 or spell.queue_icon < -128 or spell.queue_icon > 127 or not spell.can_rotate or spell.target_type not in [3, 4] or spell.size < 1:
		return false
	var special := absi(spell.special)
	if special not in [0, 2]:
		return false
	var has_immediate_effect := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0 or special == 2
	var maximum_duration := maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max)
	return has_immediate_effect and maximum_duration > 0 and absi(spell.damage_type) <= 7


static func _combat_healing_spell(spell: SpellDefinition) -> bool:
	if spell == null or absi(spell.special) != 57 or not spell.in_combat or spell.queue_icon != 0 or spell.target_type != 1 or spell.cannot != 4 or spell.cost <= 0:
		return false
	if absi(spell.spell_class) != 8 or absi(spell.damage_type) != 8:
		return false
	if spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0:
		return false
	if spell.damage_min < 0 or spell.damage_max < 0 or spell.power_damage_min < 0 or spell.power_damage_max < 0:
		return false
	return spell.damage_min > 0 or spell.damage_max > 0 or spell.power_damage_min > 0 or spell.power_damage_max > 0


static func _combat_condition_cure_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [0, 1, 5] and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and _condition_cure_index(spell) >= 0


static func _condition_cure_index(spell: SpellDefinition) -> int:
	var index := absi(spell.special) - 101 if spell != null else -1
	return index if index >= 0 and index < ConditionSet.CHARACTER_COUNT else -1


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
