## Implements deterministic level up result rules without presentation dependencies.

class_name LevelUpResult
extends RefCounted

enum State { COMPLETED, UNSAFE_CANDIDATE }
var state: State = State.COMPLETED

var stamina_gained: int
var spell_points_gained: int
var to_hit_gained: int
var magic_resistance_gained: int


func _init(stamina: int = 0, spell_points: int = 0, to_hit: int = 0, magic_resistance: int = 0) -> void:
	stamina_gained = stamina
	spell_points_gained = spell_points
	to_hit_gained = to_hit
	magic_resistance_gained = magic_resistance


static func unsafe_candidate() -> LevelUpResult:
	var result := LevelUpResult.new()
	result.state = State.UNSAFE_CANDIDATE
	return result
