class_name SessionCoordinatorResult
extends RefCounted

enum State {
	COMPLETED,
	WAITING,
	FAILED,
	CLOSE,
}

var state: State
var events: Array[DomainEvent] = []
var interaction: InteractionRequest
var error_code: StringName
var error_message: String
var close_reason: String


func _init(value: State) -> void:
	state = value


static func completed(value_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var result := SessionCoordinatorResult.new(State.COMPLETED)
	result.events.assign(value_events)
	return result


static func waiting(request: InteractionRequest, value_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var result := SessionCoordinatorResult.new(State.WAITING)
	result.interaction = request
	result.events.assign(value_events)
	return result


static func failed(code: StringName, message: String, value_events: Array[DomainEvent] = []) -> SessionCoordinatorResult:
	var result := SessionCoordinatorResult.new(State.FAILED)
	result.error_code = code
	result.error_message = message
	result.events.assign(value_events)
	return result


static func closed(value_events: Array[DomainEvent], reason: String) -> SessionCoordinatorResult:
	var result := SessionCoordinatorResult.new(State.CLOSE)
	result.events.assign(value_events)
	result.close_reason = reason
	return result
