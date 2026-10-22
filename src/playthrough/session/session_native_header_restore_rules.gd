## Validates shared and suspended native destination facts before session replacement.
class_name SessionNativeHeaderRestoreRules
extends RefCounted


static func is_valid(content: RealmzContent, snapshot: SessionSnapshot) -> bool:
	var shared := snapshot.classic_execution
	return shared != null and shared.is_valid(content) and _vm(content, snapshot.scenario_vm, shared) and _owner(content, snapshot.continuation, shared) and _owner(content, snapshot.battle_return_continuation, shared)


static func _vm(content: RealmzContent, snapshot: ScenarioVmSnapshot, shared: ClassicExecutionState, depth: int = 0) -> bool:
	if snapshot == null or depth > 32: return false
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
