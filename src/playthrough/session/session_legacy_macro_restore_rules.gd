## Adds explicit direct-session macro ownership to historical execution state.
class_name SessionLegacyMacroRestoreRules
extends RefCounted


static func normalize(execution: ScenarioExecutionState, continuation: SessionContinuation) -> ScenarioExecutionState:
	if continuation == null or continuation.kind not in [&"combat-round-macro", &"combat-death-macro"]: return execution
	var body := continuation.combat()
	if body == null: return null
	var call := ScenarioMacroCall.new()
	call.kind = ScenarioMacroCall.Kind.ROUND if continuation.kind == &"combat-round-macro" else ScenarioMacroCall.Kind.DEATH
	call.battle_id = body.battle_id
	call.program_id = body.program_id
	call.combatant_id = body.combatant_id
	call.reset_traitor_on_complete = body.reset_traitor_on_complete
	var state := ScenarioExecutionState.new()
	state.halted = false
	var owner := state.append_record(ScenarioExecutionRecord.Kind.OPERATION)
	owner.operation = ScenarioOperationExecutionRecord.new()
	owner.operation.return_kind = ScenarioOperationExecutionRecord.ReturnKind.DIRECT
	return state if ScenarioLegacyMacroCodec.attach(state, execution, call) else null
