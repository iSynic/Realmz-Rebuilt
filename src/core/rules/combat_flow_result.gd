class_name CombatFlowResult
extends RefCounted

var ok: bool = true
var completed: bool = false
var events: Array[DomainEvent] = []
var error_code: StringName = &""
var error_message: String = ""


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
