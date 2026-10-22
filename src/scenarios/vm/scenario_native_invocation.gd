## Retains one newland invocation's local guards, distinct from shared native data.
class_name ScenarioNativeInvocation
extends RefCounted

var context: ScenarioExecutionContext
var secondary_door: bool = false
var no_second_door: bool = false
var returned_early: bool = false
var _shared: ClassicExecutionState


func bind(runtime: RealmzRuntimeApi) -> void:
	_shared = runtime.classic_execution()


func capture_return_header(frame: ScenarioFrame) -> void:
	if _shared != null and not _shared.map_id.is_empty(): frame.native_return_destination = TriggerDestinationDefinition.new(_shared.map_id, _shared.coordinate)


func restore_return_header(frame: ScenarioFrame) -> void:
	var destination := frame.native_return_destination
	if destination == null or _shared == null: return
	# Castle pulls the saved infodoor header, but doornum remains global.
	_shared.map_id = destination.map_id
	_shared.coordinate = destination.coordinate
	_shared.header_replaced = true
	frame.native_return_destination = null


func start(caller: ScenarioExecutionContext) -> void:
	context = caller.copy() if caller != null and caller.is_native_mode_one() else null
	secondary_door = false
	no_second_door = false
	returned_early = false


func header_pending() -> bool:
	return context != null and not secondary_door and not returned_early


func complete(runtime: RealmzRuntimeApi) -> ScenarioRuntimeOperationResult:
	secondary_door = true
	var result := runtime.native_action_points.complete_invocation(context, no_second_door)
	if result.directive != null and result.value is bool and not result.value: returned_early = true
	return result


func after_operation(action: ClassicActionDefinition, operation: ScenarioRuntimeOperationResult, caller: ScenarioExecutionContext, runtime: RealmzRuntimeApi) -> ScenarioRuntimeOperationResult:
	if operation.state != ScenarioRuntimeOperationResult.State.COMPLETED: return operation
	if action.opcode == 37 and operation.directive != null: returned_early = true
	if action.opcode == 45: no_second_door = true
	if action.opcode != 20 or operation.value == null: return operation
	secondary_door = true
	for event: DomainEvent in operation.events:
		if event.kind != &"destination_trigger_recheck_requested": continue
		var recheck := runtime.native_action_points.recheck(caller)
		recheck.events = operation.events + recheck.events
		if recheck.state == ScenarioRuntimeOperationResult.State.FAILED: return recheck
		returned_early = not recheck.value
		if recheck.directive.kind == ScenarioVmDirective.CLOCK_TIMER_RETURN: recheck.directive.kind = ScenarioVmDirective.RECHECK_PROGRAM
		return recheck
	return operation


func write_snapshot(snapshot: ScenarioVmSnapshot) -> void:
	snapshot.native_context = context.copy() if context != null else null
	snapshot.secondary_door = secondary_door
	snapshot.no_second_door = no_second_door
	snapshot.returned_early = returned_early


func restore(snapshot: ScenarioVmSnapshot) -> void:
	context = snapshot.native_context.copy() if snapshot.native_context != null else null
	secondary_door = snapshot.secondary_door
	no_second_door = snapshot.no_second_door
	returned_early = snapshot.returned_early
