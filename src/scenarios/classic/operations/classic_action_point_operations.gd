## Owns selected-AP admission, default removal and native header completion.
class_name ClassicActionPointOperations
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _shared: ClassicExecutionState


func _init(content: RealmzContent, state: GameState, rng: RealmzRng, shared: ClassicExecutionState) -> void:
	_content = content
	_state = state
	_rng = rng
	_shared = shared


func begin() -> void:
	_shared.begin_timer(_state.party.map_id, _state.party.coordinate)


func placed_entry_is_valid(id: String, program_id: String) -> bool:
	var trigger := _content.scenario_records.trigger_by_id(id)
	return trigger != null and _shared.trigger_id == id and (program_id.is_empty() or program_id == trigger.program_id)


func remove_selected() -> ScenarioRuntimeOperationResult:
	var id := _shared.trigger_id
	if id.is_empty() or _state.world.triggers.trigger_is_disabled(id): return ScenarioRuntimeOperationResult.completed(false)
	if _content.scenario_records.trigger_by_id(id) == null: return ScenarioRuntimeOperationResult.failed(&"invalid_native_action_point","The selected native Action Point is unavailable.")
	_state.world.triggers.disable_trigger(id)
	return ScenarioRuntimeOperationResult.completed(true,[DomainEvent.new(&"trigger_disabled",{"triggerId":id,"source":"classic-default-one-shot"})])


func recheck(context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var map := _content.world.map_by_id(_state.party.map_id)
	if map == null: return ScenarioRuntimeOperationResult.failed(&"invalid_timed_encounter_location", "The timer's Action Point destination is unavailable.")
	var selected := ClassicActionPointRules.first_placed_trigger_ids(_content, map.topology.cell_at(_state.party.coordinate))
	if selected.is_empty(): return ScenarioRuntimeOperationResult.completed(false, [], ScenarioVmDirective.native_return(0))
	var trigger := _content.scenario_records.trigger_by_id(selected[0])
	_shared.begin_trigger(trigger, true)
	_shared.header_replaced = true
	var program := _content.scenario.program_by_id(trigger.program_id)
	if program == null: return ScenarioRuntimeOperationResult.failed(&"unknown_scenario_program", "The selected native Action Point program is missing.")
	var chance := _state.world.triggers.trigger_chance(trigger.id, trigger.chance_percent)
	var eligible := not _state.world.triggers.trigger_is_disabled(trigger.id) and (trigger.active or _state.world.triggers.trigger_chance_is_overridden(trigger.id)) and chance > 0
	var admitted := eligible and _rng.draw(100, StringName("trigger.%s" % trigger.id)) <= chance
	var target_context := context.for_new_program_frame()
	target_context.trigger_id = trigger.id
	target_context.map_id = map.id
	target_context.coordinate = _state.party.coordinate
	target_context.has_coordinate = true
	var events: Array[DomainEvent] = [DomainEvent.new(&"native_action_point_selected", {"triggerId": trigger.id, "programId": program.id, "admitted": admitted})]
	if admitted: events.append(DomainEvent.new(&"trigger_fired", {"triggerId": trigger.id}))
	return ScenarioRuntimeOperationResult.completed(admitted, events, ScenarioVmDirective.recheck_program(program.id, admitted, target_context))


func complete_invocation(context: ScenarioExecutionContext, suppress_recheck: bool, placed_owner: String = "") -> ScenarioRuntimeOperationResult:
	if _state.combat != null or _shared.map_id.is_empty() or _shared.map_id == _state.party.map_id and _shared.coordinate == _state.party.coordinate:
		return ScenarioRuntimeOperationResult.completed()
	var issuing := _content.scenario_records.trigger_by_id(placed_owner) if not placed_owner.is_empty() else null
	if issuing != null and not _shared.header_replaced and _shared.map_id == issuing.map_id and _shared.coordinate == issuing.coordinate: return ScenarioRuntimeOperationResult.completed()
	var map := _content.world.map_by_id(_shared.map_id)
	# FD-CLOCK-002: retain a typed destination instead of Castle's stale outdoor
	# globals or an unchecked field read when a timer runs inside a dungeon.
	if map == null or map.topology.cell_at(_shared.coordinate) == null:
		return ClassicCompatibility.skip(&"unsafe-timer-header", _shared.map_id, 0)
	var previous_map := _state.party.map_id
	var previous_coordinate := _state.party.coordinate
	_state.party.map_id = map.id
	_state.party.coordinate = _shared.coordinate
	_state.world.exploration.mark_visited(map.id, _shared.coordinate)
	var moved := {"fromMapId":previous_map,"fromX":previous_coordinate.x,"fromY":previous_coordinate.y,"mapId":map.id,"x":_shared.coordinate.x,"y":_shared.coordinate.y,"source":"timed-action-point-header"}
	if issuing != null:
		moved["source"] = "action-point-destination"
		moved["triggerId"] = issuing.id
	var events: Array[DomainEvent] = [DomainEvent.new(&"party_moved", moved)]
	if suppress_recheck or not map.topology.action_point_is_marked(_state.party.coordinate, _state.world, true): return ScenarioRuntimeOperationResult.completed(null, events)
	var result := recheck(context)
	result.events = events + result.events
	return result
