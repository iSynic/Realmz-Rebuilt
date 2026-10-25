## Applies explicit native guard and destination work facts from an accepted operation.
class_name ScenarioNativeOperationRules
extends RefCounted


static func after_operation(entry: ScenarioClassicInvocationRecord, operation: ScenarioRuntimeOperationResult, context: ScenarioExecutionContext, runtime: RealmzRuntimeApi) -> ScenarioRuntimeOperationResult:
	if operation.state != ScenarioRuntimeOperationResult.State.COMPLETED: return operation
	if operation.invocation_returned_early: entry.returned_early = true
	if operation.suppress_header_recheck: entry.no_second_door = true
	if operation.secondary_door_completed: entry.secondary_door = true
	if operation.suppress_header_completion: entry.completion.header_suppressed = true
	if not operation.recheck_destination: return operation
	var recheck := runtime.native_action_points.recheck(context)
	recheck.events = operation.events + recheck.events
	return recheck
