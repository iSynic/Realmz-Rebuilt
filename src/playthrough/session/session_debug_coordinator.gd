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
		SessionDebugCommand.Kind.START_ACTION_POINT:
			return _start_action_point(command.target_id)
		SessionDebugCommand.Kind.START_EXTRA_ACTION_POINT_PROGRAM:
			return _start_extra_action_point_program(command.classic_id)
		SessionDebugCommand.Kind.START_BATTLE:
			return _start_battle(command.classic_id)
		SessionDebugCommand.Kind.START_TREASURE:
			return _start_treasure(command.classic_id)
		SessionDebugCommand.Kind.START_SHOP:
			return _start_shop(command.classic_id)
		SessionDebugCommand.Kind.WIN_BATTLE:
			return _win_battle()
		SessionDebugCommand.Kind.START_ENCOUNTER:
			return _start_encounter(command.encounter_kind, command.classic_id)
		SessionDebugCommand.Kind.START_SCROLLING_TEXT:
			return _start_scrolling_text(command.classic_id)
	return SessionCoordinatorResult.failed(&"debug_command_unknown", "The debug command is unknown.")


func _start_action_point(trigger_id: String) -> SessionCoordinatorResult:
	var result: SessionCoordinatorResult = _context.exploration().start_debug_action_point(trigger_id)
	if result.state == SessionCoordinatorResult.State.WAITING:
		started_ephemeral_operation = true
	return result


func _start_extra_action_point_program(native_id: int) -> SessionCoordinatorResult:
	if _context.state.combat != null:
		return SessionCoordinatorResult.failed(&"debug_extra_action_point_unavailable", "Extra Action Point program preview requires exploration.")
	var program := _context.content.scenario.program_by_id("xap:%d" % native_id)
	if program == null:
		return SessionCoordinatorResult.failed(&"debug_extra_action_point_unknown", "Extra Action Point program %d is unavailable." % native_id)
	if not program.matches_extra_action_point(native_id):
		return SessionCoordinatorResult.failed(&"debug_extra_action_point_mismatch", "Extra Action Point program %d has mismatched ownership." % native_id)
	var map := _context.content.world.map_by_id(_context.state.party.map_id)
	if map == null or map.topology.cell_at(_context.state.party.coordinate) == null:
		return SessionCoordinatorResult.failed(&"debug_extra_action_point_unavailable", "Extra Action Point program preview requires a playable exploration location.")
	var execution := ScenarioExecutionContext.trigger(&"action", program.owner_id, map.id, _context.state.party.coordinate, true)
	var started := _context.scenario_vm.start_program(program.id, execution)
	if started.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(started.error_code, started.error_message)
	var result := _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = [DomainEvent.new(&"debug_extra_action_point_program_started", {"classicId": native_id, "programId": program.id, "context": "standalone"})]
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return SessionCoordinatorResult.failed(&"debug_extra_action_point_handoff_unsupported", "Standalone Extra Action Point preview cannot suspend a total-party defeat.", events)
	if result.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if result.state == ScenarioVmResult.State.WAITING:
		started_ephemeral_operation = true
		return SessionCoordinatorResult.waiting(result.interaction, events)
	return SessionCoordinatorResult.completed(events)


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


func _start_treasure(classic_id: int) -> SessionCoordinatorResult:
	if _context.state.combat != null:
		return SessionCoordinatorResult.failed(&"debug_treasure_unavailable", "Treasure preview requires exploration.")
	if _context.content.economy.treasure_by_classic_id(classic_id) == null:
		return SessionCoordinatorResult.failed(&"debug_treasure_unknown", "Treasure %d is unavailable." % classic_id)
	var instruction := ClassicActionDefinition.new(0, 10, 10, classic_id, false, [])
	var execution := ScenarioExecutionContext.trigger(&"debug", "", _context.state.party.map_id, _context.state.party.coordinate, true)
	var started := _context.scenario_vm.start_debug_instruction(instruction, execution)
	if started.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(started.error_code, started.error_message)
	var result := _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		started_ephemeral_operation = true
		events.append(DomainEvent.new(&"debug_treasure_started", {"classicId": classic_id}))
		return SessionCoordinatorResult.waiting(result.interaction, events)
	return SessionCoordinatorResult.failed(result.error_code, result.error_message, events) if result.state == ScenarioVmResult.State.FAILED else SessionCoordinatorResult.completed(events)


func _start_shop(classic_id: int) -> SessionCoordinatorResult:
	if _context.state.combat != null:
		return SessionCoordinatorResult.failed(&"debug_shop_unavailable", "Shop preview requires exploration.")
	var shop := _context.content.economy.shop_by_classic_id(classic_id)
	if shop == null:
		return SessionCoordinatorResult.failed(&"debug_shop_unknown", "Shop %d is unavailable." % classic_id)
	var state_checkpoint := _context.state.to_data()
	var accept_ranges: Array[int] = [0, 0, 0, 0]
	if not _context.state.location_services.set_active_shop(shop.id, accept_ranges):
		return SessionCoordinatorResult.failed(&"debug_shop_configuration_failed", "Shop %d could not be configured." % classic_id)
	var operation := _context.runtime_api.request_available_shop("debug.shop:%d:%d" % [classic_id, _context.current_revision()])
	var result: SessionCoordinatorResult = _context.responses().begin_runtime_service(shop.id, operation)
	if result.state != SessionCoordinatorResult.State.WAITING:
		if not _context.state.restore_from_data(state_checkpoint):
			return SessionCoordinatorResult.failed(&"debug_shop_rollback_failed", "Shop preview failed and could not restore the isolated session.", result.events)
		return result
	started_ephemeral_operation = true
	result.events.append(DomainEvent.new(&"debug_shop_started", {"shopId": shop.id, "classicId": classic_id, "acceptRanges": accept_ranges}))
	return result


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


func _start_scrolling_text(resource_id: int) -> SessionCoordinatorResult:
	if _context.state.combat != null or resource_id == 0:
		return SessionCoordinatorResult.failed(&"debug_scrolling_text_unavailable", "Scrolling text preview requires exploration and an exact nonzero TEXT resource ID.")
	var instruction := ClassicActionDefinition.new(0, 62, 62, resource_id, false, [])
	var execution := ScenarioExecutionContext.trigger(&"debug", "", _context.state.party.map_id, _context.state.party.coordinate, true)
	var started := _context.scenario_vm.start_debug_instruction(instruction, execution)
	if started.state == ScenarioVmResult.State.FAILED:
		return SessionCoordinatorResult.failed(started.error_code, started.error_message)
	var result := _context.scenario_vm.run(_context.runtime_api)
	var events: Array[DomainEvent] = []
	events.assign(result.events)
	if result.state != ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.failed(result.error_code if result.state == ScenarioVmResult.State.FAILED else &"debug_scrolling_text_failed", result.error_message if result.state == ScenarioVmResult.State.FAILED else "Scrolling text preview did not open its acknowledgement surface.", events)
	started_ephemeral_operation = true
	events.append(DomainEvent.new(&"debug_scrolling_text_started", {"resourceType": "TEXT", "resourceId": resource_id}))
	return SessionCoordinatorResult.waiting(result.interaction, events)


func _pending_interaction() -> InteractionRequest:
	if _context.session_interaction != null:
		return _context.session_interaction
	return _context.scenario_vm.pending_request() if _context.scenario_vm != null else null


func _workflow(result: SessionWorkflowResult) -> SessionCoordinatorResult:
	if result == null:
		return SessionCoordinatorResult.failed(&"invalid_workflow_result", "The debug workflow returned no result.")
	return SessionCoordinatorResult.completed(result.events) if result.ok else SessionCoordinatorResult.failed(result.error_code, result.error_message)
