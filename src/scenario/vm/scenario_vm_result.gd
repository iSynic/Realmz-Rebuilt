class_name ScenarioVmResult
extends RefCounted

enum State {
	COMPLETED,
	WAITING,
	FAILED,
}

var state: State = State.COMPLETED
var events: Array[DomainEvent] = []
var interaction: InteractionRequest
var error_code: StringName = &""
var error_message: String = ""
var outcome: Variant


static func completed(committed_events: Array[DomainEvent] = [], result: Variant = null) -> ScenarioVmResult:
	var vm_result := ScenarioVmResult.new()
	vm_result.events.assign(committed_events)
	vm_result.outcome = result
	return vm_result


static func waiting(request: InteractionRequest, committed_events: Array[DomainEvent] = []) -> ScenarioVmResult:
	var vm_result := completed(committed_events)
	vm_result.state = State.WAITING
	vm_result.interaction = request
	return vm_result


static func failed(code: StringName, message: String, committed_events: Array[DomainEvent] = []) -> ScenarioVmResult:
	var vm_result := completed(committed_events)
	vm_result.state = State.FAILED
	vm_result.error_code = code
	vm_result.error_message = message
	return vm_result
