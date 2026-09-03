class_name ItemDefinition
extends RefCounted

const UNIDENTIFIED_ICON_RANGES := [
	Vector3i(1, 10, 2),
	Vector3i(12, 19, 12),
	Vector3i(20, 34, 20),
	Vector3i(35, 39, 35),
	Vector3i(50, 56, 50),
	Vector3i(82, 85, 82),
	Vector3i(89, 95, 89),
	Vector3i(517, 527, 527),
	Vector3i(545, 548, 546),
	Vector3i(6100, 6109, 6100),
	Vector3i(6110, 6121, 6110),
	Vector3i(6122, 6127, 6122),
	Vector3i(6137, 6139, 6137),
	Vector3i(6185, 6187, 6183),
	Vector3i(6190, 6195, 6190),
	Vector3i(6196, 6200, 6197),
	Vector3i(6202, 6206, 6202),
	Vector3i(6208, 6209, 12009),
	Vector3i(6162, 6163, 6162),
	Vector3i(6176, 6177, 6177),
]

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


func visible_icon_id(identified: bool) -> int:
	if identified or icon_id <= 0:
		return icon_id
	for icon_range: Vector3i in UNIDENTIFIED_ICON_RANGES:
		if icon_id >= icon_range.x and icon_id <= icon_range.y:
			return icon_range.z
	return icon_id
