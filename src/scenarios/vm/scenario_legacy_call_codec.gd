## Flattens historical clock children and host handoffs into explicit runner records.
class_name ScenarioLegacyCallCodec
extends RefCounted


static func normalize(state: ScenarioExecutionState, definition: ScenarioDefinition, depth: int) -> ScenarioExecutionState:
	if state.pending_request == null: return state
	var record: ScenarioExecutionRecord = state.records.back()
	var operation := record.operation
	if not ScenarioLegacyDirectiveCodec.normalize(state, definition): return null
	var body := operation.continuation.body as ScenarioClockContinuationBody
	if body == null: return ScenarioLegacyMacroCodec.normalize(state, definition, depth)
	if not clock_owner_is_valid(state, body, definition): return null
	if body.timer_vm == null:
		operation.continuation = scan_body(body).as_continuation()
		if not body.return_program_id.is_empty():
			if definition.program_by_id(body.return_program_id) == null: return null
			var parent: ScenarioExecutionRecord = state.records[-2]
			state.classic.code = ScenarioClassicProgramState.new(body.return_program_id, parent.classic.context)
			state.classic.returns.clear()
			state.classic.gosub = false
		return state
	var child: ScenarioExecutionState = ScenarioLegacyExecutionCodec.convert(body.timer_vm, definition, depth + 1)
	if child == null or child.pending_request == null or child.pending_request.to_data() != state.pending_request.to_data(): return null
	return state if attach_clock(state, body, child) else null


static func with_handoff(saved: ScenarioVmSnapshot, handoff: ScenarioVmHandoff, definition: ScenarioDefinition, depth: int = 0) -> ScenarioExecutionState:
	if depth > 32 or not ScenarioVmHandoff.is_valid(handoff, saved): return null
	var state: ScenarioExecutionState = ScenarioExecutionState.from_data(saved.execution.to_data()) if saved.execution != null else ScenarioLegacyExecutionCodec.convert(saved, definition, depth)
	if state == null: return null
	if saved.execution != null: return state
	var operation := handoff_operation(state, saved, handoff, definition)
	if operation == null: return null
	state.append_record(ScenarioExecutionRecord.Kind.OPERATION).operation = operation
	if handoff.runtime.source_kind != ScenarioRuntimeHandoff.CLASSIC_CLOCK: return state
	var body := handoff.runtime.clock_continuation.body as ScenarioClockContinuationBody
	if body == null or not clock_owner_is_valid(state, body, definition): return null
	var child := with_handoff(body.timer_vm, handoff.runtime.nested_handoff, definition, depth + 1)
	return state if child != null and attach_clock(state, body, child) else null


static func handoff_operation(state: ScenarioExecutionState, saved: ScenarioVmSnapshot, handoff: ScenarioVmHandoff, definition: ScenarioDefinition) -> ScenarioOperationExecutionRecord:
	var parent: ScenarioExecutionRecord = state.records.back()
	var operation := ScenarioOperationExecutionRecord.new()
	operation.phase = ScenarioOperationExecutionRecord.Phase.HOST_RETURN
	operation.handoff = handoff.runtime.copy()
	if handoff.kind == ScenarioVmHandoff.SAFE_OPERATION:
		if parent.kind != ScenarioExecutionRecord.Kind.SAFE or handoff.frame_index != saved.frames.size() - 1: return null
		operation.return_kind = ScenarioOperationExecutionRecord.ReturnKind.SAFE
		operation.result_target = handoff.result_target
	else:
		if parent.kind != ScenarioExecutionRecord.Kind.CLASSIC or parent.classic.cursor < 1: return null
		var program := definition.program_by_id(parent.classic.position_program_id)
		if program == null or not program.instruction_at(parent.classic.cursor - 1) is ClassicActionDefinition: return null
		operation.instruction_program_id = program.id
		operation.instruction_cursor = parent.classic.cursor - 1
	return operation


static func clock_owner_is_valid(state: ScenarioExecutionState, body: ScenarioClockContinuationBody, definition: ScenarioDefinition) -> bool:
	if state.records.size() < 2: return false
	var owner: ScenarioExecutionRecord = state.records.back()
	var parent: ScenarioExecutionRecord = state.records[-2]
	if owner.kind != ScenarioExecutionRecord.Kind.OPERATION or parent.kind != ScenarioExecutionRecord.Kind.CLASSIC: return false
	var operation := owner.operation
	var program := definition.program_by_id(operation.instruction_program_id)
	if operation.return_kind != ScenarioOperationExecutionRecord.ReturnKind.CLASSIC or program == null or operation.instruction_cursor < 0: return false
	var instruction: Variant = program.instruction_at(operation.instruction_cursor)
	if not instruction is ClassicActionDefinition: return false
	var action: ClassicActionDefinition = instruction
	return action.opcode == 63 and body.resume_slot == action.slot + 1


static func scan_body(body: ScenarioClockContinuationBody) -> ScenarioClockScanBody:
	var scan := ScenarioClockScanBody.new()
	scan.updates.assign(body.updates)
	scan.age_index = body.age_index
	scan.scan_pending = body.scan_pending
	scan.timer_index = body.timer_index
	return scan


static func attach_clock(state: ScenarioExecutionState, body: ScenarioClockContinuationBody, child: ScenarioExecutionState) -> bool:
	if child.records.is_empty() or child.records[0].kind != ScenarioExecutionRecord.Kind.CLASSIC: return false
	var entry := child.records[0].classic
	if entry.context.timed_encounter_id < 0: return false
	entry.mode = ScenarioClassicInvocationRecord.Mode.MODE_ONE
	entry.entry_program_id = body.program_id
	entry.placed_trigger_id = ""
	var owner: ScenarioExecutionRecord = state.records.back()
	owner.operation.phase = ScenarioOperationExecutionRecord.Phase.CHILD
	owner.operation.continuation = null
	owner.operation.handoff = null
	owner.operation.child_call = ScenarioProgramCall.timer_call(scan_body(body), body.program_id, entry.context)
	return append_child(state, child)


static func append_child(state: ScenarioExecutionState, child: ScenarioExecutionState) -> bool:
	var offset := state.record_counter
	for record: ScenarioExecutionRecord in child.records:
		record.id += offset
		record.parent_id += offset
		if record.kind == ScenarioExecutionRecord.Kind.SAFE and record.safe.invocation_owner_id > 0: record.safe.invocation_owner_id += offset
		state.records.append(record)
	state.classic = child.classic
	state.pending_request = child.pending_request
	state.pending_owner_id = child.pending_owner_id + offset if child.pending_owner_id > 0 else 0
	state.request_counter = maxi(state.request_counter, child.request_counter)
	state.record_counter = child.record_counter + offset
	state.trace.append_array(child.trace.slice(0, maxi(0, 4096 - state.trace.size())))
	state.halted = false
	return ScenarioExecutionState.from_data(state.to_data()) != null
