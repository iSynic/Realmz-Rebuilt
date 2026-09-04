## Defines the immutable caste record loaded from campaign content.

class_name CasteDefinition
extends RefCounted

class AttributeDefinition:
	extends RefCounted

	var _save_bonuses: Array[int]
	var _attribute_bonuses: Array[int]
	var _attribute_limits: Array[int]
	var _condition_levels: Array[int]
	var _strength_values: Vector2i

	func _init(save_bonuses: Array[int], attribute_bonuses: Array[int], attribute_limits: Array[int], condition_levels: Array[int], strength_values: Vector2i = Vector2i(0, 8)) -> void:
		_save_bonuses = save_bonuses.duplicate()
		_attribute_bonuses = attribute_bonuses.duplicate()
		_attribute_limits = attribute_limits.duplicate()
		_condition_levels = condition_levels.duplicate()
		_strength_values = strength_values

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

	func maximum_damage_bonus() -> int:
		return _strength_values.y

	static func _at(values: Array[int], index: int, fallback: int = 0) -> int:
		return fallback if index < 0 or index >= values.size() else values[index]


class ProgressionDefinition:
	extends RefCounted

	var _stamina_dice: Vector2i
	var _to_hit: Vector2i
	var _dodge: Vector2i
	var _missile: Vector2i
	var _hand_to_hand: Vector2i
	var _spellcasters: Array[Vector3i]
	var _attack_levels: Array[int]
	var _initial_ability_values: Array[int]
	var _level_ability_dice: Array[int]
	var _victory_thresholds: Array[int]

	func _init(stamina_dice: Vector2i, to_hit_values: Vector2i, dodge_values: Vector2i, missile_values: Vector2i, hand_to_hand_values: Vector2i, authored_spellcaster_rows: Array[Vector3i] = [], authored_attack_levels: Array[int] = [], initial_ability_values: Array[int] = [], level_ability_dice: Array[int] = [], victory_thresholds: Array[int] = []) -> void:
		_stamina_dice = stamina_dice
		_to_hit = to_hit_values
		_dodge = dodge_values
		_missile = missile_values
		_hand_to_hand = hand_to_hand_values
		_spellcasters = authored_spellcaster_rows.duplicate()
		_attack_levels = authored_attack_levels.duplicate()
		_initial_ability_values = initial_ability_values.duplicate()
		_level_ability_dice = level_ability_dice.duplicate()
		_victory_thresholds = victory_thresholds.duplicate()

	func initial_stamina_die() -> int:
		return _stamina_dice.x

	func level_stamina_die() -> int:
		return _stamina_dice.y

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

	func initial_ability_value(index: int) -> int:
		return _at(_initial_ability_values, index)

	func level_ability_die(index: int) -> int:
		return _at(_level_ability_dice, index)

	func victory_threshold(index: int) -> int:
		return _at(_victory_thresholds, index)

	static func _at(values: Array[int], index: int, fallback: int = 0) -> int:
		return fallback if index < 0 or index >= values.size() else values[index]


var id: String
var classic_id: int
var name: String
var description: String = ""
var eligible_race_ids: Array[String] = []
var caste_class: int = 0
var minimum_age_group: int = 1
var movement_bonus: int = 0
var magic_resistance_multiplier: int = 1
var two_hand_bonus: int = 0
var maximum_stamina_bonus: int = 0
var bonus_attacks: int = 0
var maximum_attacks: int = 1
var start_money: int = 0
var can_use_missile: bool = true
var gets_missile_bonus: bool = false
var default_icon: int = 0
var item_category_mask_low: int = 0
var item_category_mask_high: int = 0
var attributes: AttributeDefinition
var progression: ProgressionDefinition
var _start_items: Array[String]


func _init(definition_id: String, native_id: int, display_name: String, attribute_definition: AttributeDefinition, progression_definition: ProgressionDefinition, starting_items: Array[String] = []) -> void:
	id = definition_id
	classic_id = native_id
	name = display_name
	attributes = attribute_definition
	progression = progression_definition
	_start_items = starting_items.duplicate()


func start_items() -> Array[String]:
	return _start_items.duplicate()
