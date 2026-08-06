class_name GameSession
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _scenario_vm: ScenarioVm
var _scenario_action_state: ScenarioActionState
var _runtime_api: RealmzRuntimeApi
var _session_continuation: Dictionary = {}
var _started: bool = false
var _view_revision: int = 0


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_view_revision, &"session_already_started", "The session has already started.")
	if content == null or content.scenario == null:
		return SessionStep.failed(_view_revision, &"invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_view_revision, &"invalid_start_location", "The package start location is unavailable.")
	var starting_characters: Array[CharacterState] = [CharacterState.new("party.starting.adventurer", "Adventurer", 10, 10)]
	var game_state := GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, starting_characters), RealmzClock.new())
	game_state.world.mark_visited(content.start_map_id, content.start_coordinate)
	var random_source := RealmzRng.new(initial_seed)
	var action_state := ScenarioActionState.new()
	var scenario_vm := ScenarioVm.new()
	scenario_vm.configure(content.scenario)
	_content = content
	_state = game_state
	_rng = random_source
	_scenario_action_state = action_state
	_scenario_vm = scenario_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state)
	_session_continuation.clear()
	_started = true
	_view_revision = 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SaveEnvelope) -> SessionStep:
	if content == null or content.scenario == null or save_envelope == null:
		return SessionStep.failed(_view_revision, &"invalid_restore", "Validated content and save data are required.")
	if save_envelope.campaign_id != content.campaign_id or save_envelope.package_hash != content.package_hash:
		return SessionStep.failed(_view_revision, &"package_mismatch", "The save belongs to a different package build.")
	if save_envelope.rules_version != content.rules_version:
		return SessionStep.failed(_view_revision, &"rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(save_envelope.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(save_envelope.game_state.party.coordinate) == null:
		return SessionStep.failed(_view_revision, &"invalid_saved_location", "The saved party location is unavailable.")
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(save_envelope.rng_state):
		return SessionStep.failed(_view_revision, &"invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(save_envelope.game_state.to_data())
	var replacement_action_state := ScenarioActionState.from_data(save_envelope.scenario_action_state.to_data())
	if replacement_state == null or replacement_action_state == null:
		return SessionStep.failed(_view_revision, &"invalid_game_state", "The saved game or Scenario Action state is invalid.")
	var replacement_vm := ScenarioVm.new()
	replacement_vm.configure(content.scenario)
	if not replacement_vm.restore(save_envelope.scenario_vm):
		return SessionStep.failed(_view_revision, &"invalid_vm_state", "The saved Scenario VM state is invalid.")
	var replacement_continuation := save_envelope.session_continuation.duplicate(true)
	if not replacement_continuation.is_empty() and (replacement_vm.pending_request() == null or not _valid_session_continuation(content, replacement_state, replacement_continuation)):
		return SessionStep.failed(_view_revision, &"invalid_session_continuation", "The saved session continuation is invalid.")
	_content = content
	_state = replacement_state
	_rng = replacement_rng
	_scenario_action_state = replacement_action_state
	_scenario_vm = replacement_vm
	_runtime_api = RealmzRuntimeApi.new(_content, _state, _rng, _scenario_action_state)
	_session_continuation = replacement_continuation
	_view_revision = save_envelope.view_revision
	_started = true
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_restored")])


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	if _scenario_vm.pending_request() != null or _scenario_vm.is_active():
		return SessionStep.failed(_view_revision, &"interaction_pending", "Respond to the pending interaction first.")
	if intent == null:
		return SessionStep.failed(_view_revision, &"invalid_intent", "A typed player intent is required.")
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			return _move(intent.direction)
		PlayerIntent.Kind.SEARCH:
			return _search()
		_:
			return SessionStep.failed(_view_revision, &"intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func respond(response: InteractionResponse) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, &"session_not_started", "Start or restore the session first.")
	var pending := _scenario_vm.pending_request()
	if pending == null:
		return SessionStep.failed(_view_revision, &"no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != pending.request_id:
		return SessionStep.failed(_view_revision, &"interaction_mismatch", "The response does not match the pending request.")
	var result := _scenario_vm.resume(response, _runtime_api)
	var events: Array[DomainEvent] = []
	events.append_array(result.events)
	if result.state == ScenarioVmResult.State.WAITING:
		return _finish_waiting(result.interaction, events)
	if result.state == ScenarioVmResult.State.FAILED:
		_session_continuation.clear()
		return _finish_failed(result.error_code, result.error_message, events)
	if not _session_continuation.is_empty():
		return _continue_post_move(events)
	return _finish_completed(events)


func view() -> GameView:
	if not _started:
		return GameView.new(_view_revision, false, null)
	return GameView.new(_view_revision, true, _scenario_vm.pending_request(), _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour(), _build_map_view())


func snapshot() -> SaveEnvelope:
	if not _started or (_scenario_vm.is_active() and _scenario_vm.pending_request() == null):
		return null
	var envelope := SaveEnvelope.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, _state, _rng.snapshot(), _scenario_vm.snapshot(), _scenario_action_state, _session_continuation)
	return SaveEnvelope.from_data(envelope.to_data())


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


func scenario_trace() -> Array[Dictionary]:
	return [] if _scenario_vm == null else _scenario_vm.trace()


func _search() -> SessionStep:
	_state.mark_searched(_state.party.map_id, _state.party.coordinate)
	var current_map := _content.world.map_by_id(_state.party.map_id)
	var discovered: Array[String] = []
	var first_roll: int = 0
	for cell: MapCell in current_map.topology.cells():
		if absi(cell.coordinate.x - _state.party.coordinate.x) > 1 or absi(cell.coordinate.y - _state.party.coordinate.y) > 1:
			continue
		for feature: MapFeature in cell.features():
			if feature.kind != &"secret" or _state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
				continue
			var roll := _rng.draw(100, StringName("exploration.search.%s" % feature.id))
			if first_roll == 0:
				first_roll = roll
			if roll <= 100:
				_state.world.discover_secret(feature.id)
				discovered.append(feature.id)
	_state.clock.advance_minutes(1)
	var events: Array[DomainEvent] = [DomainEvent.new("search_completed", {"mapId": _state.party.map_id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "roll": first_roll, "discoveredSecrets": discovered})]
	for secret_id: String in discovered:
		events.append(DomainEvent.new("secret_discovered", {"secretId": secret_id}))
	return _finish_completed(events)


func _move(direction: Vector2i) -> SessionStep:
	if direction not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return SessionStep.failed(_view_revision, &"invalid_direction", "Movement requires one cardinal direction.")
	var source_map := _content.world.map_by_id(_state.party.map_id)
	var target_map := source_map
	var target_coordinate := _state.party.coordinate + direction
	var transition: MapTransition = null
	if not source_map.topology.contains(target_coordinate):
		transition = _content.world.transition_from(source_map.id, MapTopology.direction_name(direction))
		if transition == null:
			return _movement_blocked(&"map_boundary")
		target_map = _content.world.map_by_id(transition.target_map_id)
		target_coordinate = _content.world.transition_target_coordinate(transition, _state.party.coordinate)
	var probe := target_map.topology.probe_entry(target_coordinate, direction, _state.world)
	if not probe.allowed:
		return _movement_blocked(probe.reason)
	var events: Array[DomainEvent] = []
	if not probe.door_id.is_empty() and not _state.world.door_is_open(probe.door_id):
		_state.world.open_door(probe.door_id)
		events.append(DomainEvent.new("door_opened", {"doorId": probe.door_id}))
	if not probe.secret_id.is_empty() and not _state.world.secret_is_discovered(probe.secret_id):
		_state.world.discover_secret(probe.secret_id)
		events.append(DomainEvent.new("secret_discovered", {"secretId": probe.secret_id, "byMovement": true}))
	var source_map_id := _state.party.map_id
	var source_coordinate := _state.party.coordinate
	_state.party.map_id = target_map.id
	_state.party.coordinate = target_coordinate
	_state.world.mark_visited(target_map.id, target_coordinate)
	_state.clock.advance_minutes(probe.target_cell.movement_cost)
	events.append(DomainEvent.new("party_moved", {"fromMapId": source_map_id, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": target_map.id, "x": target_coordinate.x, "y": target_coordinate.y}))
	if transition != null:
		events.append(DomainEvent.new("map_transitioned", {"transitionId": transition.id, "sourceMapId": source_map_id, "targetMapId": target_map.id}))
	_session_continuation = {
		"kind": "post-move",
		"mapId": target_map.id,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"triggerIds": probe.target_cell.trigger_ids(),
		"triggerIndex": 0,
		"activeTriggerId": "",
	}
	return _continue_post_move(events)


func _continue_post_move(events: Array[DomainEvent]) -> SessionStep:
	var map := _content.world.map_by_id(String(_session_continuation.get("mapId", "")))
	var coordinate := Vector2i(int(_session_continuation.get("x", -1)), int(_session_continuation.get("y", -1)))
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null:
		_session_continuation.clear()
		return _finish_failed(&"invalid_session_continuation", "Post-movement topology continuation is unavailable.", events)
	var active_trigger_id := String(_session_continuation.get("activeTriggerId", ""))
	if not active_trigger_id.is_empty():
		var completed_trigger := _content.trigger_by_id(active_trigger_id)
		if completed_trigger == null:
			_session_continuation.clear()
			return _finish_failed(&"invalid_session_continuation", "Completed trigger continuation is unavailable.", events)
		_apply_trigger_replacement(map, completed_trigger, events)
		_session_continuation["activeTriggerId"] = ""
		_session_continuation["triggerIndex"] = int(_session_continuation["triggerIndex"]) + 1
	var trigger_ids: Array = _session_continuation["triggerIds"]
	while int(_session_continuation["triggerIndex"]) < trigger_ids.size():
		var trigger_index: int = int(_session_continuation["triggerIndex"])
		var trigger_id: String = String(trigger_ids[trigger_index])
		var trigger := _content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _state.world.trigger_is_disabled(trigger_id):
			_session_continuation["triggerIndex"] = trigger_index + 1
			continue
		if trigger.chance_percent < 100:
			var chance_roll := _rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger.chance_percent:
				_session_continuation["triggerIndex"] = trigger_index + 1
				continue
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		_session_continuation["activeTriggerId"] = trigger.id
		var started := _scenario_vm.start_program(trigger.program_id, {"callingContext": "action", "triggerId": trigger.id, "mapId": map.id, "x": coordinate.x, "y": coordinate.y})
		if started.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(started.error_code, started.error_message, events)
		var result := _scenario_vm.run(_runtime_api)
		events.append_array(result.events)
		if result.state == ScenarioVmResult.State.WAITING:
			return _finish_waiting(result.interaction, events)
		if result.state == ScenarioVmResult.State.FAILED:
			_session_continuation.clear()
			return _finish_failed(result.error_code, result.error_message, events)
		_apply_trigger_replacement(map, trigger, events)
		_session_continuation["activeTriggerId"] = ""
		_session_continuation["triggerIndex"] = trigger_index + 1
	_check_random_regions(map, cell, events)
	_session_continuation.clear()
	return _finish_completed(events)


func _apply_trigger_replacement(map: MapDefinition, trigger: TriggerDefinition, events: Array[DomainEvent]) -> void:
	if trigger.replacement == null or not trigger.replacement.changes_terrain():
		return
	var replacement_cell := map.topology.cell_at(trigger.replacement.target_coordinate)
	if replacement_cell == null:
		return
	var terrain_id := "classic.terrain.%d" % trigger.replacement.terrain_id
	_state.world.replace_terrain(map.id, replacement_cell.coordinate, terrain_id)
	events.append(DomainEvent.new("tile_replaced", {"mapId": map.id, "x": replacement_cell.coordinate.x, "y": replacement_cell.coordinate.y, "terrainId": terrain_id}))


func _movement_blocked(reason: StringName) -> SessionStep:
	return _finish_completed([DomainEvent.new("movement_blocked", {"reason": String(reason)})])


func _check_random_regions(map: MapDefinition, cell: MapCell, events: Array[DomainEvent]) -> void:
	for region_id: String in cell.random_rect_ids():
		var region := map.random_region_by_id(region_id)
		if region == null or region.chance_percent <= 0:
			continue
		var triggered := region.chance_percent >= 100
		var roll := 0
		if not triggered:
			roll = _rng.draw(100, StringName("random-region.%s" % region.id))
			triggered = roll <= region.chance_percent
		events.append(DomainEvent.new("random_encounter_checked", {"regionId": region.id, "roll": roll, "chancePercent": region.chance_percent, "triggered": triggered}))
		if triggered:
			events.append(DomainEvent.new("random_encounter_triggered", {"regionId": region.id, "battleMinimum": region.battle_minimum, "battleMaximum": region.battle_maximum, "textId": region.text_id, "soundId": region.sound_id}))


func _finish_completed(events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.completed(_view_revision, events)


func _finish_waiting(request: InteractionRequest, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.waiting(_view_revision, request, events)


func _finish_failed(code: StringName, message: String, events: Array[DomainEvent]) -> SessionStep:
	_view_revision += 1
	return SessionStep.failed(_view_revision, code, message, events)


static func _valid_session_continuation(content: RealmzContent, state: GameState, continuation: Dictionary) -> bool:
	var fields: Array[String] = ["kind", "mapId", "x", "y", "triggerIds", "triggerIndex", "activeTriggerId"]
	if continuation.size() != fields.size():
		return false
	for field: String in fields:
		if not continuation.has(field):
			return false
	if continuation["kind"] != "post-move" or not continuation["mapId"] is String or not continuation["x"] is int or not continuation["y"] is int or not continuation["triggerIds"] is Array or not continuation["triggerIndex"] is int or not continuation["activeTriggerId"] is String:
		return false
	var map := content.world.map_by_id(continuation["mapId"])
	var coordinate := Vector2i(continuation["x"], continuation["y"])
	var cell: MapCell = null if map == null else map.topology.cell_at(coordinate)
	if cell == null or state.party.map_id != map.id or state.party.coordinate != coordinate or continuation["triggerIds"] != cell.trigger_ids():
		return false
	var index: int = continuation["triggerIndex"]
	if index < 0 or index >= continuation["triggerIds"].size() or continuation["activeTriggerId"].is_empty() or continuation["triggerIds"][index] != continuation["activeTriggerId"]:
		return false
	return content.trigger_by_id(continuation["activeTriggerId"]) != null


func _build_map_view() -> MapView:
	var map := _content.world.map_by_id(_state.party.map_id)
	var visible_coordinates := map.topology.visible_cells(_state.party.coordinate, 8, _state.world, map.uses_los)
	var visible: Dictionary = {}
	for coordinate: Vector2i in visible_coordinates:
		visible[coordinate] = true
	var cells: Array[MapCellView] = []
	for cell: MapCell in map.topology.cells():
		var feature_kinds: Array[StringName] = []
		var edge_kinds: Dictionary = {}
		var edge_passability: Dictionary = {}
		for direction: StringName in [&"north", &"east", &"south", &"west"]:
			var edge := cell.edge(direction)
			edge_kinds[direction] = edge.kind
			edge_passability[direction] = edge.passable
		var hidden_secret := false
		for feature: MapFeature in cell.features():
			if feature.kind == &"secret" and not _state.world.secret_is_discovered(feature.id, feature.initial_state == &"revealed"):
				hidden_secret = true
				continue
			if not feature_kinds.has(feature.kind):
				feature_kinds.append(feature.kind)
		var can_enter := cell.passable and not hidden_secret
		cells.append(MapCellView.new(cell.coordinate, _state.world.terrain_for(map.id, cell), can_enter, cell.blocks_los, visible.has(cell.coordinate), _state.world.was_visited(map.id, cell.coordinate), not hidden_secret and not cell.trigger_ids().is_empty(), not cell.random_rect_ids().is_empty(), feature_kinds, edge_kinds, edge_passability))
	return MapView.new(map.id, map.name, map.level_type, map.topology.width, map.topology.height, _state.party.coordinate, cells)
