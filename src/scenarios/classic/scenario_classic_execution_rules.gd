## Applies Castle's native record transitions without scheduling another executor.
class_name ScenarioClassicExecutionRules
extends RefCounted

const PUSH_OPCODES: Array[int] = [3, 21, 31, 40, 46, 55, 56, 64, 67, 72, 75, 76, 77, 78, 81, 85, 86, 87]
enum ExitPath { NATURAL, KEEP_CODES }


static func prepare_action(shared: ScenarioClassicExecutionState, action: ClassicActionDefinition) -> ClassicActionDefinition:
	if action.raw_opcode < 0 and action.raw_opcode not in [-14, -23]:
		shared.gosub = true
	elif shared.returns.is_empty():
		shared.gosub = false
	# newland's forcebranch path and direct encounters do not push. Mode-ten
	# battle revival retains its separately documented nested-helper correction.
	var effective := ClassicActionDefinition.new(action.slot, action.raw_opcode, action.opcode, action.operand_id, shared.gosub if action.opcode in PUSH_OPCODES else action.gosub if action.opcode == 2 else false, action.extra_code)
	effective.extra_code_fault = action.extra_code_fault
	effective.native_extra_code_reference = action.native_extra_code_reference
	return effective


static func capture(shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord) -> ScenarioClassicReturnRecord:
	var saved := ScenarioClassicReturnRecord.new()
	saved.code = shared.code.copy()
	saved.cursor = invocation.cursor
	saved.native_slot = invocation.native_slot
	if not shared.header.map_id.is_empty():
		saved.destination = TriggerDestinationDefinition.new(shared.header.map_id, shared.header.coordinate)
		saved.destination_state = ScenarioClassicReturnRecord.DestinationState.KNOWN
	return saved


static func restore_record(shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord, saved: ScenarioClassicReturnRecord) -> void:
	shared.code = saved.code.copy()
	invocation.position_program_id = shared.code.program_id
	invocation.position_kind = shared.code.kind
	invocation.cursor = saved.cursor
	invocation.native_slot = saved.native_slot
	invocation.phase = ScenarioClassicInvocationRecord.Phase.CODE
	if saved.destination != null:
		# stack.c restores infodoor, independently of the global doornum.
		shared.header.map_id = saved.destination.map_id
		shared.header.coordinate = saved.destination.coordinate
		shared.header.header_replaced = true


static func push_return(shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord) -> ScenarioVmResult:
	if shared.returns.size() >= 20:
		return ScenarioVmResult.failed(&"classic_gosub_limit", "Classic GOSUB stack exceeded 20 entries.")
	shared.returns.append(capture(shared, invocation))
	return ScenarioVmResult.completed()


static func pull_return(shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord) -> void:
	if not shared.returns.is_empty():
		var saved: ScenarioClassicReturnRecord = shared.returns.pop_back()
		restore_record(shared, invocation, saved)


static func clear_encounter(shared: ScenarioClassicExecutionState) -> void:
	shared.encounter_kind = &""
	shared.encounter_id = -1
	shared.encounter_attempt = 0
	shared.repeat_encounter = false


static func finish_record(shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord, path: ExitPath = ExitPath.NATURAL) -> void:
	invocation.completion.exit_path = ScenarioNativeCompletion.Exit.NATURAL if path == ExitPath.NATURAL else ScenarioNativeCompletion.Exit.KEEP_CODES
	invocation.completion.remove_selected_ap = path == ExitPath.NATURAL and invocation.mode == ScenarioClassicInvocationRecord.Mode.PLACED and not invocation.placed_trigger_id.is_empty() and shared.encounter_kind.is_empty()
	# newland(-1) returns before the ordinary encounter epilogue.
	if invocation.mode == ScenarioClassicInvocationRecord.Mode.MACRO and path == ExitPath.NATURAL:
		invocation.phase = ScenarioClassicInvocationRecord.Phase.COMPLETE
		return
	if not shared.encounter_kind.is_empty():
		var remaining := shared.encounter_remaining
		shared.encounter_remaining = ((remaining - 1 + 32768) & 65535) - 32768
		if remaining > 1:
			invocation.completion.exit_path = ScenarioNativeCompletion.Exit.NONE
			invocation.encounter_reload = false
			invocation.phase = ScenarioClassicInvocationRecord.Phase.ENCOUNTER
			return
	clear_encounter(shared)
	invocation.phase = ScenarioClassicInvocationRecord.Phase.COMPLETE


static func apply(directive: ScenarioVmDirective, definition: ScenarioDefinition, shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord, source: ClassicActionDefinition = null) -> ScenarioVmResult:
	if directive == null:
		return ScenarioVmResult.completed()
	match directive.kind:
		ScenarioVmDirective.NATIVE_RETURN:
			invocation.return_value = directive.return_value
			invocation.returned_early = true
			invocation.completion.exit_path = ScenarioNativeCompletion.Exit.NATIVE_RETURN
			invocation.completion.backout = directive.backout
			invocation.phase = ScenarioClassicInvocationRecord.Phase.COMPLETE
		ScenarioVmDirective.COPY_RECORD:
			return copy_record(directive, definition, shared, invocation)
		ScenarioVmDirective.KEEP_CODES:
			if directive.clear_encounter: clear_encounter(shared)
			finish_record(shared, invocation, ExitPath.KEEP_CODES)
		ScenarioVmDirective.BLOWOUT:
			shared.gosub = false
			shared.returns.clear()
			clear_encounter(shared)
			# FD-SCENARIO-028 retains Rebuilt's immediate timeline termination.
			finish_record(shared, invocation)
		ScenarioVmDirective.END_RECORD:
			if directive.clear_encounter: clear_encounter(shared)
			finish_record(shared, invocation)
		ScenarioVmDirective.RESUME_AFTER_ENCOUNTER:
			if invocation.encounter_exit == null:
				return ScenarioVmResult.failed(&"missing_encounter_exit", "The saved encounter has no available native exit record.")
			restore_record(shared, invocation, invocation.encounter_exit)
			clear_encounter(shared)
		ScenarioVmDirective.PUSH_CLASSIC_RETURN:
			return push_return(shared, invocation)
		ScenarioVmDirective.DROPOUT:
			var program := definition.program_by_id(shared.code.program_id)
			if program == null and shared.code.kind == ScenarioClassicProgramState.Kind.PROGRAM: return ScenarioVmResult.failed(&"invalid_program_dropout", "Classic dropout has no active record.")
			invocation.cursor = ScenarioProgramPosition.cursor_for_slot(program, 7) if shared.code.kind == ScenarioClassicProgramState.Kind.PROGRAM else 0
			invocation.native_slot = 7
		ScenarioVmDirective.RESTART_CURRENT_PROGRAM:
			invocation.cursor = 0
			invocation.native_slot = 0
			invocation.phase = ScenarioClassicInvocationRecord.Phase.CODE
		ScenarioVmDirective.BRANCH_XAP, ScenarioVmDirective.BRANCH_PROGRAM, ScenarioVmDirective.BRANCH_ENCOUNTER_RESULT:
			return transfer(directive, definition, shared, invocation)
		ScenarioVmDirective.ENTER_ENCOUNTER:
			return enter_encounter(directive, shared, invocation, source)
		ScenarioVmDirective.RECHECK_PROGRAM:
			var replaced := replace_code(definition, shared, invocation, directive.program_id, directive.context)
			if replaced.state == ScenarioVmResult.State.FAILED or directive.admitted: return replaced
			return apply(ScenarioVmDirective.native_return(0),definition,shared,invocation)
		ScenarioVmDirective.RESET_CODE:
			shared.returns.clear()
			clear_encounter(shared)
			return replace_code(definition, shared, invocation, directive.program_id, directive.context, directive.entry_cursor)
		_:
			return ScenarioVmResult.failed(&"unknown_vm_directive", "The runtime returned an unknown Classic transition.")
	return ScenarioVmResult.completed()


static func copy_record(directive: ScenarioVmDirective, definition: ScenarioDefinition, shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord) -> ScenarioVmResult:
	var code := directive.copied_code
	if code == null or not ScenarioExecutionRestoreRules.code_is_valid(code, definition) or directive.native_slot < 0 or directive.native_slot > 8:
		return ScenarioVmResult.failed(&"invalid_record_copy", "The loaded Classic code or native position is unavailable.")
	if directive.gosub:
		var pushed := push_return(shared, invocation)
		if pushed.state == ScenarioVmResult.State.FAILED: return pushed
	var context := shared.code.context.for_new_program_frame().merged(code.context)
	shared.code = code.copy()
	shared.code.context = context
	shared.code.context.program_resolved = true
	invocation.position_program_id = code.program_id
	invocation.position_kind = code.kind
	invocation.native_slot = directive.native_slot
	invocation.cursor = ScenarioProgramPosition.cursor_for_slot(definition.program_by_id(code.program_id), directive.native_slot) if code.kind == ScenarioClassicProgramState.Kind.PROGRAM else 0
	invocation.phase = ScenarioClassicInvocationRecord.Phase.CODE
	invocation.completion.exit_path = ScenarioNativeCompletion.Exit.NONE
	return ScenarioVmResult.completed()


static func transfer(directive: ScenarioVmDirective, definition: ScenarioDefinition, shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord) -> ScenarioVmResult:
	var target := "xap:%d" % directive.target_id if directive.kind == ScenarioVmDirective.BRANCH_XAP else directive.program_id
	if definition.program_by_id(target) == null:
		if not definition.native_program_is_unavailable(target):
			return ScenarioVmResult.failed(&"unknown_scenario_program", "Classic transfer references unavailable program '%s'." % target)
		# FD-SCENARIO-015 bounds an absent program as an empty call/transfer.
		if not directive.gosub: finish_record(shared, invocation)
		return ScenarioVmResult.completed()
	if directive.gosub:
		var pushed := push_return(shared, invocation)
		if pushed.state == ScenarioVmResult.State.FAILED: return pushed
	var context := shared.code.context.for_new_program_frame().merged(directive.context)
	context.program_resolved = false
	if directive.kind == ScenarioVmDirective.BRANCH_XAP:
		context.mark_program_transfer(shared.code.program_id, target)
	if directive.kind == ScenarioVmDirective.BRANCH_ENCOUNTER_RESULT:
		shared.encounter_kind = context.encounter_kind
		shared.encounter_id = context.encounter_id
		shared.encounter_attempt = context.encounter_attempt
		shared.repeat_encounter = directive.repeat_encounter
		invocation.encounter_reload = false
	return replace_code(definition, shared, invocation, target, context, directive.entry_cursor)


static func enter_encounter(directive: ScenarioVmDirective, shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord, source: ClassicActionDefinition) -> ScenarioVmResult:
	if directive.encounter_kind not in [&"simple", &"complex"]:
		return ScenarioVmResult.failed(&"invalid_encounter_branch", "Classic encounter transition has no selected kind.")
	if directive.gosub:
		var pushed := push_return(shared, invocation)
		if pushed.state == ScenarioVmResult.State.FAILED: return pushed
	# Only type2branch (40/85), rather than type2new, captures holddoor.
	if source != null and source.opcode in [40, 85] and directive.encounter_kind == &"complex":
		invocation.encounter_exit = capture(shared, invocation)
	shared.encounter_kind = directive.encounter_kind
	shared.encounter_id = directive.target_id
	shared.encounter_attempt = 0
	shared.repeat_encounter = false
	invocation.encounter_reload = true
	invocation.phase = ScenarioClassicInvocationRecord.Phase.ENCOUNTER
	return ScenarioVmResult.completed()


static func replace_code(definition: ScenarioDefinition, shared: ScenarioClassicExecutionState, invocation: ScenarioClassicInvocationRecord, program_id: String, context: ScenarioExecutionContext, cursor: int = 0) -> ScenarioVmResult:
	var program := definition.program_by_id(program_id)
	if program == null or cursor < 0 or cursor > program.instruction_count():
		return ScenarioVmResult.failed(&"unknown_scenario_program", "The selected Classic record or position is unavailable.")
	shared.code = ScenarioClassicProgramState.new()
	shared.code.program_id = program_id
	shared.code.context = context.copy()
	invocation.position_program_id = program_id
	invocation.position_kind = ScenarioClassicProgramState.Kind.PROGRAM
	invocation.cursor = cursor
	invocation.native_slot = ScenarioProgramPosition.slot_for_cursor(program, cursor)
	invocation.phase = ScenarioClassicInvocationRecord.Phase.CODE
	invocation.completion.exit_path = ScenarioNativeCompletion.Exit.NONE
	return ScenarioVmResult.completed()
