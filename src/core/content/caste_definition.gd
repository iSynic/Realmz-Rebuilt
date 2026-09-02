class_name CasteDefinition
extends RefCounted

var id: String
var classic_id: int
var name: String
var description: String = ""
var eligible_race_ids: Array[String] = []
var caste_class: int
var minimum_age_group: int
var movement_bonus: int
var magic_resistance_multiplier: int
var two_hand_bonus: int
var maximum_stamina_bonus: int
var bonus_attacks: int
var maximum_attacks: int
var start_money: int
var can_use_missile: bool
var gets_missile_bonus: bool
var default_icon: int
var item_category_mask_low: int
var item_category_mask_high: int
var _save_bonuses: Array[int]
var _attribute_bonuses: Array[int]
var _attribute_limits: Array[int]
var _condition_levels: Array[int]
var _stamina_dice: Vector2i
var _strength_values: Vector2i
var _to_hit: Vector2i
var _dodge: Vector2i
var _missile: Vector2i
var _hand_to_hand: Vector2i
var _spellcasters: Array[Vector3i]
var _attack_levels: Array[int]
var _start_items: Array[String]
var _initial_ability_values: Array[int]
var _level_ability_dice: Array[int]
var _victory_thresholds: Array[int]


func _init(definition_id: String, native_id: int, display_name: String, save_bonuses: Array[int], attribute_bonuses: Array[int], attribute_limits: Array[int], condition_levels: Array[int], stamina_dice: Vector2i, to_hit_values: Vector2i, dodge_values: Vector2i, missile_values: Vector2i, hand_to_hand_values: Vector2i, authored_spellcaster_rows: Array[Vector3i] = [], authored_attack_levels: Array[int] = [], starting_items: Array[String] = [], class_id: int = 0, minimum_age: int = 1, move_bonus: int = 0, magic_multiplier: int = 1, two_hand: int = 0, max_stamina_bonus: int = 0, extra_attacks: int = 0, max_attack_count: int = 1, money: int = 0, uses_missile: bool = true, missile_bonus_enabled: bool = false, icon: int = 0, item_mask_low: int = 0, item_mask_high: int = 0, strength_values: Vector2i = Vector2i(0, 8), display_description: String = "", allowed_races: Array[String] = [], initial_ability_values: Array[int] = [], level_ability_dice: Array[int] = [], victory_thresholds: Array[int] = []) -> void:
	id = definition_id
	classic_id = native_id
	name = display_name
	description = display_description
	eligible_race_ids = allowed_races.duplicate()
	_save_bonuses = save_bonuses.duplicate()
	_attribute_bonuses = attribute_bonuses.duplicate()
	_attribute_limits = attribute_limits.duplicate()
	_condition_levels = condition_levels.duplicate()
	_stamina_dice = stamina_dice
	_strength_values = strength_values
	_to_hit = to_hit_values
	_dodge = dodge_values
	_missile = missile_values
	_hand_to_hand = hand_to_hand_values
	_spellcasters = authored_spellcaster_rows.duplicate()
	_attack_levels = authored_attack_levels.duplicate()
	_start_items = starting_items.duplicate()
	_initial_ability_values = initial_ability_values.duplicate()
	_level_ability_dice = level_ability_dice.duplicate()
	_victory_thresholds = victory_thresholds.duplicate()
	caste_class = class_id
	minimum_age_group = minimum_age
	movement_bonus = move_bonus
	magic_resistance_multiplier = maxi(1, magic_multiplier)
	two_hand_bonus = two_hand
	maximum_stamina_bonus = max_stamina_bonus
	bonus_attacks = extra_attacks
	maximum_attacks = max_attack_count
	start_money = money
	can_use_missile = uses_missile
	gets_missile_bonus = missile_bonus_enabled
	default_icon = icon
	item_category_mask_low = item_mask_low
	item_category_mask_high = item_mask_high


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


func initial_stamina_die() -> int:
	return _stamina_dice.x


func level_stamina_die() -> int:
	return _stamina_dice.y


func maximum_damage_bonus() -> int:
	return _strength_values.y


func initial_to_hit() -> int:
	return _to_hit.x


func level_to_hit() -> int:
	return _to_hit.y


func initial_dodge() -> int:
	return _dodge.x


func level_dodge() -> int:
	return _dodge.y


func initial_missile() -> int:
	return _missile.x


func level_missile() -> int:
	return _missile.y


func initial_hand_to_hand() -> int:
	return _hand_to_hand.x


func level_hand_to_hand() -> int:
	return _hand_to_hand.y


func spellcaster_rows() -> Array[Vector3i]:
	return _spellcasters.duplicate()


func attack_levels() -> Array[int]:
	return _attack_levels.duplicate()


func start_items() -> Array[String]:
	return _start_items.duplicate()


func initial_ability_value(index: int) -> int:
	return _at(_initial_ability_values, index)


func level_ability_die(index: int) -> int:
	return _at(_level_ability_dice, index)


func victory_threshold(index: int) -> int:
	return _at(_victory_thresholds, index)


static func _at(values: Array[int], index: int, fallback: int = 0) -> int:
	return fallback if index < 0 or index >= values.size() else values[index]
