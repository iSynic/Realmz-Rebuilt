class_name MonsterAttackDefinition
extends RefCounted

var damage_min: int
var damage_max: int
var sound_or_type: int
var special: int


func _init(minimum_damage: int = 0, maximum_damage: int = 0, attack_sound_or_type: int = 0, special_attack: int = 0) -> void:
	damage_min = minimum_damage
	damage_max = maximum_damage
	sound_or_type = attack_sound_or_type
	special = special_attack
