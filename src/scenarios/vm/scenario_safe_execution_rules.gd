## Applies Safe-language rules to their dedicated lexical execution record.
class_name ScenarioSafeExecutionRules
extends RefCounted


static func validate_call(definition: ScenarioDefinition, action_id: String, arguments: Dictionary, calling: StringName, require_public: bool) -> ScenarioVmResult:
	var action := definition.action_by_id(action_id)
	if action == null:
		return ScenarioVmResult.failed(&"unknown_scenario_action", "Scenario Action '%s' is unavailable." % action_id)
	if require_public and action.visibility != &"public":
		return ScenarioVmResult.failed(&"private_scenario_action", "Private Scenario Action '%s' cannot be called from a timeline." % action_id)
	if calling == &"" or not action.allowed_contexts().has(calling):
		return ScenarioVmResult.failed(&"scenario_action_context", "Scenario Action '%s' is not allowed in context '%s'." % [action_id, calling])
	var parameters := action.parameters()
	if arguments.size() != parameters.size():
		return ScenarioVmResult.failed(&"scenario_action_arguments", "Scenario Action '%s' received the wrong argument set." % action_id)
	for parameter: ScenarioActionParameter in parameters:
		if not arguments.has(parameter.name) or not SafeExpressionEvaluator.value_matches_type(arguments[parameter.name], parameter.value_type, parameter.max_length):
			return ScenarioVmResult.failed(&"scenario_action_arguments", "Scenario Action '%s' received an invalid '%s' argument." % [action_id, parameter.name])
	return ScenarioVmResult.completed()


static func step(record: ScenarioSafeExecutionRecord, instruction: SafeInstructionDefinition, runtime: RealmzRuntimeApi) -> ScenarioVmResult:
	match instruction.kind:
		SafeInstructionDefinition.Kind.SET_VALUE:
			var evaluated := SafeExpressionEvaluator.evaluate(instruction.value, record.scope, runtime)
			if not evaluated["ok"]: return ScenarioVmActionRules.expression_failure(evaluated)
			if instruction.scope == &"local":
				record.scope.set_local(instruction.name, evaluated["value"])
			else:
				var state_scope := instruction.state_scope if not instruction.state_scope.is_empty() else "campaign"
				var owner := instruction.owner_id if not instruction.owner_id.is_empty() else record.scope.definition_id
				if not runtime.write_action_state(state_scope, owner, instruction.name, evaluated["value"]):
					return ScenarioVmResult.failed(&"scenario_state_limit", "Scenario Action state rejected an unsafe or oversized value.")
			record.cursor += 1
		SafeInstructionDefinition.Kind.JUMP_IF_FALSE:
			var evaluated := SafeExpressionEvaluator.evaluate(instruction.condition, record.scope, runtime)
			if not evaluated["ok"] or not evaluated["value"] is bool:
				return ScenarioVmActionRules.expression_failure(evaluated, "Safe condition did not evaluate to bool.")
			record.cursor = record.cursor + 1 if evaluated["value"] else instruction.target
		SafeInstructionDefinition.Kind.JUMP:
			record.cursor = instruction.target
		SafeInstructionDefinition.Kind.BEGIN_FOR_EACH:
			var evaluated := SafeExpressionEvaluator.evaluate(instruction.collection, record.scope, runtime)
			if not evaluated["ok"] or not evaluated["value"] is Array:
				return ScenarioVmActionRules.expression_failure(evaluated, "For-each input is not an array.")
			var values: Array = evaluated["value"]
			return ScenarioSafeInstructionRules.begin_for_each(record, instruction, values)
		SafeInstructionDefinition.Kind.NEXT_FOR_EACH:
			return ScenarioSafeInstructionRules.next_for_each(record, instruction)
		_:
			return ScenarioVmResult.failed(&"unknown_scenario_instruction", "Scenario Action contains an unavailable instruction.")
	return ScenarioVmResult.completed()


static func halt_invocation(state: ScenarioExecutionState, owner_id: int, outcome: Variant) -> ScenarioVmResult:
	if owner_id == 0:
		state.records.clear()
		state.last_outcome = outcome
		return ScenarioVmResult.completed()
	for index: int in state.records.size():
		var owner := state.records[index]
		if owner.id != owner_id: continue
		if owner.kind != ScenarioExecutionRecord.Kind.CLASSIC:
			return ScenarioVmResult.failed(&"invalid_safe_halt_owner", "The Safe halt target is not its native invocation.")
		state.records.resize(index + 1)
		owner.classic.completion.exit_path = ScenarioNativeCompletion.Exit.SAFE_HALT
		owner.classic.completion.remove_selected_ap = not owner.classic.placed_trigger_id.is_empty()
		owner.classic.phase = ScenarioClassicInvocationRecord.Phase.COMPLETE
		if index == 0: state.last_outcome = outcome
		return ScenarioVmResult.completed()
	return ScenarioVmResult.failed(&"invalid_safe_halt_owner", "The Safe halt target is unavailable.")
