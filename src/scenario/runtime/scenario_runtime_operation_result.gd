class_name ScenarioRuntimeOperationResult
extends RefCounted

enum State {
	COMPLETED,
	WAITING,
	FAILED,
}

var state: State = State.COMPLETED
var value: Variant
var events: Array[DomainEvent] = []
var interaction: InteractionRequest
var continuation: Dictionary = {}
var directive: Dictionary = {}
var error_code: StringName = &""
var error_message: String = ""


static func completed(result_value: Variant = null, committed_events: Array[DomainEvent] = [], vm_directive: Dictionary = {}) -> ScenarioRuntimeOperationResult:
	var result := ScenarioRuntimeOperationResult.new()
	result.value = result_value
	result.events.assign(committed_events)
	result.directive = vm_directive.duplicate(true)
	return result


static func waiting(request: InteractionRequest, resume_data: Dictionary, committed_events: Array[DomainEvent] = [], vm_directive: Dictionary = {}) -> ScenarioRuntimeOperationResult:
	var result := completed(null, committed_events, vm_directive)
	result.state = State.WAITING
	result.interaction = request
	result.continuation = resume_data.duplicate(true)
	return result


static func failed(code: StringName, message: String) -> ScenarioRuntimeOperationResult:
	var result := ScenarioRuntimeOperationResult.new()
	result.state = State.FAILED
	result.error_code = code
	result.error_message = message
	return result
