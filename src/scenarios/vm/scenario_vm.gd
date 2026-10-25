## Runs Classic, Safe and gameplay operation records through one deterministic scheduler.
class_name ScenarioVm
extends RefCounted

const CLASSIC_CALL_LIMIT: int = 20
const ACTION_CALL_LIMIT: int = 32
const EXECUTION_STEP_LIMIT: int = 65536
const TRACE_LIMIT: int = 4096
const DEBUG_PROGRAM_ID := "__debug_instruction__"

var _definition: ScenarioDefinition
var _state := ScenarioExecutionState.new()
var _execution_step_limit: int = EXECUTION_STEP_LIMIT
var _debug_program: ScenarioProgramDefinition
var _bind_saved_header: bool = false
var diagnostics := ScenarioVmDiagnostics.new()


func configure(definition: ScenarioDefinition, execution_step_limit: int = EXECUTION_STEP_LIMIT) -> void:
	assert(execution_step_limit > 0 and execution_step_limit <= EXECUTION_STEP_LIMIT)
	_definition = definition
	_execution_step_limit = execution_step_limit
	reset()


func reset() -> void:
	_state = ScenarioExecutionState.new()
	_debug_program = null
	_bind_saved_header = false
	diagnostics.clear()


func start_program(program_id: String, context: ScenarioExecutionContext = null, placed_owner: String = "") -> ScenarioVmResult:
	if _definition == null:
		return ScenarioVmResult.failed(&"scenario_not_configured", "Scenario VM has no validated definition.")
	if is_active() or _state.pending_request != null:
		return ScenarioVmResult.failed(&"scenario_already_running", "A scenario program is already active.")
	if _definition.program_by_id(program_id) == null:
		if not _definition.native_program_is_unavailable(program_id): return ScenarioVmResult.failed(&"unknown_scenario_program", "Scenario program '%s' is unavailable." % program_id)
	_bind_saved_header = false
	var entry_context := ScenarioExecutionContext.empty() if context == null else context.copy()
	var mode := ScenarioClassicInvocationRecord.Mode.MACRO if entry_context.calling_context in [&"battle-macro", &"monster-death-macro"] else ScenarioClassicInvocationRecord.Mode.MODE_ONE if entry_context.is_native_mode_one() else ScenarioClassicInvocationRecord.Mode.PLACED
	if not placed_owner.is_empty() and (mode != ScenarioClassicInvocationRecord.Mode.PLACED or entry_context.trigger_id != placed_owner): return ScenarioVmResult.failed(&"invalid_native_entry","A placed Action Point requires its declared entry owner.")
	_state.completion = ScenarioNativeCompletion.new()
	_enter_program(program_id, entry_context, mode, null, placed_owner)
	_state.halted = false
	_state.last_outcome = null
	_state.append_trace({"event": "start", "programId": program_id})
	return ScenarioVmResult.completed()


func _enter_program(program_id: String, context: ScenarioExecutionContext, mode: ScenarioClassicInvocationRecord.Mode, queued_source: CombatQueuedMacroSource = null, placed_owner: String = "") -> void:
	var entry := ScenarioClassicInvocationRecord.new()
	entry.position_program_id = program_id
	entry.entry_program_id = program_id
	entry.placed_trigger_id = placed_owner
	entry.position_kind = ScenarioClassicProgramState.Kind.PROGRAM if _definition.program_by_id(program_id) != null else ScenarioClassicProgramState.Kind.EMPTY
	entry.context = context.copy()
	entry.mode = mode
	entry.queued_source = queued_source.copy() if queued_source != null else null
	var record := _state.append_record(ScenarioExecutionRecord.Kind.CLASSIC)
	record.classic = entry
	_state.classic.code = ScenarioClassicProgramState.new()
	_state.classic.code.program_id = program_id
	_state.classic.code.kind = entry.position_kind
	_state.classic.code.context = entry.context.copy()
	_state.classic.returns.clear()
	if entry.mode != ScenarioClassicInvocationRecord.Mode.MACRO:
		ScenarioClassicExecutionRules.clear_encounter(_state.classic)
		_state.classic.encounter_remaining = 0


func start_program_call(call: ScenarioProgramCall, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	if _definition == null or _state.pending_request != null or call == null:
		return ScenarioVmResult.failed(&"scenario_already_running", "The program caller cannot enter this execution boundary.")
	if not is_active(): _state.completion = ScenarioNativeCompletion.new()
	var application := call.kind == ScenarioProgramCall.Kind.APPLICATION
	if application:
		if is_active():
			var parent: ScenarioExecutionRecord = _state.records.back()
			if parent.kind != ScenarioExecutionRecord.Kind.OPERATION or parent.operation.phase != ScenarioOperationExecutionRecord.Phase.HOST_RETURN:
				return ScenarioVmResult.failed(&"invalid_application_return", "An application hook requires its explicit suspended operation.")
			for record: ScenarioExecutionRecord in _state.records:
				if record.kind == ScenarioExecutionRecord.Kind.OPERATION and record.operation.return_kind == ScenarioOperationExecutionRecord.ReturnKind.APPLICATION:
					return ScenarioVmResult.failed(&"nested_party_defeat_handoff", "An application hook cannot interrupt another application hook.")
	elif is_active() or call.kind != ScenarioProgramCall.Kind.MACRO or call.macro.return_kind != ScenarioMacroCall.ReturnKind.DIRECT:
		return ScenarioVmResult.failed(&"scenario_already_running", "The direct macro caller requires an idle runner.")
	if not is_active(): _bind_saved_header = false
	_bind_runtime(runtime)
	var pending := call.copy()
	if application and is_active(): pending.application.caller_control = ScenarioClassicCallerState.capture(_state.classic)
	_state.halted = false
	var owner := _new_direct_operation(ScenarioOperationExecutionRecord.ReturnKind.APPLICATION if application else ScenarioOperationExecutionRecord.ReturnKind.DIRECT)
	var owner_id: int = _state.records.back().id
	var result := _continue_operation(owner, ScenarioRuntimeOperationResult.calling(pending), runtime)
	if application: result.application_owner_id = owner_id
	return result


func _new_direct_operation(kind: ScenarioOperationExecutionRecord.ReturnKind = ScenarioOperationExecutionRecord.ReturnKind.DIRECT) -> ScenarioOperationExecutionRecord:
	var record := _state.append_record(ScenarioExecutionRecord.Kind.OPERATION)
	record.operation = ScenarioOperationExecutionRecord.new()
	record.operation.return_kind = kind
	return record.operation


func start_debug_instruction(instruction: ClassicActionDefinition, context: ScenarioExecutionContext = null) -> ScenarioVmResult:
	if instruction == null or _definition == null or is_active() or _state.pending_request != null:
		return ScenarioVmResult.failed(&"debug_instruction_unavailable", "The debug scenario instruction cannot start at this boundary.")
	_debug_program = ScenarioProgramDefinition.new(DEBUG_PROGRAM_ID, &"debug", DEBUG_PROGRAM_ID, [instruction])
	var result := start_program_for_debug(context)
	return result


func start_program_for_debug(context: ScenarioExecutionContext) -> ScenarioVmResult:
	_bind_saved_header = false
	_state.completion = ScenarioNativeCompletion.new()
	var record := _state.append_record(ScenarioExecutionRecord.Kind.CLASSIC)
	record.classic = ScenarioClassicInvocationRecord.new()
	record.classic.mode = ScenarioClassicInvocationRecord.Mode.DEBUG
	record.classic.position_program_id = DEBUG_PROGRAM_ID
	record.classic.entry_program_id = DEBUG_PROGRAM_ID
	record.classic.context = ScenarioExecutionContext.empty() if context == null else context.copy()
	_state.classic.code = ScenarioClassicProgramState.new()
	_state.classic.code.program_id = DEBUG_PROGRAM_ID
	_state.classic.code.context = record.classic.context.copy()
	_state.halted = false
	_state.append_trace({"event": "debug-start"})
	return ScenarioVmResult.completed()


func run(runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	_bind_runtime(runtime)
	if _state.pending_request != null:
		return ScenarioVmResult.failed(&"interaction_pending", "The Scenario VM is waiting for interaction '%s'." % _state.pending_request.request_id)
	var remaining_steps := _execution_step_limit
	var events: Array[DomainEvent] = []
	var party_revived := false
	while not _state.records.is_empty():
		if remaining_steps <= 0:
			return _fail(&"scenario_step_limit", "Scenario execution exceeded %s steps." % _execution_step_limit, events)
		remaining_steps -= 1
		var record: ScenarioExecutionRecord = _state.records.back()
		var result: ScenarioVmResult
		match record.kind:
			ScenarioExecutionRecord.Kind.CLASSIC: result = _step_classic(record.classic, runtime)
			ScenarioExecutionRecord.Kind.SAFE: result = _step_safe(record.safe, runtime)
			_: result = _step_operation(record.operation, runtime)
		events.append_array(result.events)
		party_revived = party_revived or result.party_revived
		if result.state == ScenarioVmResult.State.FAILED:
			return _fail(result.error_code, result.error_message, events)
		if result.state != ScenarioVmResult.State.COMPLETED or result.direct_combat_return != null or result.application_return != null:
			_state.halted = _state.records.is_empty()
			result.events.assign(events)
			result.party_revived = party_revived
			return result
	_state.halted = true
	var completed := ScenarioVmResult.completed(events, _state.last_outcome)
	completed.party_revived = party_revived
	return completed


func resume(response: InteractionResponse, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	if _state.pending_request == null:
		return ScenarioVmResult.failed(&"no_interaction_pending", "The Scenario VM has no interaction to resume.")
	if response == null or response.request_id != _state.pending_request.request_id:
		return ScenarioVmResult.rejected(&"interaction_mismatch", "The interaction response does not match the issuing VM request.")
	if not response.is_supported_kind():
		return ScenarioVmResult.rejected(&"invalid_interaction_response", "The response payload does not match its interaction kind.")
	_bind_runtime(runtime)
	var owner: ScenarioExecutionRecord = _state.records.back()
	var call := owner.operation
	_restore_diagnostic(call)
	var retry := snapshot() if call.continuation.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD else null
	var counter := _state.request_counter
	var continuation := call.continuation.copy()
	if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.CLASSIC: runtime.bind_execution(_state.classic, _state.records[-2].classic)
	var operation := runtime.resume_safe(continuation, response, _state.next_request_id()) if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE else runtime.resume_classic(continuation, response, _state.next_request_id())
	if operation.is_rejection:
		_state.request_counter = counter
		return ScenarioVmResult.rejected(operation.error_code, operation.error_message)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		if retry != null and restore(retry): return ScenarioVmResult.failed(operation.error_code, operation.error_message)
		return _fail(operation.error_code, operation.error_message, operation.events)
	_state.append_trace({"event": "resume", "requestId": _state.pending_request.request_id})
	_state.pending_request = null
	_state.pending_owner_id = 0
	return _continue_operation(call, operation, runtime)


func complete_debug_victory(runtime: RealmzRuntimeApi, events: Array[DomainEvent]) -> ScenarioVmResult:
	if _state.pending_request == null or _state.pending_request.kind != InteractionRequest.COMBAT:
		return ScenarioVmResult.failed(&"invalid_vm_continuation", "Debug victory requires an active combat request.")
	var call: ScenarioOperationExecutionRecord = _state.records.back().operation
	var expected := ScenarioRuntimeContinuation.SAFE_COMBAT if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE else ScenarioRuntimeContinuation.CLASSIC_COMBAT
	if call.continuation.kind != expected:
		return ScenarioVmResult.failed(&"invalid_vm_continuation", "Debug victory cannot bypass a nested combat continuation.")
	var operation := runtime.complete_debug_victory(call.continuation, _state.next_request_id(), events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return ScenarioVmResult.failed(operation.error_code, operation.error_message, operation.events)
	_state.pending_request = null
	_state.pending_owner_id = 0
	return _continue_operation(call, operation, runtime)


func resume_handoff(handoff: ScenarioVmHandoff, operation: ScenarioRuntimeOperationResult, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	_bind_runtime(runtime)
	if _state.records.is_empty() or _state.pending_request != null or handoff == null or operation == null:
		return ScenarioVmResult.failed(&"invalid_vm_handoff", "The suspended Scenario VM is unavailable.")
	var owner: ScenarioExecutionRecord = _state.records.back()
	if owner.kind != ScenarioExecutionRecord.Kind.OPERATION or owner.operation.phase != ScenarioOperationExecutionRecord.Phase.HOST_RETURN:
		return ScenarioVmResult.failed(&"invalid_vm_handoff", "The suspended operation has no explicit return owner.")
	if handoff.runtime == null or owner.operation.handoff.to_data() != handoff.runtime.to_data():
		return ScenarioVmResult.failed(&"invalid_vm_handoff", "The handoff does not match its explicit suspended owner.")
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return _fail(operation.error_code, operation.error_message, operation.events)
	return _continue_operation(owner.operation, operation, runtime)


func snapshot() -> ScenarioVmSnapshot:
	var saved := ScenarioVmSnapshot.new()
	var detached := ScenarioExecutionState.from_data(_state.to_data())
	if detached == null:
		push_error("The execution state could not detach for saving or rollback.")
		return null
	saved.set_execution(detached)
	return saved


func restore(value: Variant) -> bool:
	var saved: ScenarioVmSnapshot = value if value is ScenarioVmSnapshot else null
	if saved == null or _definition == null: return false
	var restored := ScenarioExecutionState.from_data(saved.execution.to_data()) if saved.execution != null else ScenarioLegacyExecutionCodec.convert(saved, _definition)
	if not ScenarioExecutionRestoreRules.is_valid(restored, _definition): return false
	_state = restored
	_bind_saved_header = saved.execution != null
	return true


func classic_record_id() -> String:
	return _state.classic.code.program_id if _state.classic.code != null else ""


func native_completion() -> ScenarioNativeCompletion:
	return _state.completion.copy()


func trace() -> Array[Dictionary]:
	return _state.trace.duplicate(true)


func is_active() -> bool:
	return not _state.halted and not _state.records.is_empty()


func pending_request() -> InteractionRequest:
	return _state.pending_request


func _step_classic(entry: ScenarioClassicInvocationRecord, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	if entry.phase == ScenarioClassicInvocationRecord.Phase.ENTRY:
		if not entry.placed_trigger_id.is_empty() and not runtime.native_action_points.placed_entry_is_valid(entry.placed_trigger_id,entry.entry_program_id): return ScenarioVmResult.failed(&"invalid_native_entry","The placed Action Point entry does not match its selected record.")
		if entry.mode == ScenarioClassicInvocationRecord.Mode.MODE_ONE: runtime.native_action_points.begin()
		entry.phase = ScenarioClassicInvocationRecord.Phase.CODE
	if entry.phase == ScenarioClassicInvocationRecord.Phase.COMPLETE:
		return _complete_classic(entry, runtime)
	if entry.phase == ScenarioClassicInvocationRecord.Phase.ENCOUNTER:
		runtime.bind_execution(_state.classic, entry)
		var context := (entry.context if _state.classic.code == null else _state.classic.code.context).without_encounter().merged(ScenarioExecutionContext.encounter(_state.classic.encounter_kind, _state.classic.encounter_id).set_encounter_attempt(_state.classic.encounter_attempt))
		var operation := runtime.request_classic_encounter(_state.classic.encounter_kind, _state.classic.encounter_id, _state.next_request_id(), context, entry.encounter_reload)
		entry.encounter_reload = false
		return _accept_operation(operation, ScenarioOperationExecutionRecord.ReturnKind.CLASSIC, runtime)
	var resolved := _resolve_program(entry, runtime)
	if resolved.state == ScenarioVmResult.State.FAILED or entry.phase != ScenarioClassicInvocationRecord.Phase.CODE: return resolved
	if _state.classic.code.kind != ScenarioClassicProgramState.Kind.PROGRAM:
		if _state.classic.returns.is_empty(): _state.classic.gosub = false
		var runs_keep := _state.classic.code.kind == ScenarioClassicProgramState.Kind.KEEP_CODES and entry.native_slot <= 7
		entry.native_slot = 8
		if runs_keep:
			var context := entry.execution_context(_state.classic.code.context)
			var operand := _state.classic.code.keep_operand(_definition)
			_state.append_trace({"event": "execute-classic", "programId": _state.classic.code.program_id, "cursor": 0, "slot": 7, "rawOpcode": 24, "opcode": 24, "id": operand, "stackDepth": _state.classic.returns.size()})
			runtime.bind_execution(_state.classic, entry)
			return _accept_operation(runtime.execute_classic(ClassicActionDefinition.new(7, 24, 24, operand, false, []), _state.next_request_id(), context), ScenarioOperationExecutionRecord.ReturnKind.CLASSIC, runtime)
		ScenarioClassicExecutionRules.finish_record(_state.classic, entry)
		return ScenarioVmResult.completed()
	var program := _program(_state.classic.code.program_id)
	if entry.cursor >= program.instruction_count():
		ScenarioClassicExecutionRules.finish_record(_state.classic, entry)
		return ScenarioVmResult.completed()
	var instruction: Variant = program.instruction_at(entry.cursor)
	if instruction is CallScenarioActionInstruction:
		var call: CallScenarioActionInstruction = instruction
		return _call_from_timeline(entry, call, program, runtime)
	if not instruction is ClassicActionDefinition:
		return ScenarioVmResult.failed(&"unknown_scenario_instruction", "The Classic record contains an unknown instruction.")
	var original_action: ClassicActionDefinition = instruction
	return _execute_classic(entry, program, original_action, runtime)


func _execute_classic(entry: ScenarioClassicInvocationRecord, program: ScenarioProgramDefinition, original_action: ClassicActionDefinition, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	var action := ScenarioClassicExecutionRules.prepare_action(_state.classic, original_action)
	diagnostics.capture_instruction(program.id, action)
	var source_cursor := entry.cursor
	entry.cursor += 1
	entry.native_slot = action.slot + 1
	if action.opcode in [4, 5]:
		entry.encounter_exit = ScenarioClassicExecutionRules.capture(_state.classic, entry)
	if ClassicOpcodeCatalog.is_executable(action.opcode):
		_state.append_trace({"event": "execute-classic", "programId": program.id, "cursor": source_cursor, "slot": action.slot, "rawOpcode": action.raw_opcode, "opcode": action.opcode, "id": action.operand_id, "stackDepth": _state.classic.returns.size()})
	if action.opcode == 111:
		_state.append_trace({"event": "classic-return", "programId": program.id})
		ScenarioClassicExecutionRules.pull_return(_state.classic, entry)
		diagnostics.clear_instruction()
		return ScenarioVmResult.completed()
	if action.opcode == 112:
		if not _state.classic.returns.is_empty(): _state.classic.returns.pop_back()
		diagnostics.clear_instruction()
		return ScenarioVmResult.completed()
	if action.opcode == 39:
		return ScenarioClassicExecutionRules.apply(ScenarioVmDirective.branch_xap(action.operand_id, false), _definition, _state.classic, entry, action)
	if not ClassicOpcodeCatalog.is_executable(action.opcode):
		if not _definition.allows_classic_fallthrough() or ClassicOpcodeCatalog.disposition(action.opcode) not in [ClassicOpcodeCatalog.DISPOSITION_UNKNOWN, ClassicOpcodeCatalog.DISPOSITION_CLASSIC_RESERVED]:
			return ScenarioVmResult.failed(&"unsupported_classic_opcode", "Classic opcode %d in '%s' is not implemented." % [action.raw_opcode, program.id])
		_state.append_trace({"event": "classic-unrecognized-skipped", "programId": program.id, "slot": action.slot, "rawOpcode": action.raw_opcode, "opcode": action.opcode, "id": action.operand_id, "extraCode": action.extra_code, "stackDepth": _state.classic.returns.size()})
		diagnostics.clear_instruction()
		return ScenarioVmResult.completed()
	var saved_code := _state.classic.code.copy() if action.opcode in [2, 56, 107] else null
	var saved_flag := ScenarioClassicExecutionState.ENCOUNTER_KINDS.find(_state.classic.encounter_kind) if action.opcode == 48 else -1
	var context := entry.execution_context(_state.classic.code.context)
	runtime.bind_execution(_state.classic, entry)
	var operation := runtime.execute_classic(action, _state.next_request_id(), context)
	operation = ScenarioNativeOperationRules.after_operation(entry, operation, context, runtime)
	return _accept_operation(operation, ScenarioOperationExecutionRecord.ReturnKind.CLASSIC, runtime, "", program.id, source_cursor, saved_code, saved_flag)


func _resolve_program(entry: ScenarioClassicInvocationRecord, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	var code := _state.classic.code
	if code.kind != ScenarioClassicProgramState.Kind.PROGRAM or code.program_id == DEBUG_PROGRAM_ID or entry.cursor != 0 or code.context.program_resolved:
		return ScenarioVmResult.completed()
	var original := code.program_id
	var resolved := runtime.resolve_program_id(original)
	if _definition.program_by_id(resolved) == null:
		if not _definition.native_program_is_unavailable(resolved):
			return ScenarioVmResult.failed(&"unknown_scenario_program", "The Classic program override references unavailable program '%s'." % resolved)
		code.kind = ScenarioClassicProgramState.Kind.EMPTY
		code.program_id = resolved
		entry.position_program_id = resolved
		entry.position_kind = code.kind
		return ScenarioVmResult.completed()
	code.context.mark_program_resolved(original, resolved)
	code.program_id = resolved
	entry.position_program_id = resolved
	if resolved != original: _state.append_trace({"event": "program-override", "sourceProgramId": original, "targetProgramId": resolved})
	return ScenarioVmResult.completed()


func _complete_classic(entry: ScenarioClassicInvocationRecord, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	var events: Array[DomainEvent] = []
	if entry.completion.remove_selected_ap:
		var removed := runtime.native_action_points.remove_selected()
		if removed.state == ScenarioRuntimeOperationResult.State.FAILED: return ScenarioVmResult.failed(removed.error_code,removed.error_message)
		events = removed.events
		entry.completion.remove_selected_ap = false
	var owns_header := entry.mode == ScenarioClassicInvocationRecord.Mode.MODE_ONE or not entry.placed_trigger_id.is_empty() or entry.mode == ScenarioClassicInvocationRecord.Mode.MACRO and entry.completion.exit_path == ScenarioNativeCompletion.Exit.KEEP_CODES
	if owns_header and not entry.secondary_door and not entry.returned_early and not entry.completion.header_suppressed:
		entry.secondary_door = true
		var operation := runtime.native_action_points.complete_invocation(entry.context, entry.no_second_door, entry.placed_trigger_id)
		operation.events = events + operation.events
		return _accept_operation(operation, ScenarioOperationExecutionRecord.ReturnKind.CLASSIC, runtime)
	entry.completion.header_suppressed = entry.completion.header_suppressed or entry.secondary_door or entry.returned_early
	entry.completion.recheck_suppressed = entry.no_second_door
	_state.records.pop_back()
	if _state.records.is_empty():
		_state.completion = entry.completion.copy()
	else:
		var parent: ScenarioExecutionRecord = _state.records.back()
		if parent.kind == ScenarioExecutionRecord.Kind.OPERATION and parent.operation.phase == ScenarioOperationExecutionRecord.Phase.CHILD:
			parent.operation.phase = ScenarioOperationExecutionRecord.Phase.CHILD_RETURN
			parent.operation.child_return_value = entry.return_value
	return ScenarioVmResult.completed(events)


func _accept_operation(operation: ScenarioRuntimeOperationResult, return_kind: ScenarioOperationExecutionRecord.ReturnKind, runtime: RealmzRuntimeApi, target: String = "", program_id: String = "", cursor: int = -1, restore_code: ScenarioClassicProgramState = null, restore_encounter_flag: int = -1) -> ScenarioVmResult:
	var record := _state.append_record(ScenarioExecutionRecord.Kind.OPERATION)
	record.operation = ScenarioOperationExecutionRecord.new()
	record.operation.return_kind = return_kind
	record.operation.result_target = target
	record.operation.instruction_program_id = program_id
	record.operation.instruction_cursor = cursor
	record.operation.restore_code = restore_code
	record.operation.restore_encounter_flag = restore_encounter_flag
	var result := _settle_operation(record.operation, operation, runtime)
	result.party_revived = operation.party_revived
	return result


func _continue_operation(call: ScenarioOperationExecutionRecord, operation: ScenarioRuntimeOperationResult, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	var settled := _settle_operation(call, operation, runtime)
	if settled.state != ScenarioVmResult.State.COMPLETED or settled.direct_combat_return != null or settled.application_return != null:
		_state.halted = _state.records.is_empty()
		return settled
	var resumed := run(runtime)
	resumed.events.assign(settled.events + resumed.events)
	return resumed


func _settle_operation(call: ScenarioOperationExecutionRecord, operation: ScenarioRuntimeOperationResult, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return ScenarioVmResult.failed(operation.error_code, operation.error_message, operation.events)
	if operation.began_combat: ScenarioClassicExecutionRules.clear_encounter(_state.classic)
	if not operation.loaded_encounter_kind.is_empty():
		_state.classic.encounter_kind = operation.loaded_encounter_kind
		_state.classic.encounter_id = operation.loaded_encounter_id
		_state.classic.encounter_remaining = operation.loaded_encounter_max_times
	if not operation.selected_encounter_kind.is_empty():
		_state.classic.encounter_kind = operation.selected_encounter_kind
		_state.classic.encounter_id = operation.selected_encounter_id
		_state.classic.encounter_attempt = operation.selected_encounter_attempt
	if operation.state == ScenarioRuntimeOperationResult.State.CALL:
		return _push_program_call(call, operation, runtime)
	call.child_call = null
	call.child_restore_code = null
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		call.phase = ScenarioOperationExecutionRecord.Phase.RESPONSE
		call.handoff = null
		call.continuation = operation.continuation.copy()
		_state.pending_request = operation.interaction
		_state.pending_owner_id = _state.records.back().id
		_state.append_trace({"event": "yield", "requestId": operation.interaction.request_id, "kind": String(operation.interaction.kind)})
		return ScenarioVmResult.waiting(operation.interaction, operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.SUSPENDED:
		if operation.handoff == null: return ScenarioVmResult.failed(&"invalid_runtime_handoff", "The runtime suspended without a typed operation.")
		call.phase = ScenarioOperationExecutionRecord.Phase.HOST_RETURN
		call.continuation = null
		call.handoff = operation.handoff.copy()
		var handoff := ScenarioVmHandoff.classic(operation.handoff) if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.CLASSIC else ScenarioVmHandoff.safe(operation.handoff, _state.records.size() - 2, call.result_target)
		return ScenarioVmResult.suspended(handoff, operation.events)
	_state.records.pop_back()
	if call.restore_code != null: _state.classic.code = call.restore_code.copy()
	if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.DIRECT:
		if operation.direct_combat_return == null: return ScenarioVmResult.failed(&"invalid_direct_return", "The direct caller has no typed combat result.", operation.events)
		var returned := ScenarioVmResult.completed()
		returned.direct_combat_return = operation.direct_combat_return
		return returned
	if call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.SAFE:
		var parent: ScenarioExecutionRecord = _state.records.back()
		if not call.result_target.is_empty(): parent.safe.scope.set_local(call.result_target, operation.value)
	else:
		var entry: ScenarioClassicInvocationRecord = _state.records.back().classic
		if operation.push_classic_return:
			var pushed := ScenarioClassicExecutionRules.push_return(_state.classic, entry)
			if pushed.state == ScenarioVmResult.State.FAILED: return pushed
		if call.restore_encounter_flag >= 0:
			_state.classic.encounter_kind = ScenarioClassicExecutionState.ENCOUNTER_KINDS[call.restore_encounter_flag]
			_state.classic.encounter_id = runtime.encounters.loaded_id(_state.classic.encounter_kind)
			if _state.classic.encounter_kind.is_empty(): ScenarioClassicExecutionRules.clear_encounter(_state.classic)
		if _state.classic.code != null and (entry.position_program_id != _state.classic.code.program_id or entry.position_kind != _state.classic.code.kind):
			entry.position_program_id = _state.classic.code.program_id
			entry.position_kind = _state.classic.code.kind
			entry.cursor = ScenarioProgramPosition.cursor_for_slot(_program(entry.position_program_id), entry.native_slot) if entry.position_kind == ScenarioClassicProgramState.Kind.PROGRAM else 0
		var applied := ScenarioClassicExecutionRules.apply(operation.directive, _definition, _state.classic, entry, _issuing_action(call))
		if applied.state == ScenarioVmResult.State.FAILED: return applied
	diagnostics.clear_instruction()
	return ScenarioVmResult.completed(operation.events)


func _push_program_call(owner: ScenarioOperationExecutionRecord, operation: ScenarioRuntimeOperationResult, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	if operation.call == null or _state.records.size() >= ScenarioExecutionState.MAX_RECORDS - 1:
		return ScenarioVmResult.failed(&"invalid_program_call", "The program call is missing or exceeds the execution bound.", operation.events)
	var call := operation.call.copy()
	if call == null: return ScenarioVmResult.failed(&"invalid_program_call", "The program call cannot detach.", operation.events)
	owner.phase = ScenarioOperationExecutionRecord.Phase.CHILD
	owner.child_return_value = 0
	owner.continuation = null
	owner.handoff = null
	owner.child_call = call
	owner.child_restore_code = _state.classic.code.copy() if call.restores_code() and _state.classic.code != null else null
	if _definition.program_by_id(call.program_id()) == null and not _definition.native_program_is_unavailable(call.program_id()):
		return ScenarioVmResult.failed(&"unknown_scenario_program", "The called program is unavailable.", operation.events)
	if call.kind == ScenarioProgramCall.Kind.MACRO:
		runtime.macros.enter_source(call.macro, _state.classic)
		_enter_program(call.program_id(), call.context(), ScenarioClassicInvocationRecord.Mode.MACRO, call.macro.queued_source)
	else:
		var depth := 0
		for record: ScenarioExecutionRecord in _state.records:
			if record.kind == ScenarioExecutionRecord.Kind.OPERATION and record.operation.child_call != null and record.operation.child_call.kind == ScenarioProgramCall.Kind.TIMER: depth += 1
		if depth > ScenarioProgramCall.TIMER_CALL_LIMIT: return ScenarioVmResult.failed(&"clock_timer_depth", "Nested timed programs exceeded the engine safety bound.", operation.events)
		_enter_program(call.program_id(), call.context(), ScenarioClassicInvocationRecord.Mode.MODE_ONE)
	_state.append_trace({"event": "program-call", "programId": call.program_id()})
	return ScenarioVmResult.completed(operation.events)


func _step_operation(owner: ScenarioOperationExecutionRecord, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	if owner.phase != ScenarioOperationExecutionRecord.Phase.CHILD_RETURN or owner.child_call == null:
		return ScenarioVmResult.failed(&"invalid_vm_operation", "The operation is not ready for its explicit child return.")
	var call := owner.child_call
	if call.kind == ScenarioProgramCall.Kind.APPLICATION: return _return_application(call.application)
	owner.child_return_value = 0
	if call.restores_code(): _state.classic.code = owner.child_restore_code.copy() if owner.child_restore_code != null else null
	owner.child_restore_code = null
	owner.child_call = null
	if call.kind == ScenarioProgramCall.Kind.MACRO: runtime.macros.return_source(call.macro, _state.classic)
	return _settle_operation(owner, runtime.complete_program_call(call, _state.next_request_id()), runtime)


func _return_application(call: ScenarioApplicationCall) -> ScenarioVmResult:
	var returned := ScenarioApplicationReturn.new()
	returned.owner_id = _state.records.back().id
	returned.native_return_value = _state.records.back().operation.child_return_value
	if call.caller_control != null: call.caller_control.restore_into(_state.classic)
	_state.records.pop_back()
	if not _state.records.is_empty():
		var parent: ScenarioExecutionRecord = _state.records.back()
		if parent.kind != ScenarioExecutionRecord.Kind.OPERATION or parent.operation.phase != ScenarioOperationExecutionRecord.Phase.HOST_RETURN:
			return ScenarioVmResult.failed(&"invalid_application_return", "The hook lost its explicit suspended operation.")
		var owner := parent.operation
		returned.handoff = ScenarioVmHandoff.classic(owner.handoff) if owner.return_kind == ScenarioOperationExecutionRecord.ReturnKind.CLASSIC else ScenarioVmHandoff.safe(owner.handoff, _state.records.size() - 2, owner.result_target)
	var result := ScenarioVmResult.completed()
	result.application_return = returned
	return result


func _step_safe(record: ScenarioSafeExecutionRecord, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	var action := _definition.action_by_id(record.scope.definition_id)
	if record.cursor >= action.program.instruction_count():
		if action.return_type != &"void": return ScenarioVmResult.failed(&"scenario_action_missing_return", "The Scenario Action completed without its declared return.")
		return _return_safe(record, null)
	var instruction := action.program.instruction_at(record.cursor)
	_state.append_trace({"event": "execute-action", "actionId": action.id, "cursor": record.cursor, "instructionKind": instruction.kind})
	match instruction.kind:
		SafeInstructionDefinition.Kind.OPERATION:
			var arguments := SafeExpressionEvaluator.evaluate_instruction_arguments(instruction, record.scope, runtime)
			if not arguments["ok"]: return ScenarioVmActionRules.expression_failure(arguments)
			record.cursor += 1
			var saved_code := _state.classic.code.copy() if instruction.capability == "core.combat.start" and _state.classic.code != null else null
			return _accept_operation(runtime.execute_safe(instruction.capability, ScenarioVmActionRules.argument_values(arguments), _state.next_request_id()), ScenarioOperationExecutionRecord.ReturnKind.SAFE, runtime, instruction.result_target, "", -1, saved_code)
		SafeInstructionDefinition.Kind.CALL_ACTION:
			var arguments := SafeExpressionEvaluator.evaluate_instruction_arguments(instruction, record.scope, runtime)
			if not arguments["ok"]: return ScenarioVmActionRules.expression_failure(arguments)
			record.cursor += 1
			return _push_action(instruction.action_id, ScenarioVmActionRules.argument_values(arguments), instruction.result_target, record.scope.context.calling_context, record.scope.context, false)
		SafeInstructionDefinition.Kind.RETURN:
			var evaluated := {"ok": true, "value": null} if instruction.value == null else SafeExpressionEvaluator.evaluate(instruction.value, record.scope, runtime)
			if not evaluated["ok"]: return ScenarioVmActionRules.expression_failure(evaluated)
			if not SafeExpressionEvaluator.value_matches_type(evaluated["value"], action.return_type): return ScenarioVmResult.failed(&"scenario_action_return_type", "The Scenario Action returned a value outside its declared type.")
			return _return_safe(record, evaluated["value"])
		SafeInstructionDefinition.Kind.HALT:
			return ScenarioSafeExecutionRules.halt_invocation(_state, record.invocation_owner_id, instruction.outcome)
	return ScenarioSafeExecutionRules.step(record, instruction, runtime)


func _call_from_timeline(entry: ScenarioClassicInvocationRecord, instruction: CallScenarioActionInstruction, program: ScenarioProgramDefinition, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	var code := _state.classic.code
	if code.timeline_values == null:
		code.timeline_values = ScenarioExpressionScope.new(code.program_id)
		code.timeline_values.context = code.context.copy()
	var arguments := SafeExpressionEvaluator.evaluate_call_arguments(instruction, code.timeline_values, runtime)
	if not arguments["ok"]: return ScenarioVmActionRules.expression_failure(arguments)
	entry.cursor += 1
	var calling := code.context.calling_context
	if calling == &"": calling = &"encounter" if program.owner_kind in [&"simple-encounter-result", &"complex-encounter-result"] else &"action"
	return _push_action(instruction.action_id, ScenarioVmActionRules.argument_values(arguments), instruction.result_target, calling, code.context, true)


func _push_action(action_id: String, arguments: Dictionary, target: String, calling: StringName, context: ScenarioExecutionContext, require_public: bool) -> ScenarioVmResult:
	var error := ScenarioSafeExecutionRules.validate_call(_definition, action_id, arguments, calling, require_public)
	if error.state == ScenarioVmResult.State.FAILED: return error
	var parent: ScenarioExecutionRecord = _state.records.back() if not _state.records.is_empty() else null
	var owner_id := 0 if parent == null else parent.id if parent.kind == ScenarioExecutionRecord.Kind.CLASSIC else parent.safe.invocation_owner_id
	var depth := 0
	for record: ScenarioExecutionRecord in _state.records:
		if record.kind == ScenarioExecutionRecord.Kind.SAFE and record.safe.invocation_owner_id == owner_id: depth += 1
	if depth >= ACTION_CALL_LIMIT: return ScenarioVmResult.failed(&"scenario_action_call_limit", "Scenario Action call stack exceeded 32 records.")
	var record := _state.append_record(ScenarioExecutionRecord.Kind.SAFE)
	record.safe = ScenarioSafeExecutionRecord.new()
	record.safe.invocation_owner_id = owner_id
	record.safe.scope = ScenarioExpressionScope.new(action_id)
	record.safe.scope.parameters = arguments.duplicate(true)
	record.safe.scope.context = context.copy()
	record.safe.scope.context.calling_context = calling
	record.safe.return_target = target
	_state.append_trace({"event": "call-action", "actionId": action_id, "depth": depth + 1})
	return ScenarioVmResult.completed()


func _return_safe(record: ScenarioSafeExecutionRecord, value: Variant) -> ScenarioVmResult:
	_state.records.pop_back()
	if _state.records.is_empty():
		_state.last_outcome = value
	elif not record.return_target.is_empty():
		var parent: ScenarioExecutionRecord = _state.records.back()
		if parent.kind == ScenarioExecutionRecord.Kind.SAFE: parent.safe.scope.set_local(record.return_target, value)
		else: _state.classic.code.timeline_values.set_local(record.return_target, value)
	return ScenarioVmResult.completed()


func _bind_runtime(runtime: RealmzRuntimeApi) -> void:
	var header := runtime.classic_execution()
	if _bind_saved_header:
		header.header_replaced = _state.classic.header.header_replaced
		header.map_id = _state.classic.header.map_id
		header.coordinate = _state.classic.header.coordinate
		header.trigger_id = _state.classic.header.trigger_id
		_bind_saved_header = false
	_state.classic.header = header
	runtime.bind_execution(_state.classic)


func _program(id: String) -> ScenarioProgramDefinition:
	return _debug_program if id == DEBUG_PROGRAM_ID else _definition.program_by_id(id)


func _issuing_action(call: ScenarioOperationExecutionRecord) -> ClassicActionDefinition:
	var program := _program(call.instruction_program_id)
	if program == null or call.instruction_cursor < 0 or call.instruction_cursor >= program.instruction_count(): return null
	var instruction: Variant = program.instruction_at(call.instruction_cursor)
	return instruction if instruction is ClassicActionDefinition else null


func _restore_diagnostic(call: ScenarioOperationExecutionRecord) -> void:
	var action := _issuing_action(call)
	if action != null: diagnostics.capture_instruction(call.instruction_program_id, action)


func _fail(code: StringName, message: String, events: Array[DomainEvent]) -> ScenarioVmResult:
	diagnostics.capture_failure(code, message)
	_state.records.clear()
	_state.pending_request = null
	_state.pending_owner_id = 0
	_state.halted = true
	_state.append_trace({"event": "error", "code": String(code), "message": message})
	return ScenarioVmResult.failed(code, message, events)
