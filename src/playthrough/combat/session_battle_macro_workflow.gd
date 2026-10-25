## Returns direct battle macros through the same runner and lifecycle as scenario calls.
class_name SessionBattleMacroWorkflow
extends RefCounted


static func start(context: SessionContext, preceding_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var combat := context.state.combat
	if combat == null or combat.round_cursor == null or combat.round_cursor.phase != &"battle-macro":
		return SessionCoordinatorResult.failed(&"invalid_round_continuation", "The battle has no pending round macro.", preceding_events)
	var call := ScenarioMacroCall.new()
	call.battle_id = combat.battle_id
	call.program_id = "xap:%d" % absi(combat.macro_id)
	return start_call(context, call, preceding_events)


static func start_call(context: SessionContext, call: ScenarioMacroCall, preceding_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var operation := context.runtime_api.macros.begin(call, preceding_events)
	if operation.state == ScenarioRuntimeOperationResult.State.FAILED:
		return SessionCoordinatorResult.failed(operation.error_code, operation.error_message, operation.events)
	var body := CombatContinuationBody.new()
	body.battle_id = call.battle_id
	body.program_id = call.program_id
	body.combatant_id = call.combatant_id
	body.reset_traitor_on_complete = call.reset_traitor_on_complete
	context.set_continuation(CombatContinuations.round_macro(body) if call.kind == ScenarioMacroCall.Kind.ROUND else CombatContinuations.death_macro(body))
	var result := context.scenario_vm.start_program_call(operation.call, context.runtime_api)
	var events: Array[DomainEvent] = operation.events + result.events
	if result.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return SessionCoordinatorResult.failed(&"nested_host_handoff", "A direct combat macro cannot suspend another battle.", events)
	return finish(context, events, result.direct_combat_return)


static func finish(context: SessionContext, events: Array[DomainEvent], result: CombatFlowResult) -> SessionCoordinatorResult:
	var combat := context.state.combat
	var body := context.session_continuation.combat()
	if combat == null or body == null or combat.battle_id != body.battle_id or result == null:
		return SessionCoordinatorResult.failed(&"invalid_macro_return", "Direct macro completion lost its typed combat return.", events)
	context.session_continuation.clear()
	var returned := context.responses().finish_combat_result(result)
	returned.events = events + returned.events
	return returned
