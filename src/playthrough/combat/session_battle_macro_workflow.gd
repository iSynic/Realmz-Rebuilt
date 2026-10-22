## Runs a direct battle's authored round macro through the session-owned VM.
class_name SessionBattleMacroWorkflow
extends RefCounted


static func start(context: SessionContext, preceding_events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var combat := context.state.combat
	if combat == null or combat.round_cursor == null or combat.round_cursor.phase != &"battle-macro":
		return SessionCoordinatorResult.failed(&"invalid_round_continuation", "The battle has no pending round macro.", preceding_events)
	var body := CombatContinuationBody.new()
	body.battle_id = combat.battle_id
	body.program_id = "xap:%d" % absi(combat.macro_id)
	context.set_continuation(CombatContinuations.round_macro(body))
	var started := context.scenario_vm.start_program(body.program_id, ScenarioExecutionContext.calling(&"battle-macro").set_battle(combat.battle_id))
	if started.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(started.error_code, started.error_message, preceding_events)
	var result := context.scenario_vm.run(context.runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(preceding_events)
	events.append(DomainEvent.new(&"battle_macro_started", {"battleId": combat.battle_id, "programId": body.program_id, "round": combat.turns.round_number}))
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return SessionCoordinatorResult.failed(&"nested_host_handoff", "A round macro cannot suspend another battle.", events)
	return finish(context, events)


static func finish(context: SessionContext, events: Array[DomainEvent]) -> SessionCoordinatorResult:
	var combat := context.state.combat
	var body := context.session_continuation.combat()
	if combat == null or body == null or combat.battle_id != body.battle_id:
		return SessionCoordinatorResult.failed(&"invalid_round_continuation", "Round macro completion lost its battle.", events)
	events.append(DomainEvent.new(&"battle_macro_completed", {"battleId": combat.battle_id, "programId": body.program_id, "round": combat.turns.round_number}))
	context.session_continuation.clear()
	var result := context.rules.combat_flow.rounds.continue_after_battle_macro(context.state, context.content, context.rng)
	result.events = events + result.events
	return context.responses().finish_combat_result(result)
