## Coordinates one selected Action Point through its ordinary scenario lifecycle.

class_name SessionActionPointCoordinator
extends RefCounted

class TriggerContext extends RefCounted:
	var continuation: ExplorationContinuationBody
	var map: MapDefinition
	var coordinate: Vector2i

var _context: SessionContext
var _exploration: SessionExplorationCoordinator


func _init(context: SessionContext, exploration: SessionExplorationCoordinator) -> void:
	_context = context
	_exploration = exploration


func start_debug(trigger_id: String) -> SessionCoordinatorResult:
	var trigger := _context.content.scenario_records.trigger_by_id(trigger_id)
	var map: MapDefinition = null if trigger == null else _context.content.world.map_by_id(trigger.map_id)
	if trigger == null:
		return SessionCoordinatorResult.failed(&"debug_action_point_unknown", "Action Point '%s' is unavailable." % trigger_id)
	if map == null or map.topology.cell_at(trigger.coordinate) == null:
		return SessionCoordinatorResult.failed(&"debug_action_point_unplaced", "Action Point '%s' has no playable map location." % trigger_id)
	if _context.state.combat != null:
		return SessionCoordinatorResult.failed(&"debug_exploration_required", "An Action Point preview requires exploration.")
	var source_map := _context.state.party.map_id
	var source_coordinate := _context.state.party.coordinate
	_context.state.party.map_id = map.id
	_context.state.party.coordinate = trigger.coordinate
	_context.state.last_move_direction = Vector2i.ZERO
	_context.state.world.exploration.mark_visited(map.id, trigger.coordinate)
	var continuation := _debug_continuation(map, trigger)
	_context.set_continuation(ExplorationContinuations.post_move(continuation))
	var events: Array[DomainEvent] = [DomainEvent.new(&"debug_party_warped", {"fromMapId": source_map, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": map.id, "x": trigger.coordinate.x, "y": trigger.coordinate.y})]
	events.append(DomainEvent.new(&"trigger_fired", {"triggerId": trigger.id}))
	events.append(DomainEvent.new(&"debug_action_point_started", {"triggerId": trigger.id}))
	var trigger_context := TriggerContext.new()
	trigger_context.continuation = continuation
	trigger_context.map = map
	trigger_context.coordinate = trigger.coordinate
	var step = execute(trigger_context, trigger, events)
	if step != null:
		return step
	_context.session_continuation.clear()
	return SessionCoordinatorResult.completed(events)


func execute(trigger_context: Variant, trigger: TriggerDefinition, events: Array[DomainEvent]):
	var continuation: ExplorationContinuationBody = trigger_context.continuation
	continuation.active_trigger_id = trigger.id
	var execution_context := ScenarioExecutionContext.trigger(&"action", trigger.id, trigger_context.map.id, trigger_context.coordinate, true)
	var started := _context.scenario_vm.start_program(trigger.program_id, execution_context)
	if started.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(started.error_code, started.error_message, events)
	var result := _context.scenario_vm.run(_context.runtime_api)
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.SUSPENDED:
		return _context.scenario().begin_scenario_handoff(result, events)
	if result.state == ScenarioVmResult.State.WAITING:
		return SessionCoordinatorResult.waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_context.session_continuation.clear()
		return SessionCoordinatorResult.failed(result.error_code, result.error_message, events)
	if _context.events_have(result.events, &"party_backed_up"):
		_context.session_continuation.clear()
		return SessionCoordinatorResult.completed(events)
	_context.scenario().finalize_completed_trigger(trigger, events)
	if _context.events_have(result.events, &"destination_trigger_recheck_requested"):
		var requested_map := _context.content.world.map_by_id(_context.state.party.map_id)
		if requested_map == null:
			_context.session_continuation.clear()
			return SessionCoordinatorResult.failed(&"invalid_teleport", "Destination trigger recheck references an unavailable map.", events)
		_exploration.set_post_move_continuation(requested_map, _context.state.party.coordinate, 1)
		return _exploration.continue_post_move(events)
	if _context.scenario().apply_trigger_destination(trigger, events, continuation.action_point_destination_depth == 0 and not _context.events_have(events, &"party_position_restored")):
		var destination_map := _context.content.world.map_by_id(_context.state.party.map_id)
		_exploration.set_post_move_continuation(destination_map, _context.state.party.coordinate, 1)
		return _exploration.continue_post_move(events)
	continuation.active_trigger_id = ""
	continuation.trigger_index = continuation.trigger_ids.size()
	return null


func _debug_continuation(map: MapDefinition, trigger: TriggerDefinition) -> ExplorationContinuationBody:
	var continuation := ExplorationContinuationBody.new()
	continuation.map_id = map.id
	continuation.coordinate = trigger.coordinate
	continuation.trigger_ids = [trigger.id]
	continuation.trigger_index = 0
	continuation.active_trigger_id = ""
	continuation.random_region_ids = []
	continuation.random_region_index = -1
	continuation.active_random_program_id = ""
	continuation.active_random_region_id = ""
	continuation.random_battle_stage = &""
	continuation.action_point_destination_depth = 0
	return continuation
