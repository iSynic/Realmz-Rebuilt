## Defines the scenario VM contract for scenario execution.

class_name ScenarioVm
extends RefCounted

## Runs serializable Classic programs and Safe Scenario Actions through the typed runtime API.


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
	var resolution_failure := _resolve_program_frame(frame, runtime_api)
	if resolution_failure != null:
		return resolution_failure
	var program := _debug_program if frame.definition_id == DEBUG_PROGRAM_ID else _definition.program_by_id(frame.definition_id)
	if program == null:
		return ScenarioVmResult.failed(&"unknown_scenario_program", "Scenario program '%s' disappeared during execution." % frame.definition_id)
	if frame.cursor >= program.instruction_count():
		_return_from_frame(null)
		return ScenarioVmResult.completed()
	return _execute_program_instruction(frame, program, program.instruction_at(frame.cursor), runtime_api)


func _resolve_program_frame(frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
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
	return null


func _execute_program_instruction(frame: ScenarioFrame, program: ScenarioProgramDefinition, instruction: Variant, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	if instruction is CallScenarioActionInstruction:
		var action_call: CallScenarioActionInstruction = instruction
		var arguments_result := SafeExpressionEvaluator.evaluate_call_arguments(action_call, frame, runtime_api)
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
	var transition := ScenarioClassicControlFlow.apply(directive, _definition, _frames, inherited_context, runtime_api != null)
	if transition.is_failed():
		return ScenarioVmResult.failed(transition.error_code, transition.error_message)
	for entry: Dictionary in transition.trace_entries:
		_append_trace(entry)
	match transition.action:
		ScenarioDirectiveTransition.Action.RETURN_FRAME:
			_return_from_frame(null)
		ScenarioDirectiveTransition.Action.FINISH_TIMELINE:
			_frames.clear()
			_halted = true
			_last_outcome = null
		ScenarioDirectiveTransition.Action.HALT:
			_halted = true
	return ScenarioVmResult.completed()


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
			return _execute_action_operation(action, frame, instruction, runtime_api)
		SafeInstructionDefinition.Kind.CALL_ACTION:
			return _execute_action_call(frame, instruction, runtime_api)
		SafeInstructionDefinition.Kind.SET_VALUE:
			return _execute_action_set(frame, instruction, runtime_api)
		SafeInstructionDefinition.Kind.JUMP_IF_FALSE:
			return _execute_action_condition(frame, instruction, runtime_api)
		SafeInstructionDefinition.Kind.JUMP:
			frame.cursor = instruction.target
			return ScenarioVmResult.completed()
		SafeInstructionDefinition.Kind.BEGIN_FOR_EACH:
			return _begin_for_each(frame, instruction, runtime_api)
		SafeInstructionDefinition.Kind.NEXT_FOR_EACH:
			return _next_for_each(frame, instruction)
		SafeInstructionDefinition.Kind.RETURN:
			return _execute_action_return(action, instruction, frame, runtime_api)
		SafeInstructionDefinition.Kind.HALT:
			_frames.clear()
			_halted = true
			_last_outcome = instruction.outcome
			return ScenarioVmResult.completed([], instruction.outcome)
	return ScenarioVmResult.failed(&"unknown_scenario_instruction", "Scenario Action contains an unavailable instruction kind.")


func _execute_action_operation(action: ScenarioActionDefinition, frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var arguments_result := SafeExpressionEvaluator.evaluate_instruction_arguments(instruction, frame, runtime_api)
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


func _execute_action_call(frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var arguments_result := SafeExpressionEvaluator.evaluate_instruction_arguments(instruction, frame, runtime_api)
	if not arguments_result["ok"]:
		return ScenarioVmResult.failed(&"safe_expression_failed", arguments_result["error"])
	frame.cursor += 1
	return _push_action(instruction.action_id, arguments_result["value"], instruction.result_target, StringName(frame.context_value("callingContext")), frame.context(), false)


func _execute_action_set(frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var evaluated := SafeExpressionEvaluator.evaluate(instruction.value, frame, runtime_api)
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


func _execute_action_condition(frame: ScenarioFrame, instruction: SafeInstructionDefinition, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var evaluated := SafeExpressionEvaluator.evaluate(instruction.condition, frame, runtime_api)
	if not evaluated["ok"] or not evaluated["value"] is bool:
		return ScenarioVmResult.failed(&"safe_expression_failed", evaluated.get("error", "Safe condition did not evaluate to bool."))
	frame.cursor = frame.cursor + 1 if evaluated["value"] else instruction.target
	return ScenarioVmResult.completed()


func _execute_action_return(action: ScenarioActionDefinition, instruction: SafeInstructionDefinition, frame: ScenarioFrame, runtime_api: RealmzRuntimeApi) -> ScenarioVmResult:
	var return_value: Variant = null
	if instruction.value != null:
		var evaluated := SafeExpressionEvaluator.evaluate(instruction.value, frame, runtime_api)
		if not evaluated["ok"]:
			return ScenarioVmResult.failed(&"safe_expression_failed", evaluated["error"])
		return_value = evaluated["value"]
	if not _value_matches_type(return_value, action.return_type):
		return ScenarioVmResult.failed(&"scenario_action_return_type", "Scenario Action '%s' returned a value outside its declared type." % action.id)
	_return_from_frame(return_value)
	return ScenarioVmResult.completed()


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
	var evaluated := SafeExpressionEvaluator.evaluate(instruction.collection, frame, runtime_api)
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
	return SafeExpressionEvaluator.value_matches_type(value, value_type, max_length)


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
