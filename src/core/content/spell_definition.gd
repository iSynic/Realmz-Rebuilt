class_name SpellDefinition
extends RefCounted

var id: String
var classic_id: int
var name: String
var description: String
var range_min: int
var range_max: int
var queue_icon: int
var to_hit_bonus: int
var save_bonus: int
var fixed_target_count: int
var can_rotate: bool
var save_adjust: int
var cannot: int
var resistance_adjust: int
var cost: int
var damage_min: int
var damage_max: int
var power_damage_min: int
var power_damage_max: int
var duration_min: int
var duration_max: int
var power_duration_min: int
var power_duration_max: int
var look_start: int
var look_end: int
var sound_start: int
var sound_end: int
var target_type: int
var size: int
var special: int
var damage_type: int
var spell_class: int
var in_combat: bool
var in_camp: bool


func _init(definition_id: String, native_id: int, display_name: String, spell_description: String = "") -> void:
	id = definition_id
	classic_id = native_id
	name = display_name
	description = spell_description


func classic_tier() -> int:
	if classic_id < 1101:
		return -1
	return int(classic_id % 1000 / 100) - 1


func classic_slot() -> int:
	if classic_id < 1101:
		return -1
	return classic_id % 100
