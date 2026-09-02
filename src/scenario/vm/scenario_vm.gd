class_name ScenarioVm
extends RefCounted

const CLASSIC_CALL_LIMIT: int = 20
const ACTION_CALL_LIMIT: int = 32
const EXECUTION_STEP_LIMIT: int = 65536
const TRACE_LIMIT: int = 4096
const DEBUG_PROGRAM_ID := "__debug_instruction__"

var _definition: ScenarioDefinition
var _frames: Array[ScenarioFrame] = []
var _pending_request: InteractionRequest
var _pending_continuation: ScenarioVmPendingContinuation
var _trace: Array[Dictionary] = []
var _request_counter: int = 0
var _step_count: int = 0
var _execution_step_limit: int = EXECUTION_STEP_LIMIT
var _halted: bool = true
var _last_outcome: Variant
var _debug_program: ScenarioProgramDefinition


func configure(definition: ScenarioDefinition, execution_step_limit: int = EXECUTION_STEP_LIMIT) -> void:
	assert(execution_step_limit > 0 and execution_step_limit <= EXECUTION_STEP_LIMIT, "Scenario step limit must remain within the engine budget")
	_definition = definition
	_execution_step_limit = execution_step_limit
	reset()


func reset() -> void:
	_frames.clear()
	_pending_request = null
	_pending_continuation = null
	_trace.clear()
	_request_counter = 0
	_step_count = 0
	_halted = true
	_last_outcome = null
	_debug_program = null


func start_program(program_id: String, context: ScenarioExecutionContext = null) -> ScenarioVmResult:
	if _definition == null:
		return ScenarioVmResult.failed(&"scenario_not_configured", "Scenario VM has no validated definition.")
	if _pending_request != null or not _frames.is_empty():
		return ScenarioVmResult.failed(&"scenario_already_running", "A scenario program is already active.")
	if _definition.program_by_id(program_id) == null:
		return ScenarioVmResult.failed(&"unknown_scenario_program", "Scenario program '%s' is unavailable." % program_id)
	var frame := ScenarioFrame.new(ScenarioFrame.PROGRAM, program_id)
	frame.set_context(ScenarioExecutionContext.empty() if context == null else context)
	_frames.append(frame)
	_halted = false
	_step_count = 0
	_last_outcome = null
	_append_trace({"event": "start", "programId": program_id})
	return ScenarioVmResult.completed()


func start_debug_instruction(instruction: ClassicActionDefinition, context: ScenarioExecutionContext = null) -> ScenarioVmResult:
	if instruction == null or _definition == null or _pending_request != null or not _frames.is_empty():
		return ScenarioVmResult.failed(&"debug_instruction_unavailable", "The debug scenario instruction cannot start at this boundary.")
	_debug_program = ScenarioProgramDefinition.new(DEBUG_PROGRAM_ID, &"debug", DEBUG_PROGRAM_ID, [instruction])
	var frame := ScenarioFrame.new(ScenarioFrame.PROGRAM, DEBUG_PROGRAM_ID)
	frame.set_context(ScenarioExecutionContext.empty() if context == null else context)
	_frames.append(frame)
	_halted = false
	_step_count = 0
	_last_outcome = null
	_append_trace({"event": "debug-start", "opcode": instruction.opcode, "id": instruction.operand_id})
	return ScenarioVmResult.completed()


func run(runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	if _halted:
		return ScenarioVmResult.completed([], _last_outcome)
	if _pending_request != null:
		return ScenarioVmResult.failed(&"interaction_pending", "The Scenario VM is waiting for interaction '%s'." % _pending_request.request_id)
	var events: Array[DomainEvent] = []
	while not _frames.is_empty():
		_step_count += 1
		if _step_count > _execution_step_limit:
			return _fail(&"scenario_step_limit", "Scenario execution exceeded %s steps." % _execution_step_limit, events)
		var frame: ScenarioFrame = _frames.back()
		var result: ScenarioVmResult
		match frame.kind:
			ScenarioFrame.PROGRAM: result = _execute_program_frame(frame, runtime_api)
			ScenarioFrame.ACTION: result = _execute_action_frame(frame, runtime_api)
			ScenarioFrame.ENCOUNTER: result = _execute_encounter_frame(frame, runtime_api)
			_: result = ScenarioVmResult.failed(&"invalid_vm_frame", "Scenario VM frame kind '%s' is unavailable." % frame.kind)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.WAITING:
			return ScenarioVmResult.waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.SUSPENDED:
			return ScenarioVmResult.suspended(result.handoff, events)
		if result.state == ScenarioVmResult.State.FAILED:
			return _fail(result.error_code, result.error_message, events)
	_halted = true
	return ScenarioVmResult.completed(events, _last_outcome)


func resume(response: InteractionResponse, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	if _pending_request == null:
		return ScenarioVmResult.failed(&"no_interaction_pending", "The Scenario VM has no interaction to resume.")
	if response == null or response.request_id != _pending_request.request_id:
		return ScenarioVmResult.failed(&"interaction_mismatch", "The interaction response does not match the issuing VM request.")
	if not response.is_supported_kind():
		return ScenarioVmResult.failed(&"invalid_interaction_response", "The response payload does not match its interaction kind.")
	var events: Array[DomainEvent] = []
	var reward_retry_checkpoint := snapshot() if _is_reward_continuation(_pending_continuation) else null
	var continuation := _pending_continuation.copy() if _pending_continuation != null else null
	var request_id := _pending_request.request_id
	if continuation == null:
		_pending_request = null
		_pending_continuation = null
		return _fail(&"invalid_vm_continuation", "The pending Scenario VM continuation is unavailable.", events)
	_append_trace({"event": "resume", "requestId": request_id, "kind": String(continuation.kind)})
	var operation: ScenarioRuntimeOperationResult
	match continuation.kind:
		ScenarioVmPendingContinuation.SAFE_OPERATION:
			operation = runtime_api.resume_safe(continuation.runtime, response, _next_request_id())
		ScenarioVmPendingContinuation.CLASSIC_OPERATION:
			operation = runtime_api.resume_classic(continuation.runtime, response, _next_request_id())
		_:
			_pending_request = null
			_pending_continuation = null
			return _fail(&"unknown_interaction_continuation", "Scenario VM continuation kind is unavailable.", events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		if reward_retry_checkpoint != null and restore(reward_retry_checkpoint):
			return ScenarioVmResult.failed(operation.error_code, operation.error_message)
		_pending_request = null
		_pending_continuation = null
		return _fail(operation.error_code, operation.error_message, events)
	_pending_request = null
	_pending_continuation = null
	return _complete_pending_operation(continuation, operation, runtime_api)


func complete_debug_victory(runtime_api: RealmzRuntimeApi, events: Array[DomainEvent]) -> ScenarioVmResult:
	if _pending_request == null or _pending_request.kind != InteractionRequest.COMBAT or _pending_continuation == null or _pending_continuation.runtime == null:
		return ScenarioVmResult.failed(&"invalid_vm_continuation", "Debug victory requires the Scenario VM's active combat request.")
	var continuation := _pending_continuation.copy()
	var expected_runtime_kind := ScenarioRuntimeContinuation.SAFE_COMBAT if continuation.kind == ScenarioVmPendingContinuation.SAFE_OPERATION else ScenarioRuntimeContinuation.CLASSIC_COMBAT if continuation.kind == ScenarioVmPendingContinuation.CLASSIC_OPERATION else &""
	if continuation.runtime.kind != expected_runtime_kind:
		return ScenarioVmResult.failed(&"invalid_vm_continuation", "Debug victory cannot bypass a nested combat continuation.")
	var operation := runtime_api.complete_debug_victory(continuation.runtime, _next_request_id(), events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return ScenarioVmResult.failed(operation.error_code, operation.error_message)
	_append_trace({"event": "debug-victory", "requestId": _pending_request.request_id, "kind": String(continuation.kind)})
	_pending_request = null
	_pending_continuation = null
	return _complete_pending_operation(continuation, operation, runtime_api)


func _complete_pending_operation(continuation: ScenarioVmPendingContinuation, operation: ScenarioRuntimeOperationResult, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var events: Array[DomainEvent] = []
	events.append_array(operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		_pending_request = operation.interaction
		_pending_continuation = ScenarioVmPendingContinuation.safe(operation.continuation, continuation.frame_index, continuation.result_target) if continuation.kind == ScenarioVmPendingContinuation.SAFE_OPERATION else ScenarioVmPendingContinuation.classic(operation.continuation)
		_append_trace({"event": "yield", "requestId": operation.interaction.request_id, "kind": String(operation.interaction.kind)})
		return ScenarioVmResult.waiting(operation.interaction, events)
	if operation.state == ScenarioRuntimeOperationResult.State.SUSPENDED:
		return _suspend_operation(ScenarioVmHandoff.SAFE_OPERATION, operation, continuation.frame_index, continuation.result_target) if continuation.kind == ScenarioVmPendingContinuation.SAFE_OPERATION else _suspend_operation(ScenarioVmHandoff.CLASSIC_OPERATION, operation)
	if continuation.kind == ScenarioVmPendingContinuation.SAFE_OPERATION:
		var frame_index: int = continuation.frame_index
		if frame_index < 0 or frame_index >= _frames.size() or _frames[frame_index].kind != ScenarioFrame.ACTION:
			return _fail(&"invalid_vm_continuation", "Scenario Action continuation frame is unavailable.", events)
		if not continuation.result_target.is_empty():
			_frames[frame_index].set_local(continuation.result_target, operation.value)
	else:
		var inherited_context: ScenarioExecutionContext = _frames.back().context().for_new_program_frame() if not _frames.is_empty() else null
		var directive_result := _apply_classic_directive(operation.directive, inherited_context, runtime_api)
		if directive_result.state == ScenarioVmResult.State.FAILED:
			return _fail(directive_result.error_code, directive_result.error_message, events)
	var resumed := run(runtime_api)
	events.append_array(resumed.events)
	if resumed.state == ScenarioVmResult.State.WAITING:
		return ScenarioVmResult.waiting(resumed.interaction, events)
	if resumed.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioVmResult.suspended(resumed.handoff, events)
	if resumed.state == ScenarioVmResult.State.FAILED:
		return ScenarioVmResult.failed(resumed.error_code, resumed.error_message, events)
	return ScenarioVmResult.completed(events, resumed.outcome)


func resume_handoff(handoff: ScenarioVmHandoff, operation: ScenarioRuntimeOperationResult, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	if _halted or _frames.is_empty() or _pending_request != null:
		return ScenarioVmResult.failed(&"invalid_vm_handoff", "The suspended Scenario VM is unavailable.")
	if handoff == null or operation == null or operation.state != ScenarioRuntimeOperationResult.State.COMPLETED:
		return ScenarioVmResult.failed(&"invalid_runtime_handoff", "The Realmz runtime did not complete the suspended operation.")
	var events: Array[DomainEvent] = []
	events.append_array(operation.events)
	match handoff.kind:
		ScenarioVmHandoff.SAFE_OPERATION:
			var frame_index := handoff.frame_index
			if frame_index < 0 or frame_index >= _frames.size() or _frames[frame_index].kind != ScenarioFrame.ACTION:
				return ScenarioVmResult.failed(&"invalid_vm_handoff", "The suspended Scenario Action frame is unavailable.", events)
			var result_target := handoff.result_target
			if not result_target.is_empty():
				_frames[frame_index].set_local(result_target, operation.value)
		ScenarioVmHandoff.CLASSIC_OPERATION:
			var context: ScenarioExecutionContext = _frames.back().context()
			var directive_result := _apply_classic_directive(operation.directive, context, runtime_api)
			if directive_result.state == ScenarioVmResult.State.FAILED:
				return ScenarioVmResult.failed(directive_result.error_code, directive_result.error_message, events)
		_:
			return ScenarioVmResult.failed(&"invalid_vm_handoff", "The suspended operation kind is unavailable.", events)
	_append_trace({"event": "host-handoff-resume", "kind": String(handoff.kind)})
	var resumed := run(runtime_api)
	events.append_array(resumed.events)
	if resumed.state == ScenarioVmResult.State.WAITING:
		return ScenarioVmResult.waiting(resumed.interaction, events)
	if resumed.state == ScenarioVmResult.State.SUSPENDED:
		return ScenarioVmResult.suspended(resumed.handoff, events)
	if resumed.state == ScenarioVmResult.State.FAILED:
		return ScenarioVmResult.failed(resumed.error_code, resumed.error_message, events)
	return ScenarioVmResult.completed(events, resumed.outcome)


func snapshot() -> ScenarioVmSnapshot:
	var result := ScenarioVmSnapshot.new()
	for frame: ScenarioFrame in _frames:
		result.frames.append(ScenarioFrame.from_data(frame.to_data()))
	result.pending_request = InteractionRequest.from_data(_pending_request.to_data()) if _pending_request != null else null
	result.pending_continuation = _pending_continuation.copy() if _pending_continuation != null else null
	result.trace = _trace.duplicate(true)
	result.request_counter = _request_counter
	result.step_count = _step_count
	result.halted = _halted
	result.last_outcome = _last_outcome.duplicate(true) if _last_outcome is Array or _last_outcome is Dictionary else _last_outcome
	return result


func restore(value: Variant) -> bool:
	var saved := value as ScenarioVmSnapshot
	if saved == null or _definition == null or saved.frames.size() > CLASSIC_CALL_LIMIT + ACTION_CALL_LIMIT + 1:
		return false
	var action_depth := 0
	var classic_depth := 0
	for frame: ScenarioFrame in saved.frames:
		if frame.kind == ScenarioFrame.PROGRAM:
			var program := _definition.program_by_id(frame.definition_id)
			if program == null or frame.cursor > program.instruction_count():
				return false
			if frame.counts_as_classic_call:
				classic_depth += 1
		elif frame.kind == ScenarioFrame.ACTION:
			var action := _definition.action_by_id(frame.definition_id)
			if action == null or frame.cursor > action.program.instruction_count():
				return false
			action_depth += 1
		else:
			var context := frame.context()
			if frame.kind != ScenarioFrame.ENCOUNTER or frame.cursor not in [0, 1] or context.encounter_kind not in [&"simple", &"complex"] or context.encounter_id < 0 or frame.definition_id != "%s:%d" % [context.encounter_kind, context.encounter_id]:
				return false
			if frame.counts_as_classic_call: classic_depth += 1
	if action_depth > ACTION_CALL_LIMIT or classic_depth > CLASSIC_CALL_LIMIT:
		return false
	_frames.clear()
	for frame: ScenarioFrame in saved.frames:
		_frames.append(ScenarioFrame.from_data(frame.to_data()))
	_pending_request = InteractionRequest.from_data(saved.pending_request.to_data()) if saved.pending_request != null else null
	_pending_continuation = saved.pending_continuation.copy() if saved.pending_continuation != null else null
	_trace = saved.trace.duplicate(true)
	_request_counter = saved.request_counter
	_step_count = saved.step_count
	_halted = saved.halted
	_last_outcome = saved.last_outcome.duplicate(true) if saved.last_outcome is Array or saved.last_outcome is Dictionary else saved.last_outcome
	return true


func trace() -> Array[Dictionary]:
	return _trace.duplicate(true)


func is_active() -> bool:
	return not _halted and not _frames.is_empty()


func pending_request() -> InteractionRequest:
	return _pending_request


static func _is_reward_continuation(continuation: ScenarioVmPendingContinuation) -> bool:
	return continuation != null and continuation.runtime != null and continuation.runtime.kind == ScenarioRuntimeContinuation.CLASSIC_REWARD


static func handoff_is_valid(handoff: ScenarioVmHandoff, saved: ScenarioVmSnapshot) -> bool:
	if saved == null or saved.halted or saved.frames.is_empty() or saved.pending_request != null or saved.pending_continuation != null or handoff == null or handoff.runtime == null:
		return false
	match handoff.kind:
		ScenarioVmHandoff.CLASSIC_OPERATION:
			return saved.frames.back().kind == ScenarioFrame.PROGRAM
		ScenarioVmHandoff.SAFE_OPERATION:
			var frame_index: int = handoff.frame_index
			return frame_index >= 0 and frame_index < saved.frames.size() and saved.frames[frame_index].kind == ScenarioFrame.ACTION
	return false


func _execute_program_frame(frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	if frame.definition_id != DEBUG_PROGRAM_ID and frame.cursor == 0 and frame.context_value("_programResolved") != true:
		var original_program_id := frame.definition_id
		var resolved_program_id := runtime_api.resolve_program_id(original_program_id)
		if _definition.program_by_id(resolved_program_id) == null:
			return ScenarioVmResult.failed(&"unknown_scenario_program", "Scenario program override for '%s' references unavailable program '%s'." % [original_program_id, resolved_program_id])
		var resolved_context := frame.context()
		resolved_context.mark_program_resolved(original_program_id)
		frame.set_context(resolved_context)
		frame.definition_id = resolved_program_id
		if resolved_program_id != original_program_id:
			_append_trace({"event": "program-override", "sourceProgramId": original_program_id, "targetProgramId": resolved_program_id})
	var program := _debug_program if frame.definition_id == DEBUG_PROGRAM_ID else _definition.program_by_id(frame.definition_id)
	if program == null:
		return ScenarioVmResult.failed(&"unknown_scenario_program", "Scenario program '%s' disappeared during execution." % frame.definition_id)
	if frame.cursor >= program.instruction_count():
		_return_from_frame(null)
		return ScenarioVmResult.completed()
	var instruction: Variant = program.instruction_at(frame.cursor)
	if instruction is CallScenarioActionInstruction:
		var action_call: CallScenarioActionInstruction = instruction
		var arguments_result := _evaluate_call_arguments(action_call, frame, runtime_api)
		if not arguments_result["ok"]:
			return ScenarioVmResult.failed(&"safe_expression_failed", arguments_result["error"])
		frame.cursor += 1
		return _push_action(action_call.action_id, arguments_result["value"], action_call.result_target, _calling_context(frame, program), frame.context(), true)
	if not instruction is ClassicActionDefinition:
		return ScenarioVmResult.failed(&"unknown_scenario_instruction", "Scenario program '%s' contains an unknown instruction." % program.id)
	var action: ClassicActionDefinition = instruction
	_append_trace({"event": "execute-classic", "programId": program.id, "cursor": frame.cursor, "slot": action.slot, "rawOpcode": action.raw_opcode, "opcode": action.opcode, "id": action.operand_id})
	match action.opcode:
		39:
			var target_id := "xap:%d" % action.operand_id
			if _definition.program_by_id(target_id) == null:
				return ScenarioVmResult.failed(&"unknown_scenario_program", "Classic opcode 39 references unavailable XAP %d." % action.operand_id)
			var replacement := ScenarioFrame.new(ScenarioFrame.PROGRAM, target_id)
			replacement.counts_as_classic_call = frame.counts_as_classic_call
			var transfer_context := frame.context()
			transfer_context.mark_program_transfer(program.id)
			replacement.set_context(transfer_context)
			_frames[_frames.size() - 1] = replacement
			_append_trace({"event": "classic-transfer", "programId": target_id})
			return ScenarioVmResult.completed()
		111:
			_append_trace({"event": "classic-return", "programId": program.id})
			_return_from_frame(null)
			return ScenarioVmResult.completed()
		112:
			frame.cursor += 1
			_pop_classic_caller_below_top()
			return ScenarioVmResult.completed()
	var request_id := _next_request_id()
	var operation := runtime_api.execute_classic(action, request_id, frame.context())
	frame.cursor += 1
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return ScenarioVmResult.failed(operation.error_code, operation.error_message)
	if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
		_pending_request = operation.interaction
		_pending_continuation = ScenarioVmPendingContinuation.classic(operation.continuation)
		_append_trace({"event": "yield", "requestId": request_id, "kind": String(operation.interaction.kind)})
		return ScenarioVmResult.waiting(operation.interaction, operation.events)
	if operation.state == ScenarioRuntimeOperationResult.State.SUSPENDED:
		return _suspend_operation(ScenarioVmHandoff.CLASSIC_OPERATION, operation)
	var directive_result := _apply_classic_directive(operation.directive, frame.context(), runtime_api)
	if directive_result.state == ScenarioVmResult.State.FAILED:
		return directive_result
	return ScenarioVmResult.completed(operation.events)


func _apply_classic_directive(directive: ScenarioVmDirective, inherited_context: ScenarioExecutionContext = null, runtime_api: RealmzRuntimeApi = null) -> ScenarioVmResult:
	if directive == null:
		return ScenarioVmResult.completed()
	match directive.kind:
		ScenarioVmDirective.FINISH:
			_return_from_frame(null)
			return ScenarioVmResult.completed()
		ScenarioVmDirective.FINISH_TIMELINE:
			_frames.clear()
			_halted = true
			_last_outcome = null
			_append_trace({"event": "classic-finish-timeline"})
			return ScenarioVmResult.completed()
		ScenarioVmDirective.RESUME_AFTER_ENCOUNTER:
			return _resume_after_classic_encounter()
		ScenarioVmDirective.RESTART_CURRENT_PROGRAM:
			if _frames.is_empty() or _frames.back().kind != ScenarioFrame.PROGRAM:
				return ScenarioVmResult.failed(&"invalid_program_restart", "Classic battle restart has no issuing program frame.")
			_frames.back().cursor = 0
			_append_trace({"event": "classic-program-restart", "programId": _frames.back().definition_id})
			return ScenarioVmResult.completed()
		ScenarioVmDirective.BRANCH_XAP:
			var program_id := "xap:%d" % directive.target_id
			if _definition.program_by_id(program_id) == null:
				return ScenarioVmResult.failed(&"unknown_scenario_program", "Classic branch references unavailable XAP %d." % directive.target_id)
			var target_frame := ScenarioFrame.new(ScenarioFrame.PROGRAM, program_id)
			target_frame.set_context(ScenarioExecutionContext.empty() if inherited_context == null else inherited_context)
			if directive.gosub:
				if _classic_call_depth() >= CLASSIC_CALL_LIMIT:
					return ScenarioVmResult.failed(&"classic_gosub_limit", "Classic GOSUB stack exceeded 20 frames.")
				target_frame.counts_as_classic_call = true
				_frames.append(target_frame)
			else:
				_frames[_frames.size() - 1] = target_frame
			_append_trace({"event": "classic-branch", "programId": program_id, "gosub": directive.gosub})
			return ScenarioVmResult.completed()
		ScenarioVmDirective.BRANCH_PROGRAM:
			var program_id: String = directive.program_id
			if _definition.program_by_id(program_id) == null:
				return ScenarioVmResult.failed(&"unknown_scenario_program", "Classic branch references unavailable program '%s'." % program_id)
			var target_frame := ScenarioFrame.new(ScenarioFrame.PROGRAM, program_id)
			target_frame.counts_as_classic_call = directive.gosub
			target_frame.cursor = directive.entry_cursor
			var base_context := ScenarioExecutionContext.empty() if inherited_context == null else inherited_context
			var merged_context: ScenarioExecutionContext = base_context.merged(directive.context)
			target_frame.set_context(merged_context)
			if target_frame.counts_as_classic_call:
				if _classic_call_depth() >= CLASSIC_CALL_LIMIT:
					return ScenarioVmResult.failed(&"classic_gosub_limit", "Classic GOSUB stack exceeded 20 frames.")
				_frames.append(target_frame)
			else:
				_frames[_frames.size() - 1] = target_frame
			_append_trace({"event": "classic-branch", "programId": program_id, "gosub": target_frame.counts_as_classic_call})
			return ScenarioVmResult.completed()
		ScenarioVmDirective.ENTER_ENCOUNTER:
			if runtime_api == null or directive.encounter_kind not in [&"simple", &"complex"] or directive.target_id < 0:
				return ScenarioVmResult.failed(&"invalid_encounter_branch", "Classic encounter transition is unavailable.")
			if directive.gosub and _classic_call_depth() >= CLASSIC_CALL_LIMIT:
				return ScenarioVmResult.failed(&"classic_gosub_limit", "Classic GOSUB stack exceeded 20 frames.")
			var encounter_context := (ScenarioExecutionContext.empty() if inherited_context == null else inherited_context.copy()).merged(ScenarioExecutionContext.encounter(directive.encounter_kind, directive.target_id).set_encounter_attempt(0))
			var encounter_frame := ScenarioFrame.new(ScenarioFrame.ENCOUNTER, "%s:%d" % [directive.encounter_kind, directive.target_id])
			encounter_frame.counts_as_classic_call = directive.gosub
			encounter_frame.set_context(encounter_context)
			if directive.gosub:
				_frames.append(encounter_frame)
			else:
				_frames[_frames.size() - 1] = encounter_frame
			_append_trace({"event": "classic-encounter-branch", "encounterKind": String(directive.encounter_kind), "encounterId": directive.target_id, "gosub": directive.gosub})
			return ScenarioVmResult.completed()
		ScenarioVmDirective.BRANCH_ENCOUNTER_RESULT:
			var program_id: String = directive.program_id
			if _definition.program_by_id(program_id) == null:
				return ScenarioVmResult.failed(&"unknown_scenario_program", "Classic encounter result references unavailable program '%s'." % program_id)
			if not _frames.is_empty() and _frames.back().kind == ScenarioFrame.ENCOUNTER:
				var encounter_frame: ScenarioFrame = _frames.back()
				var encounter_context := encounter_frame.context().merged(directive.context)
				encounter_frame.set_context(encounter_context)
				encounter_frame.cursor = 0 if directive.repeat_encounter else 1
				var result_frame := ScenarioFrame.new(ScenarioFrame.PROGRAM, program_id)
				result_frame.set_context(encounter_context)
				_frames.append(result_frame)
				_append_trace({"event": "classic-encounter-repeat" if directive.repeat_encounter else "classic-encounter-result", "programId": program_id, "attempt": encounter_context.encounter_attempt})
				return ScenarioVmResult.completed()
			if not directive.repeat_encounter:
				return _apply_classic_directive(ScenarioVmDirective.branch_program(program_id, directive.gosub, directive.context), inherited_context, runtime_api)
			if _frames.is_empty() or _frames.back().kind != ScenarioFrame.PROGRAM or _frames.back().cursor < 1:
				return ScenarioVmResult.failed(&"invalid_encounter_loop", "Classic encounter repetition has no issuing program frame.")
			var source_frame: ScenarioFrame = _frames.back()
			var base_context := source_frame.context() if inherited_context == null else inherited_context.copy()
			var loop_context := base_context.merged(directive.context)
			source_frame.cursor -= 1
			source_frame.set_context(loop_context)
			var result_frame := ScenarioFrame.new(ScenarioFrame.PROGRAM, program_id)
			result_frame.set_context(loop_context)
			_frames.append(result_frame)
			_append_trace({"event": "classic-encounter-repeat", "programId": program_id, "attempt": loop_context.encounter_attempt})
			return ScenarioVmResult.completed()
		_:
			return ScenarioVmResult.failed(&"unknown_vm_directive", "Realmz Runtime API returned an unknown VM directive.")


func _execute_encounter_frame(frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var context := frame.context()
	if context.encounter_kind not in [&"simple", &"complex"] or context.encounter_id < 0 or frame.cursor not in [0, 1]:
		return ScenarioVmResult.failed(&"invalid_encounter_branch", "Scenario encounter frame has no selected destination.")
	if frame.cursor == 1:
		_return_from_frame(null)
		_append_trace({"event": "classic-encounter-exit", "programId": frame.definition_id, "encounterKind": String(context.encounter_kind), "encounterId": context.encounter_id, "returnsToSource": frame.counts_as_classic_call})
		return ScenarioVmResult.completed()
	var request_id := _next_request_id()
	var operation := runtime_api.request_classic_encounter(context.encounter_kind, context.encounter_id, request_id, context)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return ScenarioVmResult.failed(operation.error_code, operation.error_message)
	if operation.state != ScenarioRuntimeOperationResult.State.WAITING:
		return ScenarioVmResult.failed(&"invalid_encounter_branch", "Scenario encounter frame did not produce an interaction.")
	_pending_request = operation.interaction
	_pending_continuation = ScenarioVmPendingContinuation.classic(operation.continuation)
	_append_trace({"event": "yield", "requestId": request_id, "kind": String(operation.interaction.kind), "encounterKind": String(context.encounter_kind), "encounterId": context.encounter_id})
	return ScenarioVmResult.waiting(operation.interaction, operation.events)


func _resume_after_classic_encounter() -> ScenarioVmResult:
	if _frames.size() < 2:
		return ScenarioVmResult.failed(&"invalid_encounter_loop", "Classic encounter exit has no issuing program frame.")
	var encounter_context: ScenarioExecutionContext = _frames.back().context()
	for frame_index: int in range(_frames.size() - 2, -1, -1):
		var source_frame: ScenarioFrame = _frames[frame_index]
		if source_frame.kind == ScenarioFrame.ENCOUNTER:
			var source_context := source_frame.context()
			if source_context.encounter_kind != encounter_context.encounter_kind or source_context.encounter_id != encounter_context.encounter_id:
				continue
			var returns_to_source := source_frame.counts_as_classic_call
			_frames.resize(frame_index)
			if _frames.is_empty():
				_halted = true
			_append_trace({"event": "classic-encounter-exit", "programId": source_frame.definition_id, "encounterKind": String(encounter_context.encounter_kind), "encounterId": encounter_context.encounter_id, "returnsToSource": returns_to_source})
			return ScenarioVmResult.completed()
		if source_frame.kind != ScenarioFrame.PROGRAM:
			continue
		var program := _definition.program_by_id(source_frame.definition_id)
		var instruction: Variant = program.instruction_at(source_frame.cursor) if program != null else null
		if not instruction is ClassicActionDefinition or not _is_issuing_encounter(instruction, encounter_context):
			continue
		_frames.resize(frame_index + 1)
		source_frame.cursor += 1
		source_frame.set_context(source_frame.context().without_encounter())
		_append_trace({"event": "classic-encounter-exit", "programId": source_frame.definition_id, "encounterKind": String(encounter_context.encounter_kind), "encounterId": encounter_context.encounter_id})
		return ScenarioVmResult.completed()
	return ScenarioVmResult.failed(&"invalid_encounter_loop", "Classic encounter exit cannot find its issuing encounter instruction.")


static func _is_issuing_encounter(instruction: ClassicActionDefinition, context: ScenarioExecutionContext) -> bool:
	return context != null and ((context.encounter_kind == &"simple" and instruction.opcode == 4) or (context.encounter_kind == &"complex" and instruction.opcode == 5)) and instruction.operand_id == context.encounter_id


func _execute_action_frame(frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var action := _definition.action_by_id(frame.definition_id)
	if action == null:
		return ScenarioVmResult.failed(&"unknown_scenario_action", "Scenario Action '%s' disappeared during execution." % frame.definition_id)
	if frame.cursor >= action.program.instruction_count():
		if action.return_type != &"void":
			return ScenarioVmResult.failed(&"scenario_action_missing_return", "Scenario Action '%s' completed without its declared return value." % action.id)
		_return_from_frame(null)
		return ScenarioVmResult.completed()
	var instruction := action.program.instruction_at(frame.cursor)
	_append_trace({"event": "execute-action", "actionId": action.id, "cursor": frame.cursor, "instructionKind": instruction.kind})
	match instruction.kind:
		SafeInstructionDefinition.Kind.OPERATION:
			var arguments_result := _evaluate_safe_arguments(instruction, frame, runtime_api)
			if not arguments_result["ok"]:
				return ScenarioVmResult.failed(&"safe_expression_failed", arguments_result["error"])
			var request_id := _next_request_id()
			var operation := runtime_api.execute_safe(instruction.capability, arguments_result["value"], request_id)
			frame.cursor += 1
			if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
				return ScenarioVmResult.failed(operation.error_code, operation.error_message)
			if operation.state == ScenarioRuntimeOperationResult.State.WAITING:
				_pending_request = operation.interaction
				_pending_continuation = ScenarioVmPendingContinuation.safe(operation.continuation, _frames.size() - 1, instruction.result_target)
				_append_trace({"event": "yield", "requestId": request_id, "kind": String(operation.interaction.kind), "actionId": action.id})
				return ScenarioVmResult.waiting(operation.interaction, operation.events)
			if operation.state == ScenarioRuntimeOperationResult.State.SUSPENDED:
				return _suspend_operation(ScenarioVmHandoff.SAFE_OPERATION, operation, _frames.size() - 1, instruction.result_target)
			if not instruction.result_target.is_empty():
				frame.set_local(instruction.result_target, operation.value)
			return ScenarioVmResult.completed(operation.events)
		SafeInstructionDefinition.Kind.CALL_ACTION:
			var arguments_result := _evaluate_safe_arguments(instruction, frame, runtime_api)
			if not arguments_result["ok"]:
				return ScenarioVmResult.failed(&"safe_expression_failed", arguments_result["error"])
			frame.cursor += 1
			return _push_action(instruction.action_id, arguments_result["value"], instruction.result_target, StringName(frame.context_value("callingContext")), frame.context(), false)
		SafeInstructionDefinition.Kind.SET_VALUE:
			var evaluated := _evaluate(instruction.value, frame, runtime_api)
			if not evaluated["ok"]:
				return ScenarioVmResult.failed(&"safe_expression_failed", evaluated["error"])
			if instruction.scope == &"local":
				frame.set_local(instruction.name, evaluated["value"])
			else:
				var state_scope := instruction.state_scope if not instruction.state_scope.is_empty() else "campaign"
				var owner_id := instruction.owner_id if not instruction.owner_id.is_empty() else frame.definition_id
				if not runtime_api.write_action_state(state_scope, owner_id, instruction.name, evaluated["value"]):
					return ScenarioVmResult.failed(&"scenario_state_limit", "Scenario Action state rejected an unsafe or oversized value.")
			frame.cursor += 1
			return ScenarioVmResult.completed()
		SafeInstructionDefinition.Kind.JUMP_IF_FALSE:
			var evaluated := _evaluate(instruction.condition, frame, runtime_api)
			if not evaluated["ok"] or not evaluated["value"] is bool:
				return ScenarioVmResult.failed(&"safe_expression_failed", evaluated.get("error", "Safe condition did not evaluate to bool."))
			frame.cursor = frame.cursor + 1 if evaluated["value"] else instruction.target
			return ScenarioVmResult.completed()
		SafeInstructionDefinition.Kind.JUMP:
			frame.cursor = instruction.target
			return ScenarioVmResult.completed()
		SafeInstructionDefinition.Kind.BEGIN_FOR_EACH:
			return _begin_for_each(frame, instruction, runtime_api)
		SafeInstructionDefinition.Kind.NEXT_FOR_EACH:
			return _next_for_each(frame, instruction)
		SafeInstructionDefinition.Kind.RETURN:
			var return_value: Variant = null
			if instruction.value != null:
				var evaluated := _evaluate(instruction.value, frame, runtime_api)
				if not evaluated["ok"]:
					return ScenarioVmResult.failed(&"safe_expression_failed", evaluated["error"])
				return_value = evaluated["value"]
			if not _value_matches_type(return_value, action.return_type):
				return ScenarioVmResult.failed(&"scenario_action_return_type", "Scenario Action '%s' returned a value outside its declared type." % action.id)
			_return_from_frame(return_value)
			return ScenarioVmResult.completed()
		SafeInstructionDefinition.Kind.HALT:
			_frames.clear()
			_halted = true
			_last_outcome = instruction.outcome
			return ScenarioVmResult.completed([], instruction.outcome)
	return ScenarioVmResult.failed(&"unknown_scenario_instruction", "Scenario Action contains an unavailable instruction kind.")


func _suspend_operation(kind: StringName, operation: ScenarioRuntimeOperationResult, frame_index: int = -1, result_target: String = "", preceding_events: Array[DomainEvent] = []) -> ScenarioVmResult:
	if operation.handoff == null:
		return ScenarioVmResult.failed(&"invalid_runtime_handoff", "The Realmz runtime suspended without a typed host handoff.", preceding_events)
	var handoff := ScenarioVmHandoff.safe(operation.handoff, frame_index, result_target) if kind == ScenarioVmHandoff.SAFE_OPERATION else ScenarioVmHandoff.classic(operation.handoff)
	_append_trace({"event": "host-handoff", "kind": String(kind), "runtimeKind": String(operation.handoff.kind)})
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append_array(operation.events)
	return ScenarioVmResult.suspended(handoff, events)


func _push_action(action_id: String, arguments: Dictionary, return_target: String, calling_context: StringName, inherited_context: ScenarioExecutionContext, require_public: bool) -> ScenarioVmResult:
	var action := _definition.action_by_id(action_id)
	if action == null:
		return ScenarioVmResult.failed(&"unknown_scenario_action", "Scenario Action '%s' is unavailable." % action_id)
	if require_public and action.visibility != &"public":
		return ScenarioVmResult.failed(&"private_scenario_action", "Private Scenario Action '%s' cannot be called from an authored timeline." % action_id)
	if calling_context == &"" or not action.allowed_contexts().has(calling_context):
		return ScenarioVmResult.failed(&"scenario_action_context", "Scenario Action '%s' is not allowed in context '%s'." % [action_id, calling_context])
	var parameters := action.parameters()
	if arguments.size() != parameters.size():
		return ScenarioVmResult.failed(&"scenario_action_arguments", "Scenario Action '%s' received the wrong argument set." % action_id)
	for parameter: ScenarioActionParameter in parameters:
		if not arguments.has(parameter.name) or not _value_matches_type(arguments[parameter.name], parameter.value_type, parameter.max_length):
			return ScenarioVmResult.failed(&"scenario_action_arguments", "Scenario Action '%s' received an invalid '%s' argument." % [action_id, parameter.name])
	if _action_call_depth() >= ACTION_CALL_LIMIT:
		return ScenarioVmResult.failed(&"scenario_action_call_limit", "Scenario Action call stack exceeded 32 frames.")
	var frame := ScenarioFrame.new(ScenarioFrame.ACTION, action_id)
	frame.return_target = return_target
	frame.set_parameters(arguments)
	var context: ScenarioExecutionContext = ScenarioExecutionContext.empty() if inherited_context == null else inherited_context.copy()
	context.calling_context = calling_context
	frame.set_context(context)
	_frames.append(frame)
	_append_trace({"event": "call-action", "actionId": action_id, "depth": _action_call_depth()})
	return ScenarioVmResult.completed()


func _return_from_frame(value: Variant) -> void:
	if _frames.is_empty():
		return
	var finished: ScenarioFrame = _frames.pop_back()
	_append_trace({"event": "return", "definitionId": finished.definition_id, "kind": String(finished.kind)})
	if _frames.is_empty():
		_halted = true
		_last_outcome = value
		return
	if finished.kind == ScenarioFrame.ACTION and not finished.return_target.is_empty():
		_frames.back().set_local(finished.return_target, value)


func _begin_for_each(frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var evaluated := _evaluate(instruction.collection, frame, runtime_api)
	if not evaluated["ok"] or not evaluated["value"] is Array:
		return ScenarioVmResult.failed(&"safe_expression_failed", evaluated.get("error", "For-each input is not an array."))
	var values: Array = evaluated["value"]
	if values.size() > 256:
		return ScenarioVmResult.failed(&"safe_array_limit", "For-each input exceeds 256 entries.")
	if values.is_empty():
		frame.cursor = instruction.target
		return ScenarioVmResult.completed()
	frame.push_iterator({"beginTarget": frame.cursor, "index": 0, "values": values.duplicate(true), "itemName": instruction.item_name, "hadPrevious": frame.has_local(instruction.item_name), "previous": frame.local(instruction.item_name)})
	frame.set_local(instruction.item_name, values[0])
	frame.cursor += 1
	return ScenarioVmResult.completed()


func _next_for_each(frame: ScenarioFrame, instruction: SafeInstructionDefinition) -> ScenarioVmResult:
	if not frame.has_iterator():
		return ScenarioVmResult.failed(&"invalid_safe_program", "For-each continuation has no active iterator.")
	var iterator: Dictionary = frame.current_iterator()
	if iterator.get("beginTarget") != instruction.target:
		return ScenarioVmResult.failed(&"invalid_safe_program", "For-each continuation target does not match its iterator.")
	iterator["index"] += 1
	if iterator["index"] < iterator["values"].size():
		frame.set_local(iterator["itemName"], iterator["values"][iterator["index"]])
		frame.update_current_iterator(iterator)
		frame.cursor = instruction.target + 1
		return ScenarioVmResult.completed()
	frame.pop_iterator()
	if iterator["hadPrevious"]:
		frame.set_local(iterator["itemName"], iterator["previous"])
	else:
		frame.erase_local(iterator["itemName"])
	frame.cursor += 1
	return ScenarioVmResult.completed()


func _evaluate_call_arguments(action_call: CallScenarioActionInstruction, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var result: Dictionary = {}
	for name: String in action_call.argument_names():
		var evaluated := _evaluate(action_call.argument(name), frame, runtime_api)
		if not evaluated["ok"]:
			return evaluated
		result[name] = evaluated["value"]
	return {"ok": true, "value": result}


func _evaluate_safe_arguments(instruction: SafeInstructionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var result: Dictionary = {}
	for name: String in instruction.argument_names():
		var evaluated := _evaluate(instruction.argument(name), frame, runtime_api)
		if not evaluated["ok"]:
			return evaluated
		result[name] = evaluated["value"]
	return {"ok": true, "value": result}


func _evaluate(expression: SafeExpressionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	if expression == null:
		return {"ok": false, "error": "Safe expression is missing."}
	match expression.kind:
		SafeExpressionDefinition.Kind.LITERAL:
			return {"ok": true, "value": expression.value}
		SafeExpressionDefinition.Kind.VARIABLE:
			match expression.scope:
				&"parameter":
					return {"ok": true, "value": frame.parameter(expression.name)}
				&"local":
					if not frame.has_local(expression.name):
						return {"ok": false, "error": "Safe local '%s' is undefined." % expression.name}
					return {"ok": true, "value": frame.local(expression.name)}
				&"context":
					return {"ok": true, "value": frame.context_value(expression.name)}
				&"persistent":
					var state_scope := expression.state_scope if not expression.state_scope.is_empty() else "campaign"
					var owner_id := expression.owner_id if not expression.owner_id.is_empty() else frame.definition_id
					return {"ok": true, "value": runtime_api.read_action_state(state_scope, owner_id, expression.name)}
		SafeExpressionDefinition.Kind.ARRAY:
			var values: Array = []
			for child: SafeExpressionDefinition in expression.values():
				var evaluated := _evaluate(child, frame, runtime_api)
				if not evaluated["ok"]:
					return evaluated
				values.append(evaluated["value"])
			return {"ok": true, "value": values}
		SafeExpressionDefinition.Kind.RECORD:
			var fields: Dictionary = {}
			for field_name: String in expression.field_names():
				var evaluated := _evaluate(expression.field(field_name), frame, runtime_api)
				if not evaluated["ok"]:
					return evaluated
				fields[field_name] = evaluated["value"]
			return {"ok": true, "value": fields}
		SafeExpressionDefinition.Kind.UNARY:
			var operand := _evaluate(expression.operand, frame, runtime_api)
			if not operand["ok"]:
				return operand
			if expression.operator == &"not" and operand["value"] is bool:
				return {"ok": true, "value": not operand["value"]}
			if expression.operator == &"-" and _is_number(operand["value"]):
				return {"ok": true, "value": -operand["value"]}
			return {"ok": false, "error": "Safe unary operator '%s' received an invalid operand." % expression.operator}
		SafeExpressionDefinition.Kind.BINARY:
			var left_result := _evaluate(expression.left, frame, runtime_api)
			var right_result := _evaluate(expression.right, frame, runtime_api)
			if not left_result["ok"]:
				return left_result
			if not right_result["ok"]:
				return right_result
			return _evaluate_binary(expression.operator, left_result["value"], right_result["value"])
		SafeExpressionDefinition.Kind.MEMBER:
			var object_result := _evaluate(expression.object, frame, runtime_api)
			if not object_result["ok"]:
				return object_result
			if not object_result["value"] is Dictionary or not object_result["value"].has(expression.member):
				return {"ok": false, "error": "Safe member '%s' is unavailable." % expression.member}
			return {"ok": true, "value": object_result["value"][expression.member]}
		SafeExpressionDefinition.Kind.COLLECTION:
			return _evaluate_collection(expression, frame, runtime_api)
	return {"ok": false, "error": "Safe expression kind is unavailable."}


func _evaluate_binary(operator: StringName, left: Variant, right: Variant) -> Dictionary:
	match operator:
		&"==": return {"ok": true, "value": left == right}
		&"!=": return {"ok": true, "value": left != right}
		&"and", &"or":
			if left is bool and right is bool:
				return {"ok": true, "value": left and right if operator == &"and" else left or right}
		&"+":
			if _is_number(left) and _is_number(right) or left is String and right is String:
				return {"ok": true, "value": left + right}
		&"-", &"*", &"/":
			if _is_number(left) and _is_number(right) and not (operator == &"/" and right == 0):
				match operator:
					&"-": return {"ok": true, "value": left - right}
					&"*": return {"ok": true, "value": left * right}
					&"/": return {"ok": true, "value": left / right}
		&"<", &"<=", &">", &">=":
			if _is_number(left) and _is_number(right):
				match operator:
					&"<": return {"ok": true, "value": left < right}
					&"<=": return {"ok": true, "value": left <= right}
					&">": return {"ok": true, "value": left > right}
					&">=": return {"ok": true, "value": left >= right}
	return {"ok": false, "error": "Safe binary operator '%s' received incompatible values." % operator}


func _evaluate_collection(expression: SafeExpressionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> Dictionary:
	var collection_result := _evaluate(expression.collection, frame, runtime_api)
	if not collection_result["ok"] or not collection_result["value"] is Array:
		return {"ok": false, "error": "Safe collection expression input is not an array."}
	var values: Array = collection_result["value"]
	if values.size() > 256:
		return {"ok": false, "error": "Safe collection exceeds 256 entries."}
	if expression.operator == &"count":
		return {"ok": true, "value": values.size()}
	if expression.operator == &"first" and expression.predicate == null:
		return {"ok": true, "value": values[0] if not values.is_empty() else null}
	var had_previous := frame.has_local(expression.item_name)
	var previous: Variant = frame.local(expression.item_name)
	var matches: Array = []
	for value: Variant in values:
		frame.set_local(expression.item_name, value)
		var predicate := _evaluate(expression.predicate, frame, runtime_api)
		if not predicate["ok"] or not predicate["value"] is bool:
			_restore_local(frame, expression.item_name, had_previous, previous)
			return {"ok": false, "error": "Safe collection predicate did not evaluate to bool."}
		matches.append(predicate["value"])
	_restore_local(frame, expression.item_name, had_previous, previous)
	match expression.operator:
		&"any": return {"ok": true, "value": matches.has(true)}
		&"all": return {"ok": true, "value": not matches.has(false)}
		&"first":
			for index: int in range(matches.size()):
				if matches[index]:
					return {"ok": true, "value": values[index]}
			return {"ok": true, "value": null}
	return {"ok": false, "error": "Safe collection operation '%s' is unavailable." % expression.operator}


func _restore_local(frame: ScenarioFrame, name: String, had_previous: bool, previous: Variant) -> void:
	if had_previous:
		frame.set_local(name, previous)
	else:
		frame.erase_local(name)


func _pop_classic_caller_below_top() -> void:
	for index: int in range(_frames.size() - 2, -1, -1):
		if _frames[index].kind == ScenarioFrame.PROGRAM and _frames[index + 1].counts_as_classic_call:
			_frames.remove_at(index)
			_frames[index].counts_as_classic_call = false
			return


func _action_call_depth() -> int:
	var count := 0
	for frame: ScenarioFrame in _frames:
		if frame.kind == ScenarioFrame.ACTION:
			count += 1
	return count


func _classic_call_depth() -> int:
	var count := 0
	for frame: ScenarioFrame in _frames:
		if frame.counts_as_classic_call:
			count += 1
	return count


func _calling_context(frame: ScenarioFrame, program: ScenarioProgramDefinition) -> StringName:
	var explicit: Variant = frame.context_value("callingContext")
	if explicit is String and not explicit.is_empty():
		return StringName(explicit)
	match program.owner_kind:
		&"simple-encounter-result", &"complex-encounter-result":
			return &"encounter"
		&"trigger", &"extra-action-point":
			return &"action"
	return &""


static func _value_matches_type(value: Variant, value_type: StringName, max_length: int = -1) -> bool:
	match value_type:
		&"void":
			return value == null
		&"bool":
			return value is bool
		&"int":
			return value is int
		&"float":
			return value is int or value is float
		&"string":
			return value is String and (max_length < 0 or value.length() <= max_length)
		&"bool-array", &"int-array", &"float-array", &"string-array", &"character-snapshot-array":
			if not value is Array or value.size() > 256 or (max_length >= 0 and value.size() > max_length):
				return false
			var element_type := StringName(String(value_type).trim_suffix("-array"))
			for entry: Variant in value:
				if not _value_matches_type(entry, element_type):
					return false
			return true
		&"location-snapshot", &"time-snapshot", &"wealth-snapshot", &"character-snapshot", &"combat-snapshot", &"action-outcome", &"encounter-outcome", &"effect-outcome", &"spell-validation-outcome", &"spell-cast-outcome", &"spell-effect-outcome", &"spell-tick-outcome", &"spell-expiration-outcome", &"item-outcome", &"monster-decision", &"rule-modifier":
			return value is Dictionary
	return false


func _next_request_id() -> String:
	_request_counter += 1
	return "scenario:%d" % _request_counter


func _append_trace(entry: Dictionary) -> void:
	if _trace.size() < TRACE_LIMIT:
		_trace.append(entry.duplicate(true))


func _fail(code: StringName, message: String, events: Array[DomainEvent]) -> ScenarioVmResult:
	_frames.clear()
	_pending_request = null
	_pending_continuation = null
	_halted = true
	_append_trace({"event": "error", "code": String(code), "message": message})
	return ScenarioVmResult.failed(code, message, events)


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
