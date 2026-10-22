## Defines the typed session workflow result contract used by playthrough transactions.

class_name SessionWorkflowResult
extends RefCounted

var ok: bool
var events: Array[DomainEvent]
var error_code: StringName
var error_message: String
var is_rejection: bool = false


func _init(succeeded: bool, committed_events: Array[DomainEvent] = [], code: StringName = &"", message: String = "") -> void:
	ok = succeeded
	events = committed_events
	error_code = code
	error_message = message


static func completed(committed_events: Array[DomainEvent] = []) -> SessionWorkflowResult:
	return SessionWorkflowResult.new(true, committed_events)


static func failed(code: StringName, message: String) -> SessionWorkflowResult:
	return SessionWorkflowResult.new(false, [], code, message)


## Correctable player input: nothing was mutated and the prompt stays open.
static func rejected(code: StringName, message: String) -> SessionWorkflowResult:
	var result := failed(code, message)
	result.is_rejection = true
	return result
