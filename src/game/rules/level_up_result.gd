class_name LevelUpResult
extends RefCounted

var stamina_gained: int
var spell_points_gained: int
var to_hit_gained: int
var magic_resistance_gained: int


func _init(stamina: int = 0, spell_points: int = 0, to_hit: int = 0, magic_resistance: int = 0) -> void:
	stamina_gained = stamina
	spell_points_gained = spell_points
	to_hit_gained = to_hit
	magic_resistance_gained = magic_resistance
