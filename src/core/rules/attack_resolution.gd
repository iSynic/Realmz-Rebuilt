class_name AttackResolution
extends RefCounted

var hit: bool
var killed: bool
var chance: int
var roll: int
var damage: int
var reflected: bool
var damage_deferred: bool = false
var special_code: int = 0
var special_potency: int = 0
var special_handled: bool = false
var special_save_index: int = -1
var special_save_chance: int = 0
var special_save_roll: int = 0
var special_saved: bool = false
var special_applied: bool = false
var special_condition_index: int = -1
var special_condition_before: int = 0
var special_condition_after: int = 0
var special_blocked: bool = false
var special_block_reason: StringName = &""
var special_announced: bool = false
var special_sound_id: int = 0
var special_age_days: int = 0
var special_resource: StringName = &""
var special_amount: int = 0
var special_target_before: int = 0
var special_target_after: int = 0
var special_actor_before: int = 0
var special_actor_after: int = 0
var aging: CharacterAgingResult


func _init(did_hit: bool, did_kill: bool, hit_chance: int, attack_roll: int, dealt_damage: int, was_reflected: bool = false) -> void:
	hit = did_hit
	killed = did_kill
	chance = hit_chance
	roll = attack_roll
	damage = dealt_damage
	reflected = was_reflected
