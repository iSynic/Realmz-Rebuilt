class_name AttackResolution
extends RefCounted

var hit: bool
var killed: bool
var chance: int
var roll: int
var damage: int
var reflected: bool


func _init(did_hit: bool, did_kill: bool, hit_chance: int, attack_roll: int, dealt_damage: int, was_reflected: bool = false) -> void:
	hit = did_hit
	killed = did_kill
	chance = hit_chance
	roll = attack_roll
	damage = dealt_damage
	reflected = was_reflected
