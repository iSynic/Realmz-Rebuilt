class_name SpellResolution
extends RefCounted

var cast: bool
var resisted: bool
var saved: bool
var cost: int
var damage: int
var duration: int
var target_defeated: bool
var aging: CharacterAgingResult
var cleared_condition: int = -1
var cleared_condition_count: int = 0
var applied_condition: int = -1
var spell_point_delta: int = 0
var allegiance_changed: bool = false
var target_traitor_before: bool = false
var target_traitor_after: bool = false
var detected_magic_item_count: int = 0
var unequipped_item_ids: Array[String] = []
var transformed_definition_before: String = ""
var transformed_definition_after: String = ""
var special_result: StringName = &""
var special_roll: int = 0
var special_threshold: int = 0


func _init(was_cast: bool, was_resisted: bool, did_save: bool, spell_cost: int, dealt_damage: int, effect_duration: int, defeated: bool = false) -> void:
	cast = was_cast
	resisted = was_resisted
	saved = did_save
	cost = spell_cost
	damage = dealt_damage
	duration = effect_duration
	target_defeated = defeated
