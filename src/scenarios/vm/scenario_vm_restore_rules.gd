## Validates immutable VM frame references before replacing live execution state.
class_name ScenarioVmRestoreRules
extends RefCounted


static func frames_are_valid(definition: ScenarioDefinition, saved: ScenarioVmSnapshot, classic_limit: int, action_limit: int) -> bool:
	if saved == null or definition == null or saved.frames.size() > classic_limit + action_limit + 1: return false
	var action_depth := 0
	var classic_depth := 0
	for frame: ScenarioFrame in saved.frames:
		if frame.kind == ScenarioFrame.PROGRAM:
			var program := definition.program_by_id(frame.definition_id)
			if program == null or frame.cursor > program.instruction_count(): return false
			if frame.counts_as_classic_call: classic_depth += 1
		elif frame.kind == ScenarioFrame.ACTION:
			var action := definition.action_by_id(frame.definition_id)
			if action == null or frame.cursor > action.program.instruction_count(): return false
			action_depth += 1
		else:
			var context := frame.context()
			if frame.kind != ScenarioFrame.ENCOUNTER or frame.cursor not in [0, 1] or context.encounter_kind not in [&"simple", &"complex"] or context.encounter_id < 0 or frame.definition_id != "%s:%d" % [context.encounter_kind, context.encounter_id]: return false
			if frame.counts_as_classic_call: classic_depth += 1
	return action_depth <= action_limit and classic_depth <= classic_limit and (saved.classic_record_id.is_empty() or definition.program_by_id(saved.classic_record_id) != null)
