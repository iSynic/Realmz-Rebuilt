## Implements deterministic combat spell cast probe rules without presentation dependencies.

class_name CombatSpellCastProbe
extends RefCounted

var allowed: bool = false
var reason: StringName = &"spell_cast_unavailable"
var reason_text: String = "Spell casting is unavailable."
var content_fault: bool = false


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


static func fault(code: StringName, message: String) -> CombatSpellCastProbe:
	var result := blocked(code, message)
	result.content_fault = true
	return result


func denial_result() -> CombatFlowResult:
	return CombatFlowResult.failed(reason, reason_text) if content_fault else CombatFlowResult.rejected(reason, reason_text)
