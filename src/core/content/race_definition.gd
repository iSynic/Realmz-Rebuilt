class_name RaceDefinition
extends RefCounted

var id: String
var classic_id: int
var name: String
var description: String = ""
var eligible_caste_ids: Array[String] = []
var max_age: int
var does_not_die: bool
var base_movement: int
var magic_resistance: int
var two_hand_bonus: int
var missile_bonus: int
var base_attacks: int
var maximum_attacks: int
var can_regenerate: bool
var default_icon_set: int
var item_category_mask_low: int
var item_category_mask_high: int
var descriptor_flags: int
var _hit_modifiers: Array[int]
var _ability_bonuses: Array[int]
var _save_bonuses: Array[int]
var _attribute_bonuses: Array[int]
var _attribute_limits: Array[int]
var _condition_levels: Array[int]
var _age_ranges: Array[Vector2i]
var _age_changes: Array[PackedInt32Array]


func _init(definition_id: String, native_id: int, display_name: String, hit_modifiers: Array[int], save_bonuses: Array[int], attribute_bonuses: Array[int], attribute_limits: Array[int], condition_levels: Array[int], age_ranges: Array[Vector2i], age_changes: Array[PackedInt32Array], maximum_age: int = 0, immortal: bool = false, movement: int = 10, magic_resist: int = 0, two_hand: int = 0, missile: int = 0, attacks: int = 1, max_attacks: int = 1, regenerates: bool = false, icon_set: int = 0, item_mask_low: int = 0, item_mask_high: int = 0, descriptors: int = 0, display_description: String = "", allowed_castes: Array[String] = [], ability_bonuses: Array[int] = []) -> void:
	id = definition_id
	classic_id = native_id
	name = display_name
	description = display_description
	eligible_caste_ids = allowed_castes.duplicate()
	_hit_modifiers = hit_modifiers.duplicate()
	_ability_bonuses = ability_bonuses.duplicate()
	_save_bonuses = save_bonuses.duplicate()
	_attribute_bonuses = attribute_bonuses.duplicate()
	_attribute_limits = attribute_limits.duplicate()
	_condition_levels = condition_levels.duplicate()
	_age_ranges = age_ranges.duplicate()
	_age_changes = age_changes.duplicate(true)
	max_age = maximum_age
	does_not_die = immortal
	base_movement = movement
	magic_resistance = magic_resist
	two_hand_bonus = two_hand
	missile_bonus = missile
	base_attacks = attacks
	maximum_attacks = max_attacks
	can_regenerate = regenerates
	default_icon_set = icon_set
	item_category_mask_low = item_mask_low
	item_category_mask_high = item_mask_high
	descriptor_flags = descriptors


func hit_modifier(index: int) -> int:
	return _at(_hit_modifiers, index)


func ability_bonus(index: int) -> int:
	return _at(_ability_bonuses, index)


func save_bonus(index: int) -> int:
	return _at(_save_bonuses, index)


func attribute_bonus(index: int) -> int:
	return _at(_attribute_bonuses, index)


func attribute_minimum(index: int) -> int:
	return _at(_attribute_limits, index * 2)


func attribute_maximum(index: int) -> int:
	return _at(_attribute_limits, index * 2 + 1, 30)


func condition_level(index: int) -> int:
	return _at(_condition_levels, index)


func age_range(index: int) -> Vector2i:
	return Vector2i.ZERO if index < 0 or index >= _age_ranges.size() else _age_ranges[index]


func age_change(index: int) -> PackedInt32Array:
	return PackedInt32Array() if index < 0 or index >= _age_changes.size() else _age_changes[index].duplicate()


static func _at(values: Array[int], index: int, fallback: int = 0) -> int:
	return fallback if index < 0 or index >= values.size() else values[index]
