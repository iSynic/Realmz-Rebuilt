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


func _init(was_cast: bool, was_resisted: bool, did_save: bool, spell_cost: int, dealt_damage: int, effect_duration: int, defeated: bool = false) -> void:
	cast = was_cast
	resisted = was_resisted
	saved = did_save
	cost = spell_cost
	damage = dealt_damage
	duration = effect_duration
	target_defeated = defeated
