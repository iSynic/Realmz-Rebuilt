## Coordinates developer commands that cross workflow, combat, and scenario boundaries.
class_name SessionDebugCoordinator
extends RefCounted

var _context: SessionContext
var started_ephemeral_operation: bool = false


func _init(context: SessionContext) -> void:
	_context = context


func run(command: SessionDebugCommand) -> SessionCoordinatorResult:
	if command == null or not _context.state.party_setup_completed:
		return SessionCoordinatorResult.failed(&"debug_command_unavailable", "Debug commands require a committed active adventure boundary.")
	var pending := _pending_interaction()
	var active_combat_command := command.kind in [SessionDebugCommand.Kind.RESTORE_PARTY, SessionDebugCommand.Kind.WIN_BATTLE] and _context.state.combat != null and not _context.state.combat.completed and (pending == null or pending.kind == InteractionRequest.COMBAT)
	if not active_combat_command and (pending != null or _context.scenario_vm.is_active()):
		return SessionCoordinatorResult.failed(&"debug_command_unavailable", "Debug commands require a committed active adventure boundary.")
	match command.kind:
		SessionDebugCommand.Kind.WARP:
			return _workflow(SessionDebugWorkflow.warp(_context.workflow_context(), command.map_id, command.coordinate))
		SessionDebugCommand.Kind.NOCLIP_STEP:
			return _workflow(SessionDebugWorkflow.noclip_step(_context.workflow_context(), command.coordinate))
		SessionDebugCommand.Kind.RESTORE_PARTY:
			return _workflow(SessionDebugWorkflow.restore_party(_context.workflow_context()))
		SessionDebugCommand.Kind.START_BATTLE:
			return _start_battle(command.classic_id)
		SessionDebugCommand.Kind.WIN_BATTLE:
			return _win_battle()
		SessionDebugCommand.Kind.START_ENCOUNTER:
			return _start_encounter(command.encounter_kind, command.classic_id)
	return SessionCoordinatorResult.failed(&"debug_command_unknown", "The debug command is unknown.")


func _start_battle(classic_id: int) -> SessionCoordinatorResult:
	if _context.state.combat != null:
		return SessionCoordinatorResult.failed(&"debug_battle_active", "A battle is already active.")
	var battle := _context.content.combat.battle_by_classic_id(classic_id)
	if battle == null:
		return SessionCoordinatorResult.failed(&"debug_battle_unknown", "Battle %d is unavailable." % classic_id)
	var result := _context.rules.combat_flow.start_battle(_context.state, _context.content, battle, _context.rng)
	if not result.ok:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message)
	result.events.append(DomainEvent.new(&"debug_battle_started", {"battleId": battle.id, "classicId": classic_id}))
	return SessionCoordinatorResult.completed(result.events)


func _win_battle() -> SessionCoordinatorResult:
	if _context.state.combat == null or _context.state.combat.completed:
		return SessionCoordinatorResult.failed(&"debug_battle_unavailable", "There is no active battle to win.")
	var state_checkpoint := _context.state.to_data()
	var rng_checkpoint := _context.rng.checkpoint()
	var vm_checkpoint := _context.scenario_vm.snapshot() if _context.scenario_vm.is_active() else null
	var events: Array[DomainEvent] = [DomainEvent.new(&"debug_battle_victory_requested", {"battleId": _context.state.combat.battle_id})]
	for monster: MonsterState in _context.state.combat.roster.monsters():
		if monster.traitor:
			monster.current_health = 0
			_context.state.combat.battlefield.actors.remove_monster(monster.id)
	for character: CharacterState in _context.state.party.characters():
		if character.traitor:
			character.current_health = 0
			_context.state.combat.battlefield.actors.remove_character(character.id)
	if not _context.rules.combat_flow.finish_debug_victory(_context.state, _context.content, events):
		return SessionCoordinatorResult.failed(&"debug_victory_failed", "The active battle could not resolve as a victory.")
	if vm_checkpoint != null:
		var result := _context.scenario_vm.complete_debug_victory(_context.runtime_api, events)
		if result.state == ScenarioVmResult.State.FAILED:
			if not _context.state.restore_from_data(state_checkpoint) or not _context.rng.rollback(rng_checkpoint) or not _context.scenario_vm.restore(vm_checkpoint):
				return SessionCoordinatorResult.failed(&"debug_victory_rollback_failed", "Debug victory failed and could not restore its combat continuation.")
			return SessionCoordinatorResult.failed(result.error_code, result.error_message)
		return _context.scenario().finish_resumed_vm_result(result, result.events)
	return _context.scenario().finish_direct_battle(events)


func _start_encounter(kind: StringName, classic_id: int) -> SessionCoordinatorResult:
	if _context.state.combat != null or kind not in [&"simple", &"complex"]:
		return SessionCoordinatorResult.failed(&"debug_encounter_unavailable", "A Simple or Complex Encounter requires exploration.")
	var available := _context.content.scenario_records.simple_encounter_by_id(classic_id) != null if kind == &"simple" else _context.content.scenario_records.complex_encounter_by_id(classic_id) != null
	if not available:
		return SessionCoordinatorResult.failed(&"debug_encounter_unknown", "%s Encounter %d is unavailable." % [String(kind).capitalize(), classic_id])
	var opcode := 4 if kind == &"simple" else 5
	var started := _context.scenario_vm.start_debug_instruction(ClassicActionDefinition.new(0, opcode, opcode, classic_id, false, []), ScenarioExecutionContext.trigger(&"debug", "", _context.state.party.map_id, _context.state.party.coordinate, true))
	if started.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(started.error_code, started.error_message)
	var result := _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		started_ephemeral_operation = true
		events.append(DomainEvent.new(&"debug_encounter_started", {"kind": String(kind), "classicId": classic_id}))
		return SessionCoordinatorResult.waiting(result.interaction, events)
	return SessionCoordinatorResult.failed(result.error_code, result.error_message, events) if result.state == ScenarioVmResult.State.FAILED else SessionCoordinatorResult.completed(events)


func _pending_interaction() -> InteractionRequest:
	if _context.session_interaction != null:
		return _context.session_interaction
	return _context.scenario_vm.pending_request() if _context.scenario_vm != null else null


func _workflow(result: SessionWorkflowResult) -> SessionCoordinatorResult:
	if result == null:
		return SessionCoordinatorResult.failed(&"invalid_workflow_result", "The debug workflow returned no result.")
	return SessionCoordinatorResult.completed(result.events) if result.ok else SessionCoordinatorResult.failed(result.error_code, result.error_message)
