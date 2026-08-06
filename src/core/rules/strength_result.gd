class_name StrengthResult
extends RefCounted

var to_hit_bonus: int
var damage_bonus: int


func _init(hit_bonus: int = 0, damage: int = 0) -> void:
	to_hit_bonus = hit_bonus
	damage_bonus = damage
