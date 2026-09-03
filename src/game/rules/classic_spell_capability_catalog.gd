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
const FAMILY_PROJECTILE: StringName = &"projectile"
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
	if _physical_projectile_profile(spell) or _application_area_projectile_item_profile(spell) or _application_transport_projectile_item_profile(spell):
		return FAMILY_PROJECTILE
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
		"characterProjectile": String(_character_projectile_disposition(spell)),
		"fieldCharacter": String(_field_character_disposition(spell)),
		"monsterProjectile": String(_monster_projectile_disposition(spell)),
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


static func character_projectile_disposition(spell: SpellDefinition) -> StringName:
	return _character_projectile_disposition(spell)


static func monster_projectile_disposition(spell: SpellDefinition) -> StringName:
	return _monster_projectile_disposition(spell)


static func is_physical_projectile_profile(spell: SpellDefinition) -> bool:
	return _physical_projectile_profile(spell)


static func is_application_area_projectile_item_profile(spell: SpellDefinition) -> bool:
	return _application_area_projectile_item_profile(spell)


static func is_application_transport_projectile_item_profile(spell: SpellDefinition) -> bool:
	return _application_transport_projectile_item_profile(spell)


static func is_combat_application_elemental_attack(spell: SpellDefinition) -> bool:
	return _combat_application_elemental_attack(spell)


static func is_ordinary_combat_spell(spell: SpellDefinition) -> bool:
	return _ordinary_combat_spell(spell)


static func is_inert_self_duration_effect(spell: SpellDefinition) -> bool:
	return _inert_self_duration_effect(spell)


static func is_combat_healing_spell(spell: SpellDefinition) -> bool:
	return _combat_healing_spell(spell)


static func is_combat_condition_cure_spell(spell: SpellDefinition) -> bool:
	return _combat_condition_cure_spell(spell)


static func is_combat_condition_effect_spell(spell: SpellDefinition) -> bool:
	return _combat_condition_effect_spell(spell)


static func combat_condition_effect_index(spell: SpellDefinition) -> int:
	return _combat_condition_index(spell) if _combat_condition_effect_spell(spell) or _combat_actor_field_spell(spell) else -1


static func resolved_combat_condition_index(spell: SpellDefinition) -> int:
	return _combat_condition_index(spell)


static func is_combat_helpless_spell(spell: SpellDefinition) -> bool:
	return _combat_helpless_spell(spell)


static func is_combat_repeated_field_spell(spell: SpellDefinition) -> bool:
	return _combat_repeated_field_spell(spell)


static func is_combat_single_actor_field_spell(spell: SpellDefinition) -> bool:
	return _combat_single_actor_field_spell(spell)


static func is_combat_summon_spell(spell: SpellDefinition) -> bool:
	return _combat_summon_spell(spell)


static func is_combat_death_spell(spell: SpellDefinition) -> bool:
	return _combat_death_spell(spell)


static func is_combat_spell_point_restore_spell(spell: SpellDefinition) -> bool:
	return _combat_spell_point_restore_spell(spell)


static func is_combat_spell_point_drain_spell(spell: SpellDefinition) -> bool:
	return _combat_spell_point_drain_spell(spell)


static func is_combat_destroy_magic_spell(spell: SpellDefinition) -> bool:
	return _combat_destroy_magic_spell(spell)


static func is_combat_remove_curse_spell(spell: SpellDefinition) -> bool:
	return _combat_remove_curse_spell(spell)


static func is_combat_magic_detection_spell(spell: SpellDefinition) -> bool:
	return _combat_magic_detection_spell(spell)


static func is_combat_charm_spell(spell: SpellDefinition) -> bool:
	return _combat_charm_spell(spell)


static func is_combat_polymorph_spell(spell: SpellDefinition) -> bool:
	return _combat_polymorph_spell(spell)


static func is_combat_destroy_turn_undead_spell(spell: SpellDefinition) -> bool:
	return _combat_destroy_turn_undead_spell(spell)


static func is_combat_phase_spell(spell: SpellDefinition) -> bool:
	return _combat_phase_spell(spell)


static func is_combat_persistent_field_spell(spell: SpellDefinition) -> bool:
	return _combat_persistent_field_spell(spell)


static func combat_persistent_field_condition_index(spell: SpellDefinition) -> int:
	return _combat_condition_index(spell) if _combat_persistent_field_spell(spell) else -1


static func combat_spell_uses_persistent_field_queue(spell: SpellDefinition) -> bool:
	return spell != null and spell.queue_icon != 0 and spell.target_type != 6 and spell.target_type <= 8


static func unsupported_reason(spell: SpellDefinition, context_name: StringName) -> String:
	if spell == null:
		return "The spell definition is unavailable."
	if application_role(spell) == ROLE_RESERVED_STANDARD:
		return "This is a reserved Classic spell slot, not an executable spell."
	if String(context_name).begins_with("field-") and not spell.in_camp:
		return "This spell is not available in the Classic field/camp context."
	if context_name != &"field-character" and not spell.in_combat:
		return "This spell is not available in Classic combat."
	if combat_spell_uses_persistent_field_queue(spell):
		return "This persistent battlefield-field spell is waiting for its collision and expiry lifecycle."
	if spell.can_rotate and spell.target_type in [3, 4] and context_name not in [&"combat-character", &"combat-scroll", &"combat-item"]:
		return "This casting source is waiting for the Classic rotatable-area orientation contract."
	var family := String(mechanical_family(spell)).replace("-", " ")
	var context_label := String(context_name).replace("-", " ")
	return "This Classic %s family is not executable for %s yet (special %d, target type %d)." % [family, context_label, absi(spell.special), spell.target_type]


static func _combat_character_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if _physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_area_projectile_item_profile(spell) or _application_salt_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_transport_projectile_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_application_elemental_attack(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE
	if combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _inert_self_duration_effect(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) or _combat_condition_effect_spell(spell) or _combat_death_spell(spell) or _combat_spell_point_restore_spell(spell) or _combat_spell_point_drain_spell(spell) or _combat_destroy_magic_spell(spell) or _combat_remove_curse_spell(spell) or _combat_charm_spell(spell) or _combat_polymorph_spell(spell) or _combat_destroy_turn_undead_spell(spell) or _combat_phase_spell(spell) or _combat_summon_spell(spell) else DISPOSITION_PENDING


static func _combat_scroll_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if _physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_area_projectile_item_profile(spell) or _application_salt_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_transport_projectile_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_application_elemental_attack(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE
	if combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _inert_self_duration_effect(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) or _combat_condition_effect_spell(spell) or _combat_death_spell(spell) or _combat_spell_point_restore_spell(spell) or _combat_spell_point_drain_spell(spell) or _combat_destroy_magic_spell(spell) or _combat_remove_curse_spell(spell) or _combat_charm_spell(spell) or _combat_polymorph_spell(spell) or _combat_destroy_turn_undead_spell(spell) or _combat_phase_spell(spell) or _combat_summon_spell(spell) else DISPOSITION_PENDING


static func _combat_item_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if _physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_area_projectile_item_profile(spell) or _application_salt_item_profile(spell):
		return DISPOSITION_EXECUTABLE
	if _application_transport_projectile_item_profile(spell):
		return DISPOSITION_EXECUTABLE
	if _combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE
	if combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _inert_self_duration_effect(spell) or _combat_application_elemental_attack(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) or _combat_condition_effect_spell(spell) or _combat_death_spell(spell) or _combat_spell_point_restore_spell(spell) or _combat_spell_point_drain_spell(spell) or _combat_destroy_magic_spell(spell) or _combat_remove_curse_spell(spell) or _combat_charm_spell(spell) or _combat_polymorph_spell(spell) or _combat_destroy_turn_undead_spell(spell) or _combat_phase_spell(spell) or _combat_summon_spell(spell) else DISPOSITION_PENDING


static func _combat_monster_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if _physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_area_projectile_item_profile(spell) or _application_salt_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _application_transport_projectile_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_application_elemental_attack(spell):
		return DISPOSITION_EXECUTABLE
	if _combat_remove_curse_spell(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_phase_spell(spell) or spell.target_type == 7:
		return DISPOSITION_NOT_APPLICABLE
	if _combat_destroy_turn_undead_spell(spell):
		return DISPOSITION_NOT_APPLICABLE
	if _combat_summon_spell(spell):
		return DISPOSITION_EXECUTABLE if spell.cost >= 0 else DISPOSITION_PENDING
	if _combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE if spell.cost > 0 else DISPOSITION_PENDING
	if combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if spell.cost >= 0 and _combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 3, 4, 5, 6, 9, 10, 12] or spell.target_type == 0 and spell.size != 0 or spell.cost < 0:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _ordinary_combat_spell(spell) or _inert_self_duration_effect(spell) or _combat_healing_spell(spell) or _combat_condition_cure_spell(spell) or _combat_condition_effect_spell(spell) or _combat_death_spell(spell) or _combat_spell_point_restore_spell(spell) or _combat_spell_point_drain_spell(spell) or _combat_destroy_magic_spell(spell) or _combat_charm_spell(spell) or _combat_polymorph_spell(spell) else DISPOSITION_PENDING


static func _field_character_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_camp or application_role(spell) == ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	var special := absi(spell.special)
	if special == 68:
		return DISPOSITION_EXECUTABLE
	if spell.target_type == 7:
		return DISPOSITION_EXECUTABLE if special == 0 or special == 50 or special >= 1 and special < ConditionSet.PARTY_COUNT else DISPOSITION_PENDING
	if _field_encounter_utility_spell(spell):
		return DISPOSITION_EXECUTABLE
	if _inert_self_duration_effect(spell):
		return DISPOSITION_EXECUTABLE
	if special > 0 and special < 41 or special in [48, 57, 59, 60, 61, 62, 63, 64, 66, 91, 92] or special > 99:
		return DISPOSITION_EXECUTABLE
	if special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0):
		return DISPOSITION_EXECUTABLE
	return DISPOSITION_PENDING


static func _field_encounter_utility_spell(spell: SpellDefinition) -> bool:
	return spell.in_camp and not spell.in_combat and spell.cost < 0 and spell.target_type in [0, 11] and spell.special == 0 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0


static func _character_projectile_disposition(spell: SpellDefinition) -> StringName:
	return DISPOSITION_EXECUTABLE if _physical_projectile_profile(spell) else DISPOSITION_NOT_APPLICABLE


static func _monster_projectile_disposition(spell: SpellDefinition) -> StringName:
	return DISPOSITION_EXECUTABLE if _physical_projectile_profile(spell) else DISPOSITION_NOT_APPLICABLE


static func _physical_projectile_profile(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.target_type == 1 and absi(spell.spell_class) == 9 and absi(spell.damage_type) == 9 and spell.special == 0


static func _application_area_projectile_item_profile(spell: SpellDefinition) -> bool:
	return spell != null and application_role(spell) == ROLE_APPLICATION_EFFECT and spell.in_combat and spell.target_type == 3 and spell.size > 0 and spell.queue_icon == 0 and spell.cost == 0 and absi(spell.spell_class) == 9 and absi(spell.damage_type) == 9 and spell.special == 0 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func _application_salt_item_profile(spell: SpellDefinition) -> bool:
	return spell != null and application_role(spell) == ROLE_APPLICATION_EFFECT and spell.in_combat and not spell.in_camp and spell.queue_icon == 0 and spell.target_type == 3 and spell.size == 4 and spell.cannot == 0 and spell.cost == -10 and absi(spell.spell_class) == 4 and absi(spell.damage_type) == 4 and absi(spell.special) == 28 and spell.damage_min == 5 and spell.damage_max == 5 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 2 and spell.duration_max == 2 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == -4 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == -10 and not spell.can_rotate and spell.fixed_target_count == 0


static func _application_transport_projectile_item_profile(spell: SpellDefinition) -> bool:
	return spell != null and application_role(spell) == ROLE_APPLICATION_EFFECT and spell.in_combat and spell.target_type == -1 and spell.size == 1 and spell.queue_icon == 0 and spell.cost == 0 and absi(spell.spell_class) == 9 and absi(spell.damage_type) == 9 and absi(spell.special) == 56 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0


static func _ordinary_combat_spell(spell: SpellDefinition) -> bool:
	var projectile_spell := absi(spell.spell_class) == 9
	var source_defined_projectile_spell := projectile_spell and spell.cost > 0 and absi(spell.damage_type) != 9
	return spell.special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 8 and (not projectile_spell or source_defined_projectile_spell) and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func _inert_self_duration_effect(spell: SpellDefinition) -> bool:
	return spell != null and application_role(spell) == ROLE_APPLICATION_EFFECT and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 5 and spell.cannot == 3 and spell.cost == 0 and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and spell.special == 0 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min > 0 and spell.duration_max >= spell.duration_min and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == 0 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == 0 and not spell.can_rotate and spell.fixed_target_count == 0


static func _combat_application_elemental_attack(spell: SpellDefinition) -> bool:
	return spell != null and application_role(spell) == ROLE_APPLICATION_EFFECT and spell.in_combat and spell.queue_icon == 0 and spell.target_type in [1, 6] and spell.special == 0 and spell.cost == 0 and absi(spell.spell_class) == 9 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0)


static func _combat_summon_spell(spell: SpellDefinition) -> bool:
	return spell != null and absi(spell.special) == 58 and spell.target_type == 0 and spell.queue_icon == 0


static func _combat_polymorph_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.queue_icon != 0 or spell.size != 0 or spell.cannot != 0 or spell.cost <= 0 or absi(spell.spell_class) != 7 or absi(spell.damage_type) != 7 or absi(spell.special) != 46 or spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0 or spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0 or spell.range_min != 8 or spell.range_max != 0 or spell.save_adjust != 0 or spell.to_hit_bonus != 0 or spell.can_rotate or spell.fixed_target_count != 0:
		return false
	return spell.target_type == 1 and spell.cost == 20 and spell.save_bonus == 10 and spell.resistance_adjust == -3 or spell.target_type == 4 and spell.cost == 80 and spell.save_bonus == 5 and spell.resistance_adjust == 0


static func _combat_destroy_turn_undead_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and not spell.in_camp and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 10 and spell.cannot == 2 and spell.cost == 30 and absi(spell.spell_class) == 7 and absi(spell.damage_type) == 7 and absi(spell.special) == 90 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == 0 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == 0 and not spell.can_rotate and spell.fixed_target_count == 0


static func _combat_death_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and absi(spell.special) in [27, 49]


static func _combat_spell_point_restore_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [1, 5] and absi(spell.special) == 59 and maxi(spell.damage_max, spell.power_damage_max) > 0


static func _combat_spell_point_drain_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [0, 1, 6] and spell.cannot == 0 and spell.cost > 0 and absi(spell.spell_class) == 7 and absi(spell.damage_type) == 7 and absi(spell.special) == 60


static func _combat_destroy_magic_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 0 and spell.cannot in [3, 4] and spell.cost > 0 and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and absi(spell.special) == 61 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0


static func _combat_remove_curse_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_camp and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type == 0 and spell.cannot == 4 and spell.cost > 0 and absi(spell.spell_class) == 7 and absi(spell.damage_type) == 7 and absi(spell.special) == 62 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and spell.range_min == 1 and spell.range_max == 0 and spell.save_adjust == 0 and spell.save_bonus == 0 and spell.resistance_adjust == 0 and spell.to_hit_bonus == 0 and not spell.can_rotate and spell.fixed_target_count == 0


static func _combat_magic_detection_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon != 0 and spell.queue_icon >= -128 and spell.queue_icon <= 127 and spell.size == 0 and spell.target_type in [1, 4] and spell.cannot == 3 and spell.cost >= 0 and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and absi(spell.special) == 63 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max) > 0


static func _combat_charm_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and absi(spell.special) in [51, 52]


static func _combat_phase_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.target_type == 8 and absi(spell.special) == 56


static func _combat_persistent_field_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.queue_icon == 0 or spell.queue_icon < -128 or spell.queue_icon > 127 or spell.target_type not in [3, 4, 5] or spell.target_type == 3 and spell.size < 1:
		return false
	var special := absi(spell.special)
	var has_damage := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0
	var maximum_duration := maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max)
	var supported_condition := _combat_helpless_spell(spell) if special in [53, 54] else _combat_condition_index(spell) >= 0
	var supported_effect := special == 0 and has_damage and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 8 or supported_condition or _combat_magic_detection_spell(spell)
	return maximum_duration > 0 and supported_effect


static func _combat_helpless_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or absi(spell.special) not in [53, 54] or spell.target_type not in [0, 4, 10] or spell.target_type == 0 and spell.size != 0:
		return false
	return maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max) > 0


static func _combat_repeated_field_spell(spell: SpellDefinition) -> bool:
	return _combat_actor_field_spell(spell) and spell.target_type == 0


static func _combat_single_actor_field_spell(spell: SpellDefinition) -> bool:
	return _combat_actor_field_spell(spell) and spell.target_type == 1


static func _combat_actor_field_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or spell.target_type not in [0, 1] or spell.size != 0 or spell.queue_icon == 0 or spell.queue_icon < -128 or spell.queue_icon > 127:
		return false
	var special := absi(spell.special)
	var maximum_duration := maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max)
	var has_damage := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0
	var supported_condition := _combat_helpless_spell(spell) if special in [53, 54] else _combat_condition_index(spell) >= 0
	return maximum_duration > 0 and (special == 0 and has_damage and absi(spell.damage_type) >= 1 and absi(spell.damage_type) <= 7 or supported_condition or _combat_magic_detection_spell(spell))


static func _combat_healing_spell(spell: SpellDefinition) -> bool:
	if spell == null or absi(spell.special) != 57 or not spell.in_combat or spell.queue_icon != 0 or spell.target_type not in [1, 5]:
		return false
	if spell.target_type == 1 and (spell.cannot != 4 or spell.cost <= 0 or absi(spell.spell_class) != 8) or spell.target_type == 5 and (spell.cannot != 3 or spell.cost != 0 or absi(spell.spell_class) != 7) or absi(spell.damage_type) != 8:
		return false
	if spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0:
		return false
	if spell.damage_min < 0 or spell.damage_max < 0 or spell.power_damage_min < 0 or spell.power_damage_max < 0:
		return false
	return spell.damage_min > 0 or spell.damage_max > 0 or spell.power_damage_min > 0 or spell.power_damage_max > 0


static func _combat_condition_cure_spell(spell: SpellDefinition) -> bool:
	return spell != null and spell.in_combat and spell.queue_icon == 0 and spell.size == 0 and spell.target_type in [0, 1, 5] and absi(spell.spell_class) == 8 and absi(spell.damage_type) == 8 and spell.damage_min == 0 and spell.damage_max == 0 and spell.power_damage_min == 0 and spell.power_damage_max == 0 and spell.duration_min == 0 and spell.duration_max == 0 and spell.power_duration_min == 0 and spell.power_duration_max == 0 and _condition_cure_index(spell) >= 0


static func _combat_condition_effect_spell(spell: SpellDefinition) -> bool:
	if spell == null or not spell.in_combat or combat_spell_uses_persistent_field_queue(spell):
		return false
	if absi(spell.special) == 28:
		return spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0
	var maximum_duration := maxi(spell.duration_min, spell.duration_max) + 7 * maxi(spell.power_duration_min, spell.power_duration_max)
	var has_damage := spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0; var has_duration := spell.duration_min != 0 or spell.duration_max != 0 or spell.power_duration_min != 0 or spell.power_duration_max != 0
	var supported_condition := _combat_helpless_spell(spell) if absi(spell.special) in [53, 54] else _combat_condition_index(spell) >= 0
	return supported_condition and (has_damage or has_duration)


static func _combat_condition_index(spell: SpellDefinition) -> int:
	var special := absi(spell.special) if spell != null else 0
	if special == 253:
		special = 3
	if special in [53, 54]:
		return ConditionRules.HELPLESS
	return special - 1 if special >= 1 and special < 41 else -1


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
