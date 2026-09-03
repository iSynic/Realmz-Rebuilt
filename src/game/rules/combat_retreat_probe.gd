class_name CombatRetreatProbe
extends RefCounted

var allowed: bool = false
var forced: bool = false
var reason: StringName = &"unavailable"
var reason_text: String = "Retreat is unavailable."
var nearest_enemy_range: int = 127


static func permitted(enemy_range: int = 127, is_forced: bool = false) -> CombatRetreatProbe:
	var result := CombatRetreatProbe.new()
	result.allowed = true
	result.forced = is_forced
	result.reason = &""
	result.reason_text = ""
	result.nearest_enemy_range = enemy_range
	return result


static func blocked(block_reason: StringName, message: String, enemy_range: int = 127) -> CombatRetreatProbe:
	var result := CombatRetreatProbe.new()
	result.reason = block_reason
	result.reason_text = message
	result.nearest_enemy_range = enemy_range
	return result
