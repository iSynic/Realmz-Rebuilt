class_name SessionStep
extends RefCounted

enum State {
	COMPLETED,
	WAITING_FOR_INTERACTION,
	FAILED,
}

var events: Array[DomainEvent] = []
var interaction: InteractionRequest
var view_revision: int = 0
var state: State = State.COMPLETED
var error_code: StringName = &""
var error_message: String = ""


static func completed(revision: int, committed_events: Array[DomainEvent] = []) -> SessionStep:
	var step := SessionStep.new()
	step.view_revision = revision
	step.events.assign(committed_events)
	return step


static func waiting(revision: int, request: InteractionRequest, committed_events: Array[DomainEvent] = []) -> SessionStep:
	var step := completed(revision, committed_events)
	step.state = State.WAITING_FOR_INTERACTION
	step.interaction = request
	return step


static func failed(revision: int, code: StringName, message: String, committed_events: Array[DomainEvent] = []) -> SessionStep:
	var step := SessionStep.new()
	step.view_revision = revision
	step.state = State.FAILED
	step.error_code = code
	step.error_message = message
	step.events.assign(committed_events)
	return step
