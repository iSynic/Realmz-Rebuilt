## Decides which Classic casting sources can execute a spell record.

class_name ClassicSpellDispositionRules
extends RefCounted

const DISPOSITION_EXECUTABLE: StringName = &"executable"
const DISPOSITION_PENDING: StringName = &"unsupported-pending"
const DISPOSITION_NOT_APPLICABLE: StringName = &"not-applicable"


static func runtime_contexts(spell: SpellDefinition) -> Dictionary:
	return {
		"combatCharacter": String(combat_character_disposition(spell)),
		"combatItem": String(combat_item_disposition(spell)),
		"combatMonster": String(combat_monster_disposition(spell)),
		"combatScroll": String(combat_scroll_disposition(spell)),
		"characterProjectile": String(character_projectile_disposition(spell)),
		"fieldCharacter": String(field_character_disposition(spell)),
		"monsterProjectile": String(monster_projectile_disposition(spell)),
	}


static func combat_character_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell) or ClassicSpellSourceRules.is_application_salt_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_combat_application_elemental_attack(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellConditionRules.is_combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellConditionRules.combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 3, 4, 5, 6, 7, 8, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _is_character_source_effect(spell) else DISPOSITION_PENDING


static func combat_scroll_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell) or ClassicSpellSourceRules.is_application_salt_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_combat_application_elemental_attack(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellConditionRules.is_combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellConditionRules.combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _is_character_source_effect(spell) else DISPOSITION_PENDING


static func combat_item_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell) or ClassicSpellSourceRules.is_application_salt_item_profile(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellConditionRules.is_combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellConditionRules.combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _is_character_source_effect(spell) or ClassicSpellSourceRules.is_combat_application_elemental_attack(spell) else DISPOSITION_PENDING


static func combat_monster_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_combat or ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_physical_projectile_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_area_projectile_item_profile(spell) or ClassicSpellSourceRules.is_application_salt_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_application_transport_projectile_item_profile(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSourceRules.is_combat_application_elemental_attack(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellSpecialEffectRules.is_combat_remove_curse_spell(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) or spell.target_type == 7:
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSpecialEffectRules.is_combat_destroy_turn_undead_spell(spell):
		return DISPOSITION_NOT_APPLICABLE
	if ClassicSpellSpecialEffectRules.is_combat_summon_spell(spell):
		return DISPOSITION_EXECUTABLE if spell.cost >= 0 else DISPOSITION_PENDING
	if ClassicSpellConditionRules.is_combat_actor_field_spell(spell):
		return DISPOSITION_EXECUTABLE if spell.cost > 0 else DISPOSITION_PENDING
	if ClassicSpellConditionRules.combat_spell_uses_persistent_field_queue(spell):
		return DISPOSITION_EXECUTABLE if spell.cost >= 0 and ClassicSpellConditionRules.is_combat_persistent_field_spell(spell) else DISPOSITION_PENDING
	if spell.target_type not in [0, 1, 3, 4, 5, 6, 9, 10, 12] or spell.target_type == 0 and spell.size != 0 or spell.cost < 0:
		return DISPOSITION_PENDING
	return DISPOSITION_EXECUTABLE if _is_monster_source_effect(spell) else DISPOSITION_PENDING


static func field_character_disposition(spell: SpellDefinition) -> StringName:
	if spell == null or not spell.in_camp or ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return DISPOSITION_NOT_APPLICABLE
	var special := absi(spell.special)
	if special == 68:
		return DISPOSITION_EXECUTABLE
	if spell.target_type == 7:
		return DISPOSITION_EXECUTABLE if special == 0 or special == 50 or special >= 1 and special < ConditionSet.PARTY_COUNT else DISPOSITION_PENDING
	if ClassicSpellSourceRules.is_field_encounter_utility_spell(spell):
		return DISPOSITION_EXECUTABLE
	if ClassicSpellSourceRules.is_inert_self_duration_effect(spell):
		return DISPOSITION_EXECUTABLE
	if special > 0 and special < 41 or special in [48, 57, 59, 60, 61, 62, 63, 64, 66, 91, 92] or special > 99:
		return DISPOSITION_EXECUTABLE
	if special == 0 and absi(spell.damage_type) >= 1 and absi(spell.damage_type) < 8 and (spell.damage_min != 0 or spell.damage_max != 0 or spell.power_damage_min != 0 or spell.power_damage_max != 0):
		return DISPOSITION_EXECUTABLE
	return DISPOSITION_PENDING


static func character_projectile_disposition(spell: SpellDefinition) -> StringName:
	return DISPOSITION_EXECUTABLE if ClassicSpellSourceRules.is_physical_projectile_profile(spell) else DISPOSITION_NOT_APPLICABLE


static func monster_projectile_disposition(spell: SpellDefinition) -> StringName:
	return DISPOSITION_EXECUTABLE if ClassicSpellSourceRules.is_physical_projectile_profile(spell) else DISPOSITION_NOT_APPLICABLE


static func unsupported_reason(spell: SpellDefinition, context_name: StringName) -> String:
	if spell == null:
		return "The spell definition is unavailable."
	if ClassicSpellIdentityCatalog.application_role(spell) == ClassicSpellIdentityCatalog.ROLE_RESERVED_STANDARD:
		return "This is a reserved Classic spell slot, not an executable spell."
	if String(context_name).begins_with("field-") and not spell.in_camp:
		return "This spell is not available in the Classic field/camp context."
	if context_name != &"field-character" and not spell.in_combat:
		return "This spell is not available in Classic combat."
	if ClassicSpellConditionRules.combat_spell_uses_persistent_field_queue(spell):
		return "This persistent battlefield-field spell is waiting for its collision and expiry lifecycle."
	if spell.can_rotate and spell.target_type in [3, 4] and context_name not in [&"combat-character", &"combat-scroll", &"combat-item"]:
		return "This casting source is waiting for the Classic rotatable-area orientation contract."
	var family := String(ClassicSpellClassificationRules.mechanical_family(spell)).replace("-", " ")
	var context_label := String(context_name).replace("-", " ")
	return "This Classic %s family is not executable for %s yet (special %d, target type %d)." % [family, context_label, absi(spell.special), spell.target_type]


static func _is_character_source_effect(spell: SpellDefinition) -> bool:
	return ClassicSpellSourceRules.is_ordinary_combat_spell(spell) or ClassicSpellSourceRules.is_inert_self_duration_effect(spell) or ClassicSpellConditionRules.is_combat_healing_spell(spell) or ClassicSpellConditionRules.is_combat_condition_cure_spell(spell) or ClassicSpellConditionRules.is_combat_condition_effect_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_death_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_remove_curse_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_destroy_turn_undead_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_phase_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_summon_spell(spell)


static func _is_monster_source_effect(spell: SpellDefinition) -> bool:
	return ClassicSpellSourceRules.is_ordinary_combat_spell(spell) or ClassicSpellSourceRules.is_inert_self_duration_effect(spell) or ClassicSpellConditionRules.is_combat_healing_spell(spell) or ClassicSpellConditionRules.is_combat_condition_cure_spell(spell) or ClassicSpellConditionRules.is_combat_condition_effect_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_death_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_restore_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_spell_point_drain_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_destroy_magic_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_charm_spell(spell) or ClassicSpellSpecialEffectRules.is_combat_polymorph_spell(spell)
