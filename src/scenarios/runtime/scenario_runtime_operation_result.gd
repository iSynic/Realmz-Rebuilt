class_name ScenarioRuntimeOperationResult
extends RefCounted

enum State {
	COMPLETED,
	WAITING,
	SUSPENDED,
	FAILED,
}

var state: State = State.COMPLETED
var value: Variant
var events: Array[DomainEvent] = []
var interaction: InteractionRequest
var continuation: ScenarioRuntimeContinuation
var handoff: ScenarioRuntimeHandoff
var directive: ScenarioVmDirective
var error_code: StringName = &""
var error_message: String = ""


static func completed(result_value: Variant = null, committed_events: Array[DomainEvent] = [], vm_directive: ScenarioVmDirective = null) -> ScenarioRuntimeOperationResult:
	var result := ScenarioRuntimeOperationResult.new()
	result.value = result_value
	result.events.assign(committed_events)
	result.directive = vm_directive.copy() if vm_directive != null else null
	return result


static func waiting(request: InteractionRequest, resume_data: ScenarioRuntimeContinuation, committed_events: Array[DomainEvent] = [], vm_directive: ScenarioVmDirective = null) -> ScenarioRuntimeOperationResult:
	var result := completed(null, committed_events, vm_directive)
	result.state = State.WAITING
	result.interaction = request
	result.continuation = resume_data.copy() if resume_data != null else null
	return result


static func suspended(host_handoff: ScenarioRuntimeHandoff, committed_events: Array[DomainEvent] = []) -> ScenarioRuntimeOperationResult:
	var result := completed(null, committed_events)
	result.state = State.SUSPENDED
	result.handoff = host_handoff.copy() if host_handoff != null else null
	return result


static func failed(code: StringName, message: String) -> ScenarioRuntimeOperationResult:
	var result := ScenarioRuntimeOperationResult.new()
	result.state = State.FAILED
	result.error_code = code
	result.error_message = message
	return result
