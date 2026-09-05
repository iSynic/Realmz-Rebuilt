## Reports a committed or waiting field-magic workflow transition to the session owner.

class_name MagicTransitionResult
extends RefCounted

var ok: bool
var completed: bool
var process_age_updates: bool
var events: Array[DomainEvent]
var continuation: SessionContinuation
var interaction: InteractionRequest
var error_code: StringName
var error_message: String


static func failed(code: StringName, message: String) -> MagicTransitionResult:
	var result := MagicTransitionResult.new()
	result.error_code = code
	result.error_message = message
	return result


static func committed(workflow_result: SessionWorkflowResult, should_process_age_updates: bool = false) -> MagicTransitionResult:
	if workflow_result == null:
		return failed(&"invalid_workflow_result", "The magic workflow returned no result.")
	if not workflow_result.ok:
		return failed(workflow_result.error_code, workflow_result.error_message)
	var result := MagicTransitionResult.new()
	result.ok = true
	result.completed = true
	result.process_age_updates = should_process_age_updates
	result.events = workflow_result.events
	return result


static func waiting(pending_continuation: SessionContinuation, pending_interaction: InteractionRequest, pending_events: Array[DomainEvent]) -> MagicTransitionResult:
	var result := MagicTransitionResult.new()
	result.ok = true
	result.continuation = pending_continuation
	result.interaction = pending_interaction
	result.events = pending_events
	return result
