## Converts admitted legacy VM wire records once, before assigning live execution.
class_name ScenarioLegacyExecutionCodec
extends RefCounted


static func convert(saved: ScenarioVmSnapshot, definition: ScenarioDefinition, depth: int = 0) -> ScenarioExecutionState:
	if depth > 32 or not ScenarioVmRestoreRules.frames_are_valid(definition, saved, 20, 32): return null
	var state := ScenarioExecutionState.new()
	state.classic.macro_monster_index = -1
	state.request_counter = saved.request_counter
	state.trace = saved.trace.duplicate(true)
	state.last_outcome = ScenarioVmSnapshot.detached(saved.last_outcome)
	state.halted = saved.halted
	state.completion.header_suppressed = saved.secondary_door or saved.returned_early
	state.completion.recheck_suppressed = saved.no_second_door
	if saved.returned_early: state.completion.exit_path = ScenarioNativeCompletion.Exit.NATIVE_RETURN
	if saved.frames.is_empty():
		return state if saved.halted and saved.pending_request == null else null
	if saved.frames[0].kind == ScenarioFrame.ACTION:
		var safe := safe_root_state(state, saved, definition)
		return null if safe == null else ScenarioLegacyCallCodec.normalize(safe, definition, depth)
	var invocation := ScenarioClassicInvocationRecord.new()
	invocation.mode = ScenarioClassicInvocationRecord.Mode.MODE_ONE if saved.native_context != null else ScenarioClassicInvocationRecord.Mode.PLACED
	invocation.context = saved.native_context.copy() if saved.native_context != null else saved.frames[0].context()
	if invocation.context.calling_context in [&"battle-macro", &"monster-death-macro"]: invocation.mode = ScenarioClassicInvocationRecord.Mode.MACRO
	if invocation.mode == ScenarioClassicInvocationRecord.Mode.PLACED: invocation.placed_trigger_id = invocation.context.trigger_id
	invocation.secondary_door = saved.secondary_door
	invocation.no_second_door = saved.no_second_door
	invocation.returned_early = saved.returned_early
	invocation.phase = ScenarioClassicInvocationRecord.Phase.CODE if saved.native_invocation_begun or invocation.mode != ScenarioClassicInvocationRecord.Mode.MODE_ONE else ScenarioClassicInvocationRecord.Phase.ENTRY
	var root := state.append_record(ScenarioExecutionRecord.Kind.CLASSIC)
	root.classic = invocation
	var restored := read_frames(state, saved, definition, root)
	return null if restored == null else ScenarioLegacyCallCodec.normalize(restored, definition, depth)


static func read_frames(state: ScenarioExecutionState, saved: ScenarioVmSnapshot, definition: ScenarioDefinition, root: ScenarioExecutionRecord) -> ScenarioExecutionState:
	var invocation := root.classic
	var legacy_owners: Dictionary[int, int] = {}
	for index: int in saved.frames.size():
		var frame := saved.frames[index]
		if frame.kind == ScenarioFrame.ACTION:
			var safe := safe_record(frame, definition, saved.legacy_values)
			if safe == null: return null
			safe.invocation_owner_id = root.id
			var record := state.append_record(ScenarioExecutionRecord.Kind.SAFE)
			record.safe = safe
			legacy_owners[index] = record.id
			continue
		legacy_owners[index] = root.id
		if frame.kind == ScenarioFrame.ENCOUNTER:
			var context := frame.context()
			state.classic.encounter_kind = context.encounter_kind
			state.classic.encounter_id = context.encounter_id
			state.classic.encounter_attempt = maxi(0, context.encounter_attempt)
			state.classic.repeat_encounter = frame.cursor == 0
			invocation.phase = ScenarioClassicInvocationRecord.Phase.ENCOUNTER if frame.cursor == 0 else ScenarioClassicInvocationRecord.Phase.COMPLETE
			continue
		var code := program_state(frame)
		var program := definition.program_by_id(frame.definition_id)
		if index + 1 < saved.frames.size() and saved.frames[index + 1].counts_as_classic_call:
			state.classic.returns.append(return_record(frame, code, program))
		if index + 1 < saved.frames.size() and _is_rewound_encounter(frame, program):
			invocation.encounter_exit = return_record(frame, code, program)
			invocation.encounter_exit.cursor += 1
			invocation.encounter_exit.native_slot = ScenarioProgramPosition.slot_for_cursor(program, frame.cursor + 1)
		state.classic.code = code
		invocation.position_program_id = frame.definition_id
		invocation.cursor = frame.cursor
		invocation.native_slot = ScenarioProgramPosition.slot_for_cursor(program, frame.cursor)
		invocation.phase = ScenarioClassicInvocationRecord.Phase.CODE
		if code.context.encounter_kind != &"":
			state.classic.encounter_kind = code.context.encounter_kind
			state.classic.encounter_id = code.context.encounter_id
			state.classic.encounter_attempt = maxi(0, code.context.encounter_attempt)
	state.classic.gosub = not state.classic.returns.is_empty()
	if saved.pending_continuation != null:
		if not add_pending(state, saved, legacy_owners, definition): return null
	return state


static func safe_root_state(state: ScenarioExecutionState, saved: ScenarioVmSnapshot, definition: ScenarioDefinition) -> ScenarioExecutionState:
	var owners: Dictionary[int, int] = {}
	for index: int in saved.frames.size():
		var frame := saved.frames[index]
		if frame.kind != ScenarioFrame.ACTION: return null
		var body := safe_record(frame, definition, saved.legacy_values)
		if body == null: return null
		var record := state.append_record(ScenarioExecutionRecord.Kind.SAFE)
		record.safe = body
		owners[index] = record.id
	if saved.pending_continuation != null and not add_pending(state, saved, owners, definition): return null
	return state


static func add_pending(state: ScenarioExecutionState, saved: ScenarioVmSnapshot, owners: Dictionary[int, int], definition: ScenarioDefinition) -> bool:
	var pending := saved.pending_continuation
	var call := ScenarioOperationExecutionRecord.new()
	call.continuation = pending.runtime.copy()
	if pending.kind == ScenarioVmPendingContinuation.SAFE_OPERATION:
		if owners.get(pending.frame_index, 0) != state.records.back().id or state.records.back().kind != ScenarioExecutionRecord.Kind.SAFE: return false
		call.return_kind = ScenarioOperationExecutionRecord.ReturnKind.SAFE
		call.result_target = pending.result_target
	elif pending.kind != ScenarioVmPendingContinuation.CLASSIC_OPERATION:
		return false
	else:
		if state.records.back().kind != ScenarioExecutionRecord.Kind.CLASSIC: return false
		var frame: ScenarioFrame = saved.frames.back()
		if frame.kind == ScenarioFrame.PROGRAM and frame.cursor > 0:
			var program := definition.program_by_id(frame.definition_id)
			var instruction: Variant = program.instruction_at(frame.cursor - 1)
			if instruction is ClassicActionDefinition:
				var action: ClassicActionDefinition = instruction
				call.instruction_program_id = program.id
				call.instruction_cursor = frame.cursor - 1
				if action.raw_opcode < 0 and action.raw_opcode not in [-14, -23]: state.classic.gosub = true
	var record := state.append_record(ScenarioExecutionRecord.Kind.OPERATION)
	record.operation = call
	state.pending_request = InteractionRequest.from_data(saved.pending_request.to_data())
	state.pending_owner_id = record.id
	return true


static func program_state(frame: ScenarioFrame) -> ScenarioClassicProgramState:
	var result := ScenarioClassicProgramState.new()
	result.program_id = frame.definition_id
	result.context = frame.context()
	var values := frame.to_data(false)
	var parameters: Dictionary = values["parameters"]
	var locals: Dictionary = values["locals"]
	if not parameters.is_empty() or not locals.is_empty():
		result.timeline_values = ScenarioExpressionScope.new(frame.definition_id)
		result.timeline_values.context = result.context.copy()
		result.timeline_values.parameters = parameters.duplicate(true)
		result.timeline_values.locals = locals.duplicate(true)
	return result


static func return_record(frame: ScenarioFrame, code: ScenarioClassicProgramState, program: ScenarioProgramDefinition) -> ScenarioClassicReturnRecord:
	var result := ScenarioClassicReturnRecord.new()
	result.code = code.copy()
	result.cursor = frame.cursor
	result.native_slot = ScenarioProgramPosition.slot_for_cursor(program, frame.cursor)
	result.destination = frame.native_return_destination
	result.destination_state = ScenarioClassicReturnRecord.DestinationState.KNOWN if result.destination != null else ScenarioClassicReturnRecord.DestinationState.UNAVAILABLE
	return result


static func safe_record(frame: ScenarioFrame, definition: ScenarioDefinition, legacy_values: bool) -> ScenarioSafeExecutionRecord:
	var detached := ScenarioFrame.from_data(frame.to_data())
	if legacy_values: detached.coerce_declared_parameters(definition.action_by_id(frame.definition_id))
	var values := detached.to_data(false)
	var result := ScenarioSafeExecutionRecord.new()
	result.scope = ScenarioExpressionScope.new(frame.definition_id)
	result.scope.context = frame.context()
	result.scope.parameters = values["parameters"]
	result.scope.locals = values["locals"]
	result.cursor = frame.cursor
	result.return_target = frame.return_target
	var iterators: Array = values["iterators"]
	for entry: Variant in iterators:
		if not entry is Dictionary: return null
		var iterator: Dictionary = entry
		if not ScenarioExecutionWire.fields(iterator, ["beginTarget", "index", "values", "itemName", "hadPrevious", "previous"]): return null
		iterator["values"] = ScenarioValueCodec.encode(iterator["values"], true)
		iterator["previous"] = ScenarioValueCodec.encode(iterator["previous"], true)
		var restored := ScenarioSafeIterator.from_data(iterator)
		if restored == null: return null
		result.iterators.append(restored)
	return result


static func _is_rewound_encounter(frame: ScenarioFrame, program: ScenarioProgramDefinition) -> bool:
	var instruction: Variant = program.instruction_at(frame.cursor) if frame.cursor < program.instruction_count() else null
	return instruction is ClassicActionDefinition and instruction.opcode in [4, 5]
