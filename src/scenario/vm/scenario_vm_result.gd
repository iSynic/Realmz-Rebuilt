class_name ScenarioVmResult
extends RefCounted

enum State {
	COMPLETED,
	WAITING,
	SUSPENDED,
	FAILED,
}

var state: State = State.COMPLETED
var events: Array[DomainEvent] = []
var interaction: InteractionRequest
var handoff: ScenarioVmHandoff
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


static func suspended(host_handoff: ScenarioVmHandoff, committed_events: Array[DomainEvent] = []) -> ScenarioVmResult:
	var vm_result := completed(committed_events)
	vm_result.state = State.SUSPENDED
	vm_result.handoff = host_handoff.copy() if host_handoff != null else null
	return vm_result


static func failed(code: StringName, message: String, committed_events: Array[DomainEvent] = []) -> ScenarioVmResult:
	var vm_result := completed(committed_events)
	vm_result.state = State.FAILED
	vm_result.error_code = code
	vm_result.error_message = message
	return vm_result
