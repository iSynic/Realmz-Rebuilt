## Implements deterministic combat flow result rules without presentation dependencies.

class_name CombatFlowResult
extends RefCounted

enum Fumble { NONE, COMMITTED, UNARMED, CURSED_WEAPON }

var fumble: Fumble = Fumble.NONE
var ok: bool = true
var completed: bool = false
var events: Array[DomainEvent] = []
var error_code: StringName = &""
var error_message: String = ""
var is_rejection: bool = false
var death_macro: CombatDeathMacroRequest
var age_updates: Array[AgeUpdateRequestBody] = []


func with_fumble(value: Fumble) -> CombatFlowResult:
	fumble = value
	return self


static func from_combat(combat: CombatState, committed_events: Array[DomainEvent], battle_completed: bool = false) -> CombatFlowResult:
	var result := succeeded(committed_events, battle_completed)
	if combat != null and combat.pending_operations.death_macro != null:
		result.death_macro = combat.pending_operations.death_macro.copy()
	if combat != null:
		for update: AgeUpdateRequestBody in combat.pending_operations.age_updates:
			result.age_updates.append(InteractionRequest.age_update_body("combat.age-copy",update).body as AgeUpdateRequestBody)
	return result


static func succeeded(committed_events: Array[DomainEvent], battle_completed: bool = false) -> CombatFlowResult:
	var result := CombatFlowResult.new()
	result.events.assign(committed_events)
	result.completed = battle_completed
	return result


static func failed(code: StringName, message: String) -> CombatFlowResult:
	var result := CombatFlowResult.new()
	result.ok = false
	result.error_code = code
	result.error_message = message
	return result


static func rejected(code: StringName, message: String) -> CombatFlowResult:
	var result := failed(code, message)
	result.is_rejection = true
	return result
