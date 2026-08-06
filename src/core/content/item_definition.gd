class_name ItemDefinition
extends RefCounted

var id: String
var classic_id: int
var name: String
var unidentified_name: String
var description: String
var icon_id: int
var item_type: int
var strength_bonus: int
var blunt: int
var hands: int
var luck_bonus: int
var movement_bonus: int
var armor_bonus: int
var magic_resistance_bonus: int
var damage_bonus: int
var spell_point_bonus: int
var sound_id: int
var weight: int
var cost: int
var initial_charges: int
var cursed_item_id: String
var magical: bool
var item_category_mask_low: int
var item_category_mask_high: int
var race_restrictions: int
var caste_restrictions: int
var specific_race_id: String
var specific_caste_id: String
var race_class_only: int
var caste_class_only: int
var vs_small: int
var vs_large: int
var heat: int
var cold: int
var electric: int
var vs_undead: int
var vs_demon_devil: int
var vs_evil: int
var special_1: int
var special_2: int
var special_3: int
var special_4: int
var special_5: int
var weight_per_charge: int
var drop_on_empty: bool


func _init(definition_id: String, native_id: int, display_name: String, unknown_name: String = "Unknown item", item_description: String = "") -> void:
	id = definition_id
	classic_id = native_id
	name = display_name
	unidentified_name = unknown_name
	description = item_description


func instance_weight(charge_count: int) -> int:
	return maxi(0, weight + maxi(0, charge_count) * weight_per_charge)
