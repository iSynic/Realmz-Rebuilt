## Reports a committed or waiting field-magic workflow transition to the session owner.

class_name MagicTransitionResult
extends RefCounted

var ok: bool
var completed: bool
var age_updates: Array[AgeUpdateRequestBody] = []
var events: Array[DomainEvent]
var continuation: SessionContinuation
var interaction: InteractionRequest
var error_code: StringName
var error_message: String
var is_rejection: bool = false


static func failed(code: StringName, message: String) -> MagicTransitionResult:
	var result := MagicTransitionResult.new()
	result.error_code = code
	result.error_message = message
	return result


## Correctable player input: nothing was mutated and the prompt stays open.
static func rejected(code: StringName, message: String) -> MagicTransitionResult:
	var result := failed(code, message)
	result.is_rejection = true
	return result


static func committed(workflow_result: SessionWorkflowResult) -> MagicTransitionResult:
	if workflow_result == null:
		return failed(&"invalid_workflow_result", "The magic workflow returned no result.")
	if not workflow_result.ok:
		return rejected(workflow_result.error_code, workflow_result.error_message) if workflow_result.is_rejection else failed(workflow_result.error_code, workflow_result.error_message)
	var result := MagicTransitionResult.new()
	result.ok = true
	result.completed = true
	result.age_updates.assign(workflow_result.age_updates)
	result.events = workflow_result.events
	return result


static func waiting(pending_continuation: SessionContinuation, pending_interaction: InteractionRequest, pending_events: Array[DomainEvent]) -> MagicTransitionResult:
	var result := MagicTransitionResult.new()
	result.ok = true
	result.continuation = pending_continuation
	result.interaction = pending_interaction
	result.events = pending_events
	return result
