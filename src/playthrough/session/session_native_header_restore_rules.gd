## Validates shared and suspended native destination facts before session replacement.
class_name SessionNativeHeaderRestoreRules
extends RefCounted


static func is_valid(content: RealmzContent, snapshot: SessionSnapshot) -> bool:
	var shared := snapshot.classic_execution
	return shared != null and shared.is_valid(content) and _vm(content, snapshot.scenario_vm, shared) and _owner(content, snapshot.continuation, shared) and _owner(content, snapshot.battle_return_continuation, shared)


static func normalize_legacy_destination(owner: SessionContinuation, execution: ScenarioExecutionState) -> bool:
	if owner == null or owner.kind != &"post-move": return true
	var body := owner.exploration()
	if body == null: return false
	if body.action_point_destination_depth == 0 or body.active_trigger_id.is_empty(): return true
	if execution == null or execution.records.is_empty(): return false
	var root := execution.records[0]
	if root.kind != ScenarioExecutionRecord.Kind.CLASSIC or root.classic.placed_trigger_id != body.active_trigger_id: return false
	root.classic.completion.header_suppressed = true
	return true


static func destination_guard_is_valid(owner: SessionContinuation, execution: ScenarioExecutionState) -> bool:
	if owner == null or owner.kind != &"post-move": return true
	var body := owner.exploration()
	if body == null: return false
	if body.action_point_destination_depth == 0 or body.active_trigger_id.is_empty(): return true
	if execution == null or execution.records.is_empty(): return false
	var root := execution.records[0]
	return root.kind == ScenarioExecutionRecord.Kind.CLASSIC and root.classic.placed_trigger_id == body.active_trigger_id and root.classic.completion.header_suppressed


static func _vm(content: RealmzContent, snapshot: ScenarioVmSnapshot, shared: ClassicExecutionState, depth: int = 0) -> bool:
	if snapshot == null or depth > 32: return false
	if snapshot.execution != null:
		if not execution_is_valid(content, snapshot.execution): return false
		var continuation := snapshot.pending_continuation.runtime if snapshot.pending_continuation != null else null
		var child := continuation.nested_vm() if continuation != null else null
		return child == null or _vm(content, child, shared, depth + 1)
	if snapshot.native_context != null and (not shared.header_replaced or shared.map_id.is_empty()): return false
	for index: int in snapshot.frames.size():
		var frame := snapshot.frames[index]
		if frame.native_return_destination == null:
			if not shared.map_id.is_empty() and index + 1 < snapshot.frames.size() and snapshot.frames[index + 1].counts_as_classic_call and (snapshot.native_context != null or not frame.context().trigger_id.is_empty()): return false
			continue
		var header := ClassicExecutionState.new()
		header.map_id = frame.native_return_destination.map_id
		header.coordinate = frame.native_return_destination.coordinate
		header.trigger_id = frame.context().trigger_id
		if not header.is_valid(content):
			header.trigger_id = shared.trigger_id
			if not header.is_valid(content): return false
	var runtime := snapshot.pending_continuation.runtime if snapshot.pending_continuation != null else null
	var nested := runtime.nested_vm() if runtime != null else null
	return nested == null or _vm(content, nested, shared, depth + 1)


static func execution_is_valid(content: RealmzContent, execution: ScenarioExecutionState) -> bool:
	if not execution.classic.header.is_valid(content): return false
	for entry: ScenarioClassicReturnRecord in execution.classic.returns:
		if not return_is_valid(content, entry, execution.classic.header.trigger_id): return false
	for record: ScenarioExecutionRecord in execution.records:
		if record.kind == ScenarioExecutionRecord.Kind.OPERATION and record.operation.child_call != null and record.operation.child_call.kind == ScenarioProgramCall.Kind.APPLICATION:
			var control := record.operation.child_call.application.caller_control
			if control != null:
				for entry: ScenarioClassicReturnRecord in control.returns:
					if not return_is_valid(content, entry, execution.classic.header.trigger_id): return false
		if record.kind != ScenarioExecutionRecord.Kind.CLASSIC: continue
		if not record.classic.placed_trigger_id.is_empty():
			var placed := content.scenario_records.trigger_by_id(record.classic.placed_trigger_id)
			if placed == null or record.classic.context.trigger_id != placed.id or not record.classic.entry_program_id.is_empty() and record.classic.entry_program_id != placed.program_id: return false
		if record.classic.mode == ScenarioClassicInvocationRecord.Mode.MODE_ONE and (not execution.classic.header.header_replaced or execution.classic.header.map_id.is_empty()): return false
		if record.classic.encounter_exit != null and not return_is_valid(content, record.classic.encounter_exit, execution.classic.header.trigger_id): return false
	return true


static func return_is_valid(content: RealmzContent, entry: ScenarioClassicReturnRecord, selected_trigger: String) -> bool:
	if entry.destination == null: return true
	var header := ClassicExecutionState.new()
	header.map_id = entry.destination.map_id
	header.coordinate = entry.destination.coordinate
	header.trigger_id = entry.code.context.trigger_id
	if header.is_valid(content): return true
	header.trigger_id = selected_trigger
	return header.is_valid(content)


static func _owner(content: RealmzContent, owner: SessionContinuation, shared: ClassicExecutionState, depth: int = 0) -> bool:
	if owner == null or owner.is_empty(): return true
	if depth > 32: return false
	var age := owner.age()
	if age != null: return _owner(content, age.resume_continuation, shared, depth + 1)
	var application := owner.application_hook()
	if application == null: return true
	if application.suspended_vm != null and not _vm(content, application.suspended_vm, shared): return false
	return _owner(content, application.suspended_owner, shared, depth + 1) and _handoff(content, application.vm_handoff, shared, depth)


static func _handoff(content: RealmzContent, handoff: ScenarioVmHandoff, shared: ClassicExecutionState, depth: int) -> bool:
	if handoff == null: return true
	if depth > 32 or handoff.runtime == null: return false
	var runtime := handoff.runtime
	if runtime.source_kind != ScenarioRuntimeHandoff.CLASSIC_CLOCK: return true
	var nested := runtime.clock_continuation.nested_vm() if runtime.clock_continuation != null else null
	return nested != null and _vm(content, nested, shared) and _handoff(content, runtime.nested_handoff, shared, depth + 1)
