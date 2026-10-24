## Applies Classic program, GOSUB, and encounter directives to VM frames.

class_name ScenarioClassicControlFlow
extends RefCounted

const CLASSIC_CALL_LIMIT := 20


static func apply(directive: ScenarioVmDirective, definition: ScenarioDefinition, frames: Array[ScenarioFrame], inherited_context: ScenarioExecutionContext = null, runtime_available: bool = false) -> ScenarioDirectiveTransition:
	if directive == null:
		return ScenarioDirectiveTransition.completed()
	match directive.kind:
		ScenarioVmDirective.FINISH:
			return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.RETURN_FRAME)
		ScenarioVmDirective.FINISH_TIMELINE:
			return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.FINISH_TIMELINE, [{"event": "classic-finish-timeline"}])
		ScenarioVmDirective.RESUME_AFTER_ENCOUNTER:
			return resume_encounter(definition, frames)
		ScenarioVmDirective.RESTART_CURRENT_PROGRAM:
			return _restart_program(frames)
		ScenarioVmDirective.PUSH_CLASSIC_RETURN:
			return _push_classic_return(frames)
		ScenarioVmDirective.DROPOUT:
			return _dropout_program(definition, frames)
		ScenarioVmDirective.BRANCH_XAP:
			return _branch_xap(directive, definition, frames, inherited_context)
		ScenarioVmDirective.BRANCH_PROGRAM:
			return _branch_program(directive, definition, frames, inherited_context)
		ScenarioVmDirective.CLOCK_TIMER_RETURN:
			return _clock_timer_return(directive, definition, frames)
		ScenarioVmDirective.ENTER_ENCOUNTER:
			return _enter_encounter(directive, frames, inherited_context, runtime_available)
		ScenarioVmDirective.BRANCH_ENCOUNTER_RESULT:
			return _branch_encounter_result(directive, definition, frames, inherited_context, runtime_available)
	return ScenarioDirectiveTransition.failed(&"unknown_vm_directive", "Realmz Runtime API returned an unknown VM directive.")


static func _clock_timer_return(directive: ScenarioVmDirective, definition: ScenarioDefinition, frames: Array[ScenarioFrame]) -> ScenarioDirectiveTransition:
	var program := definition.program_by_id(directive.program_id)
	if frames.is_empty() or frames.back().kind != ScenarioFrame.PROGRAM or program == null or directive.entry_cursor > program.instruction_count():
		return ScenarioDirectiveTransition.failed(&"invalid_clock_return", "The native timed-program return is unavailable.")
	# The timer's newland resets GOSUB and encounter repetition in this native
	# invocation. An enclosing Scenario Action remains a separate call owner.
	var invocation_index := frames.size() - 1
	while invocation_index > 0 and frames[invocation_index - 1].kind != ScenarioFrame.ACTION:
		invocation_index -= 1
	var context := frames[invocation_index].context().without_encounter().merged(directive.context)
	frames.resize(invocation_index + 1)
	var target := ScenarioFrame.new(ScenarioFrame.PROGRAM, directive.program_id, directive.entry_cursor)
	target.set_context(context)
	frames[frames.size() - 1] = target
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-clock-timer-return", "programId": directive.program_id, "cursor": directive.entry_cursor}])


static func replace_xap(definition: ScenarioDefinition, frames: Array[ScenarioFrame], source: ScenarioFrame, native_id: int, slot: int) -> ScenarioDirectiveTransition:
	var target_id := "xap:%d" % native_id
	if definition.program_by_id(target_id) == null:
		if definition.native_xap_is_unavailable(native_id):
			return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.RETURN_FRAME, [{"event": "classic-unavailable-program", "programId": target_id, "sourceProgramId": source.definition_id, "slot": slot}])
		return ScenarioDirectiveTransition.failed(&"unknown_scenario_program", "Classic opcode 39 references unavailable XAP %d." % native_id)
	var replacement := ScenarioFrame.new(ScenarioFrame.PROGRAM, target_id)
	replacement.counts_as_classic_call = source.counts_as_classic_call
	var context := source.context()
	context.mark_program_transfer(source.definition_id, target_id)
	replacement.set_context(context)
	frames[frames.size() - 1] = replacement
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-transfer", "programId": target_id}])


static func resume_encounter(definition: ScenarioDefinition, frames: Array[ScenarioFrame]) -> ScenarioDirectiveTransition:
	if frames.size() < 2:
		return ScenarioDirectiveTransition.failed(&"invalid_encounter_loop", "Classic encounter exit has no issuing program frame.")
	var encounter_frame: ScenarioFrame = frames.back()
	var encounter_context: ScenarioExecutionContext = encounter_frame.context()
	for frame_index: int in range(frames.size() - 2, -1, -1):
		var source_frame: ScenarioFrame = frames[frame_index]
		if source_frame.kind == ScenarioFrame.ENCOUNTER:
			if _same_encounter(source_frame.context(), encounter_context):
				return _exit_encounter_frame(frames, frame_index, source_frame, encounter_context)
			continue
		if source_frame.kind != ScenarioFrame.PROGRAM:
			continue
		var program := definition.program_by_id(source_frame.definition_id)
		var instruction: Variant = program.instruction_at(source_frame.cursor) if program != null else null
		if instruction is ClassicActionDefinition:
			var issuing_action: ClassicActionDefinition = instruction
			if _is_issuing_encounter(issuing_action, encounter_context):
				return _exit_issuing_program(frames, frame_index, source_frame, encounter_context)
	return ScenarioDirectiveTransition.failed(&"invalid_encounter_loop", "Classic encounter exit cannot find its issuing encounter instruction.")


static func _push_classic_return(frames: Array[ScenarioFrame]) -> ScenarioDirectiveTransition:
	if frames.is_empty() or frames.back().kind != ScenarioFrame.PROGRAM:
		return ScenarioDirectiveTransition.failed(&"invalid_classic_return", "Classic return push has no issuing program.")
	# Castle opcode 67 pushes before testing the successful destination -1.
	# The active record continues; 111 later resumes its saved following slot.
	var source: ScenarioFrame = frames.back()
	var active := ScenarioFrame.from_data(source.to_data())
	return _install_program_frame(active, true, frames, active.definition_id)


static func _restart_program(frames: Array[ScenarioFrame]) -> ScenarioDirectiveTransition:
	if frames.is_empty() or frames.back().kind != ScenarioFrame.PROGRAM:
		return ScenarioDirectiveTransition.failed(&"invalid_program_restart", "Classic battle restart has no issuing program frame.")
	frames.back().cursor = 0
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-program-restart", "programId": frames.back().definition_id}])


# Castle jumps to native slot 7. Compiled programs omit empty slots, so the
# cursor is the first retained Classic instruction at or after that slot.
static func _dropout_program(definition: ScenarioDefinition, frames: Array[ScenarioFrame]) -> ScenarioDirectiveTransition:
	var program: ScenarioProgramDefinition = null
	if not frames.is_empty() and frames.back().kind == ScenarioFrame.PROGRAM:
		var issuing_frame: ScenarioFrame = frames.back()
		program = definition.program_by_id(issuing_frame.definition_id)
	if program == null:
		return ScenarioDirectiveTransition.failed(&"invalid_program_dropout", "Classic dropout has no issuing program frame.")
	var cursor := 0
	while cursor < program.instruction_count():
		var instruction: Variant = program.instruction_at(cursor)
		if instruction is ClassicActionDefinition and instruction.slot >= 7: break
		cursor += 1
	frames.back().cursor = cursor
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-dropout", "programId": program.id, "cursor": cursor}])


static func _branch_xap(directive: ScenarioVmDirective, definition: ScenarioDefinition, frames: Array[ScenarioFrame], inherited_context: ScenarioExecutionContext) -> ScenarioDirectiveTransition:
	var program_id := "xap:%d" % directive.target_id
	if definition.program_by_id(program_id) == null:
		# FD-SCENARIO-015: an absent native target acts as an empty transfer;
		# undefined native reads never justify replacing it with another program.
		if definition.native_xap_is_unavailable(directive.target_id):
			return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE if directive.gosub else ScenarioDirectiveTransition.Action.RETURN_FRAME, [{"event": "classic-unavailable-program", "targetId": directive.target_id, "gosub": directive.gosub}])
		return ScenarioDirectiveTransition.failed(&"unknown_scenario_program", "Classic branch references unavailable XAP %d." % directive.target_id)
	var target := ScenarioFrame.new(ScenarioFrame.PROGRAM, program_id)
	target.set_context(_new_program_context(ScenarioExecutionContext.empty() if inherited_context == null else inherited_context))
	return _install_program_frame(target, directive.gosub, frames, program_id)


static func _branch_program(directive: ScenarioVmDirective, definition: ScenarioDefinition, frames: Array[ScenarioFrame], inherited_context: ScenarioExecutionContext) -> ScenarioDirectiveTransition:
	if definition.program_by_id(directive.program_id) == null:
		if definition.native_program_is_unavailable(directive.program_id):
			return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE if directive.gosub else ScenarioDirectiveTransition.Action.RETURN_FRAME, [{"event": "classic-unavailable-program", "programId": directive.program_id, "gosub": directive.gosub}])
		return ScenarioDirectiveTransition.failed(&"unknown_scenario_program", "Classic branch references unavailable program '%s'." % directive.program_id)
	var target := ScenarioFrame.new(ScenarioFrame.PROGRAM, directive.program_id)
	target.cursor = directive.entry_cursor
	var base_context := ScenarioExecutionContext.empty() if inherited_context == null else inherited_context
	target.set_context(_new_program_context(base_context.merged(directive.context)))
	return _install_program_frame(target, directive.gosub, frames, directive.program_id)


static func _install_program_frame(target: ScenarioFrame, gosub: bool, frames: Array[ScenarioFrame], program_id: String) -> ScenarioDirectiveTransition:
	if frames.is_empty():
		return ScenarioDirectiveTransition.failed(&"invalid_program_restart", "Classic branch has no issuing program frame.")
	if gosub and _classic_call_depth(frames) >= CLASSIC_CALL_LIMIT:
		return ScenarioDirectiveTransition.failed(&"classic_gosub_limit", "Classic GOSUB stack exceeded 20 frames.")
	target.counts_as_classic_call = gosub or frames.back().counts_as_classic_call
	if gosub:
		frames.append(target)
	else:
		frames[frames.size() - 1] = target
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-branch", "programId": program_id, "gosub": gosub}])


static func _enter_encounter(directive: ScenarioVmDirective, frames: Array[ScenarioFrame], inherited_context: ScenarioExecutionContext, runtime_available: bool) -> ScenarioDirectiveTransition:
	if not runtime_available or directive.encounter_kind not in [&"simple", &"complex"] or frames.is_empty():
		return ScenarioDirectiveTransition.failed(&"invalid_encounter_branch", "Classic encounter transition is unavailable.")
	if directive.gosub and _classic_call_depth(frames) >= CLASSIC_CALL_LIMIT:
		return ScenarioDirectiveTransition.failed(&"classic_gosub_limit", "Classic GOSUB stack exceeded 20 frames.")
	var context := (ScenarioExecutionContext.empty() if inherited_context == null else inherited_context.copy()).merged(ScenarioExecutionContext.encounter(directive.encounter_kind, directive.target_id).set_encounter_attempt(0))
	var encounter := ScenarioFrame.new(ScenarioFrame.ENCOUNTER, "%s:%d" % [directive.encounter_kind, directive.target_id])
	encounter.counts_as_classic_call = directive.gosub
	encounter.set_context(context)
	if directive.gosub:
		frames.append(encounter)
	else:
		frames[frames.size() - 1] = encounter
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-encounter-branch", "encounterKind": String(directive.encounter_kind), "encounterId": directive.target_id, "gosub": directive.gosub}])


static func _branch_encounter_result(directive: ScenarioVmDirective, definition: ScenarioDefinition, frames: Array[ScenarioFrame], inherited_context: ScenarioExecutionContext, runtime_available: bool) -> ScenarioDirectiveTransition:
	if definition.program_by_id(directive.program_id) == null:
		if definition.native_program_is_unavailable(directive.program_id):
			return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE if directive.gosub else ScenarioDirectiveTransition.Action.RETURN_FRAME, [{"event": "classic-unavailable-result", "programId": directive.program_id}])
		return ScenarioDirectiveTransition.failed(&"unknown_scenario_program", "Classic encounter result references unavailable program '%s'." % directive.program_id)
	if not frames.is_empty() and frames.back().kind == ScenarioFrame.ENCOUNTER:
		return _push_encounter_result(directive, frames)
	if not directive.repeat_encounter:
		return apply(ScenarioVmDirective.branch_program(directive.program_id, directive.gosub, directive.context), definition, frames, inherited_context, runtime_available)
	if frames.is_empty() or frames.back().kind != ScenarioFrame.PROGRAM or frames.back().cursor < 1:
		return ScenarioDirectiveTransition.failed(&"invalid_encounter_loop", "Classic encounter repetition has no issuing program frame.")
	return _repeat_issuing_encounter(directive, frames, inherited_context)


static func _push_encounter_result(directive: ScenarioVmDirective, frames: Array[ScenarioFrame]) -> ScenarioDirectiveTransition:
	var encounter: ScenarioFrame = frames.back()
	var context := encounter.context().merged(directive.context)
	encounter.set_context(context)
	encounter.cursor = 0 if directive.repeat_encounter else 1
	var result := ScenarioFrame.new(ScenarioFrame.PROGRAM, directive.program_id)
	result.set_context(_new_program_context(context))
	frames.append(result)
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-encounter-repeat" if directive.repeat_encounter else "classic-encounter-result", "programId": directive.program_id, "attempt": context.encounter_attempt}])


static func _repeat_issuing_encounter(directive: ScenarioVmDirective, frames: Array[ScenarioFrame], inherited_context: ScenarioExecutionContext) -> ScenarioDirectiveTransition:
	var source: ScenarioFrame = frames.back()
	var base_context := source.context() if inherited_context == null else inherited_context.copy()
	var context := base_context.merged(directive.context)
	source.cursor -= 1
	source.set_context(context)
	var result := ScenarioFrame.new(ScenarioFrame.PROGRAM, directive.program_id)
	result.set_context(_new_program_context(context))
	frames.append(result)
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-encounter-repeat", "programId": directive.program_id, "attempt": context.encounter_attempt}])


static func _exit_encounter_frame(frames: Array[ScenarioFrame], frame_index: int, source: ScenarioFrame, context: ScenarioExecutionContext) -> ScenarioDirectiveTransition:
	var returns_to_source := source.counts_as_classic_call
	frames.resize(frame_index)
	var action := ScenarioDirectiveTransition.Action.HALT if frames.is_empty() else ScenarioDirectiveTransition.Action.CONTINUE
	return ScenarioDirectiveTransition.completed(action, [{"event": "classic-encounter-exit", "programId": source.definition_id, "encounterKind": String(context.encounter_kind), "encounterId": context.encounter_id, "returnsToSource": returns_to_source}])


static func _exit_issuing_program(frames: Array[ScenarioFrame], frame_index: int, source: ScenarioFrame, context: ScenarioExecutionContext) -> ScenarioDirectiveTransition:
	frames.resize(frame_index + 1)
	source.cursor += 1
	source.set_context(source.context().without_encounter())
	return ScenarioDirectiveTransition.completed(ScenarioDirectiveTransition.Action.CONTINUE, [{"event": "classic-encounter-exit", "programId": source.definition_id, "encounterKind": String(context.encounter_kind), "encounterId": context.encounter_id}])


static func _same_encounter(left: ScenarioExecutionContext, right: ScenarioExecutionContext) -> bool:
	return left.encounter_kind == right.encounter_kind and left.encounter_id == right.encounter_id


static func _is_issuing_encounter(instruction: ClassicActionDefinition, context: ScenarioExecutionContext) -> bool:
	return context != null and ((context.encounter_kind == &"simple" and instruction.opcode == 4) or (context.encounter_kind == &"complex" and instruction.opcode == 5)) and instruction.operand_id == context.encounter_id


static func _classic_call_depth(frames: Array[ScenarioFrame]) -> int:
	var count := 0
	for frame: ScenarioFrame in frames:
		if frame.counts_as_classic_call:
			count += 1
	return count


# Every new program frame resolves its own opcode-7 override, even when it
# inherits an already-resolved issuing frame's trigger and caller provenance.
static func _new_program_context(base: ScenarioExecutionContext) -> ScenarioExecutionContext:
	var context := base.copy()
	context.program_resolved = false
	return context
