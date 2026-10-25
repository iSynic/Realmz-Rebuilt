## Binds application-hook owners and converts historical suspended callers at restore.
class_name SessionApplicationRestoreRules
extends RefCounted


static func normalize(execution: ScenarioExecutionState, body: ScenarioApplicationContinuationBody, definition: ScenarioDefinition, shared: ClassicExecutionState) -> ScenarioExecutionState:
	if body.application_owner_id >= 1: return execution
	if execution == null or execution.records.is_empty() or execution.records[0].kind != ScenarioExecutionRecord.Kind.CLASSIC: return null
	var caller := ScenarioExecutionState.new()
	if body.resume_kind == &"scenario-party-defeat":
		var saved := body.suspended_vm
		if saved == null or body.vm_handoff == null: return null
		caller = ScenarioLegacyCallCodec.with_handoff(saved, body.vm_handoff, definition)
		if caller == null or not SessionNativeHeaderRestoreRules.normalize_legacy_destination(body.suspended_owner, caller): return null
	var operation := caller.append_record(ScenarioExecutionRecord.Kind.OPERATION)
	operation.operation = ScenarioOperationExecutionRecord.new()
	operation.operation.return_kind = ScenarioOperationExecutionRecord.ReturnKind.APPLICATION
	operation.operation.phase = ScenarioOperationExecutionRecord.Phase.CHILD
	var context := ScenarioApplicationHookWorkflow.start_context(body.hook, body.service_id)
	var call := ScenarioProgramCall.application_call(body.program_id, context)
	if operation.parent_id > 0: call.application.caller_control = ScenarioClassicCallerState.capture(caller.classic)
	operation.operation.child_call = call
	body.application_owner_id = operation.id
	var entry := execution.records[0].classic
	entry.mode = ScenarioClassicInvocationRecord.Mode.MODE_ONE
	entry.entry_program_id = body.program_id
	entry.context = context
	execution.classic.header = shared.copy()
	if not ScenarioLegacyCallCodec.append_child(caller, execution): return null
	body.suspended_vm = null
	body.vm_handoff = null
	return ScenarioExecutionState.from_data(caller.to_data())


static func is_valid(content: RealmzContent, state: GameState, body: ScenarioApplicationContinuationBody, execution: ScenarioExecutionState) -> bool:
	if execution == null or body.suspended_vm != null or body.vm_handoff != null: return false
	var application_index := -1
	for index: int in execution.records.size():
		var record := execution.records[index]
		if record.kind != ScenarioExecutionRecord.Kind.OPERATION or record.operation.return_kind != ScenarioOperationExecutionRecord.ReturnKind.APPLICATION: continue
		if application_index >= 0 or record.id != body.application_owner_id: return false
		application_index = index
	if application_index < 0: return false
	var owner := execution.records[application_index].operation
	if owner.child_call == null or owner.child_call.kind != ScenarioProgramCall.Kind.APPLICATION or owner.phase != ScenarioOperationExecutionRecord.Phase.CHILD: return false
	var call := owner.child_call.application
	if call.program_id != body.program_id or call.context.application_hook != body.hook or call.context.service_id != body.service_id: return false
	if not ScenarioExecutionRestoreRules.is_valid(execution, content.scenario) or not SessionNativeHeaderRestoreRules.execution_is_valid(content, execution): return false
	if not SessionScenarioRestoreValidator.execution_calls_are_valid(content, state, execution): return false
	if body.resume_kind != &"scenario-party-defeat": return application_index == 0 and call.caller_control == null and body.suspended_owner == null
	if application_index < 1 or call.caller_control == null or body.suspended_owner == null: return false
	var suspended := ScenarioExecutionState.from_data(execution.to_data())
	suspended.records.resize(application_index)
	suspended.pending_request = null
	suspended.pending_owner_id = 0
	call.caller_control.restore_into(suspended.classic)
	if not SessionNativeHeaderRestoreRules.destination_guard_is_valid(body.suspended_owner, suspended): return false
	var parent: ScenarioExecutionRecord = suspended.records.back()
	if parent.kind != ScenarioExecutionRecord.Kind.OPERATION or parent.operation.phase != ScenarioOperationExecutionRecord.Phase.HOST_RETURN or not RealmzRuntimeApi.party_defeat_handoff_is_valid(content, state, parent.operation.handoff): return false
	var snapshot := ScenarioVmSnapshot.new()
	snapshot.set_execution(suspended)
	return SessionRestoreValidator.suspended_scenario_owner_is_valid(content, state, body.suspended_owner, snapshot)


static func has_application(execution: ScenarioExecutionState) -> bool:
	for record: ScenarioExecutionRecord in execution.records:
		if record.kind == ScenarioExecutionRecord.Kind.OPERATION and record.operation.return_kind == ScenarioOperationExecutionRecord.ReturnKind.APPLICATION: return true
	return false
