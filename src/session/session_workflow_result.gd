class_name SessionWorkflowResult
extends RefCounted

var ok: bool
var events: Array[DomainEvent]
var error_code: StringName
var error_message: String


func _init(succeeded: bool, committed_events: Array[DomainEvent] = [], code: StringName = &"", message: String = "") -> void:
	ok = succeeded
	events = committed_events
	error_code = code
	error_message = message


static func completed(committed_events: Array[DomainEvent] = []) -> SessionWorkflowResult:
	return SessionWorkflowResult.new(true, committed_events)


static func failed(code: StringName, message: String) -> SessionWorkflowResult:
	return SessionWorkflowResult.new(false, [], code, message)
