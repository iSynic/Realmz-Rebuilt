## Creates typed commands for learned spells, scrolls, placements, and Fast Spells.

class_name MagicIntents
extends RefCounted

const NO_COORDINATE := Vector2i(-100_000, -100_000)


static func cast(spell_id: String, caster_id: String = "", target_combatant_id: String = "", power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"cast", spell_id, caster_id, target_combatant_id, [], power))


static func identify_carried_items(spell_id: String, caster_id: String, target_character_id: String) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"identify-inventory", spell_id, caster_id, target_character_id))


static func make_scroll(spell_id: String, caster_id: String, power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"make-scroll", spell_id, caster_id, "", [], power))


static func use_scroll(caster_id: String, slot_index: int, target_character_ids: Array[String] = []) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"use-scroll", "", caster_id, "", target_character_ids, 1, NO_COORDINATE, 0, slot_index))


static func use_scroll_on_target(caster_id: String, slot_index: int, target_combatant_id: String = "", target_combatant_ids: Array[String] = [], coordinate: Vector2i = NO_COORDINATE, area_rotation: int = 0) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"use-scroll", "", caster_id, target_combatant_id, target_combatant_ids, 1, coordinate, area_rotation, slot_index))


static func use_scroll_at_coordinates(caster_id: String, slot_index: int, coordinates: Array[Vector2i]) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"use-scroll", "", caster_id, "", [], 1, NO_COORDINATE, 0, slot_index, coordinates))


static func cast_at(spell_id: String, caster_id: String, coordinate: Vector2i, power: int = 1, area_rotation: int = 0) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"cast", spell_id, caster_id, "", [], power, coordinate, area_rotation))


static func cast_at_targets(spell_id: String, caster_id: String, target_combatant_ids: Array[String], power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"cast", spell_id, caster_id, "", target_combatant_ids, power))


static func cast_at_coordinates(spell_id: String, caster_id: String, coordinates: Array[Vector2i], power: int = 1) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.CAST_SPELL, SpellIntentPayload.new(&"cast", spell_id, caster_id, "", [], power, NO_COORDINATE, 0, -1, coordinates))


static func set_fast_spell(caster_id: String, slot_index: int, spell_id: String = "", power: int = 0) -> PlayerIntent:
	return PlayerIntent.new(PlayerIntent.Kind.SET_FAST_SPELL, SpellIntentPayload.new(&"bind-fast", spell_id, caster_id, "", [], power, NO_COORDINATE, 0, slot_index))
