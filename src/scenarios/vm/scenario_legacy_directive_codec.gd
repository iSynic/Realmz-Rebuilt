## Replaces historical pending age exits with closed current transitions.
class_name ScenarioLegacyDirectiveCodec
extends RefCounted


static func normalize(state: ScenarioExecutionState, definition: ScenarioDefinition) -> bool:
	var owner: ScenarioExecutionRecord = state.records.back()
	var operation := owner.operation
	var age := operation.continuation.age()
	if age == null or age.directive == null: return true
	match age.directive.kind:
		ScenarioVmDirective.BLOWOUT:
			return false
		ScenarioVmDirective.FINISH:
			age.directive = ScenarioVmDirective.end_record()
		ScenarioVmDirective.FINISH_TIMELINE:
			age.directive = ScenarioVmDirective.end_record(true)
		ScenarioVmDirective.CLOCK_TIMER_RETURN:
			var legacy := age.directive
			var program := definition.program_by_id(legacy.program_id)
			if program == null or legacy.entry_cursor > program.instruction_count(): return false
			if operation.return_kind != ScenarioOperationExecutionRecord.ReturnKind.CLASSIC: return false
			for record: ScenarioExecutionRecord in state.records:
				if record.id == owner.parent_id and record.kind == ScenarioExecutionRecord.Kind.CLASSIC:
					var context := record.classic.context.without_encounter().merged(legacy.context)
					age.directive = ScenarioVmDirective.reset_code(legacy.program_id, legacy.entry_cursor, context)
					return true
			return false
	return true
