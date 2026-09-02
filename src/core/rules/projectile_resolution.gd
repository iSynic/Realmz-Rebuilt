class_name ProjectileResolution
extends RefCounted

var fired: bool
var hit_count: int
var miss_count: int
var total_damage: int
var damage_per_hit: int
var duration: int
var target_defeated: bool


func _init(was_fired: bool, hits: int, misses: int, damage: int, per_hit: int, effect_duration: int, defeated: bool) -> void:
	fired = was_fired
	hit_count = hits
	miss_count = misses
	total_damage = damage
	damage_per_hit = per_hit
	duration = effect_duration
	target_defeated = defeated
