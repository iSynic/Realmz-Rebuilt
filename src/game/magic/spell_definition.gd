## Defines the immutable spell record loaded from campaign content.

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


func with_scenario_adjustments(extra_save_adjust: int, force_affect: bool) -> SpellDefinition:
	var result := SpellDefinition.new(id, classic_id, name, description)
	result.range_min = range_min
	result.range_max = range_max
	result.queue_icon = queue_icon
	result.to_hit_bonus = to_hit_bonus
	result.save_bonus = save_bonus
	result.fixed_target_count = fixed_target_count
	result.can_rotate = can_rotate
	result.save_adjust = save_adjust + extra_save_adjust
	result.cannot = 3 if force_affect else cannot
	result.resistance_adjust = resistance_adjust
	result.cost = cost
	result.damage_min = damage_min
	result.damage_max = damage_max
	result.power_damage_min = power_damage_min
	result.power_damage_max = power_damage_max
	result.duration_min = duration_min
	result.duration_max = duration_max
	result.power_duration_min = power_duration_min
	result.power_duration_max = power_duration_max
	result.look_start = look_start
	result.look_end = look_end
	result.sound_start = sound_start
	result.sound_end = sound_end
	result.target_type = target_type
	result.size = size
	result.special = special
	result.damage_type = damage_type
	result.spell_class = spell_class
	result.in_combat = in_combat
	result.in_camp = in_camp
	return result
