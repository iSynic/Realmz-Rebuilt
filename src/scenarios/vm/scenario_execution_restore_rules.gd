## Validates stable content identities and positions before live runner assignment.
class_name ScenarioExecutionRestoreRules
extends RefCounted


static func is_valid(state: ScenarioExecutionState, definition: ScenarioDefinition) -> bool:
	if state == null or definition == null: return false
	if state.classic.code != null and not code_is_valid(state.classic.code, definition): return false
	for entry: ScenarioClassicReturnRecord in state.classic.returns:
		if not return_is_valid(entry, definition): return false
	var safe_depths: Dictionary[int, int] = {}
	var timer_depth := 0
	for record: ScenarioExecutionRecord in state.records:
		match record.kind:
			ScenarioExecutionRecord.Kind.CLASSIC:
				var entry := record.classic
				if not entry.entry_program_id.is_empty() and definition.program_by_id(entry.entry_program_id) == null and not definition.native_program_is_unavailable(entry.entry_program_id): return false
				if not entry.position_program_id.is_empty() or entry.position_kind != ScenarioClassicProgramState.Kind.PROGRAM:
					if not position_is_valid(entry.position_kind, entry.position_program_id, entry.cursor, entry.native_slot, definition): return false
				if entry.encounter_exit != null and not return_is_valid(entry.encounter_exit, definition): return false
			ScenarioExecutionRecord.Kind.SAFE:
				var depth: int = safe_depths.get(record.safe.invocation_owner_id, 0)
				depth += 1
				safe_depths[record.safe.invocation_owner_id] = depth
				if depth > 32 or not safe_is_valid(record.safe, definition): return false
			ScenarioExecutionRecord.Kind.OPERATION:
				var call := record.operation
				var age := call.continuation.age() if call.continuation != null else null
				if age != null and age.directive != null and age.directive.kind == ScenarioVmDirective.RESET_CODE:
					var target := definition.program_by_id(age.directive.program_id)
					if target == null or age.directive.entry_cursor > target.instruction_count(): return false
				if call.child_call != null and call.child_call.kind == ScenarioProgramCall.Kind.TIMER:
					timer_depth += 1
					if timer_depth > ScenarioProgramCall.TIMER_CALL_LIMIT: return false
				if call.child_call != null and call.child_call.kind == ScenarioProgramCall.Kind.APPLICATION:
					var control := call.child_call.application.caller_control
					if control != null:
						if control.code != null and not code_is_valid(control.code, definition): return false
						for saved: ScenarioClassicReturnRecord in control.returns:
							if not return_is_valid(saved, definition): return false
				if call.restore_code != null and not code_is_valid(call.restore_code, definition): return false
				if call.child_restore_code != null and not code_is_valid(call.child_restore_code, definition): return false
				if call.child_call != null and definition.program_by_id(call.child_call.program_id()) == null and not definition.native_program_is_unavailable(call.child_call.program_id()): return false
				if call.child_call != null and call.return_kind == ScenarioOperationExecutionRecord.ReturnKind.CLASSIC and call.instruction_cursor < 0: return false
				if call.instruction_cursor >= 0:
					var program := definition.program_by_id(call.instruction_program_id)
					if program == null or call.instruction_cursor >= program.instruction_count() or not program.instruction_at(call.instruction_cursor) is ClassicActionDefinition: return false
					var issuing: ClassicActionDefinition = program.instruction_at(call.instruction_cursor)
					if call.restore_encounter_flag >= 0 and issuing.opcode != 48: return false
					if call.child_call != null and call.child_call.kind == ScenarioProgramCall.Kind.TIMER and issuing.opcode != 63: return false
					if call.restore_code != null and (issuing.opcode not in [2, 56, 107] or call.restore_code.program_id != program.id): return false
					if call.child_call != null and call.child_call.kind == ScenarioProgramCall.Kind.MACRO and call.child_call.macro.return_kind in [ScenarioMacroCall.ReturnKind.CLASSIC, ScenarioMacroCall.ReturnKind.DESTRUCTION]:
						var source: ClassicActionDefinition = program.instruction_at(call.instruction_cursor)
						var macro := call.child_call.macro
						if source.opcode != (125 if macro.return_kind == ScenarioMacroCall.ReturnKind.DESTRUCTION else macro.caller.opcode): return false
	return true


static func code_is_valid(code: ScenarioClassicProgramState, definition: ScenarioDefinition) -> bool:
	if code.kind != ScenarioClassicProgramState.Kind.PROGRAM:
		return code.timeline_values == null and (code.program_id.is_empty() or definition.program_by_id(code.program_id) != null or definition.native_program_is_unavailable(code.program_id))
	return definition.program_by_id(code.program_id) != null and (code.timeline_values == null or code.timeline_values.definition_id == code.program_id)


static func position_is_valid(kind: ScenarioClassicProgramState.Kind, id: String, cursor: int, slot: int, definition: ScenarioDefinition) -> bool:
	if kind == ScenarioClassicProgramState.Kind.UNAVAILABLE: return false
	if kind == ScenarioClassicProgramState.Kind.PROGRAM:
		return ScenarioProgramPosition.is_valid(definition.program_by_id(id), cursor, slot)
	return cursor == 0 and slot >= 0 and slot <= 8 and code_is_valid(ScenarioClassicProgramState.new(id, null, kind), definition)


static func return_is_valid(entry: ScenarioClassicReturnRecord, definition: ScenarioDefinition) -> bool:
	return code_is_valid(entry.code, definition) and position_is_valid(entry.code.kind, entry.code.program_id, entry.cursor, entry.native_slot, definition)


static func safe_is_valid(record: ScenarioSafeExecutionRecord, definition: ScenarioDefinition) -> bool:
	var action := definition.action_by_id(record.scope.definition_id)
	if action == null or record.cursor > action.program.instruction_count(): return false
	var parameters := action.parameters()
	if record.scope.parameters.size() != parameters.size(): return false
	for parameter: ScenarioActionParameter in parameters:
		if not record.scope.parameters.has(parameter.name) or not SafeExpressionEvaluator.value_matches_type(record.scope.parameters[parameter.name], parameter.value_type, parameter.max_length): return false
	for iterator: ScenarioSafeIterator in record.iterators:
		if iterator.begin_target >= action.program.instruction_count(): return false
		var instruction := action.program.instruction_at(iterator.begin_target)
		if instruction.kind != SafeInstructionDefinition.Kind.BEGIN_FOR_EACH or instruction.item_name != iterator.item_name: return false
	return true
