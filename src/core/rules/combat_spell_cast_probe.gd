class_name CombatSpellCastProbe
extends RefCounted

var allowed: bool = false
var reason: StringName = &"spell_cast_unavailable"
var reason_text: String = "Spell casting is unavailable."


static func permitted() -> CombatSpellCastProbe:
	var result := CombatSpellCastProbe.new()
	result.allowed = true
	result.reason = &""
	result.reason_text = ""
	return result


static func blocked(code: StringName, message: String) -> CombatSpellCastProbe:
	var result := CombatSpellCastProbe.new()
	result.reason = code
	result.reason_text = message
	return result
