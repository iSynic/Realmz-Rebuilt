class_name GameSession
extends RefCounted

var _content: RealmzContent
var _state: GameState
var _rng: RealmzRng
var _started: bool = false
var _view_revision: int = 0
var _pending_interaction: InteractionRequest


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_view_revision, "session_already_started", "The session has already started.")
	if content == null:
		return SessionStep.failed(_view_revision, "invalid_content", "Validated Realmz content is required.")
	var start_map := content.world.map_by_id(content.start_map_id)
	if start_map == null or start_map.topology.cell_at(content.start_coordinate) == null:
		return SessionStep.failed(_view_revision, "invalid_start_location", "The package start location is unavailable.")
	_content = content
	var starting_characters: Array[CharacterState] = [CharacterState.new("party.starting.adventurer", "Adventurer", 10, 10)]
	_state = GameState.new(PartyState.new(content.start_map_id, content.start_coordinate, starting_characters), RealmzClock.new())
	_state.world.mark_visited(content.start_map_id, content.start_coordinate)
	_rng = RealmzRng.new(initial_seed)
	_started = true
	_view_revision = 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_started", {"campaignId": content.campaign_id})])


func restore(content: RealmzContent, save_envelope: SaveEnvelope) -> SessionStep:
	if content == null or save_envelope == null:
		return SessionStep.failed(_view_revision, "invalid_restore", "Validated content and save data are required.")
	if save_envelope.campaign_id != content.campaign_id or save_envelope.package_hash != content.package_hash:
		return SessionStep.failed(_view_revision, "package_mismatch", "The save belongs to a different package build.")
	if save_envelope.rules_version != content.rules_version:
		return SessionStep.failed(_view_revision, "rules_mismatch", "The save uses a different Realmz rules version.")
	var saved_map := content.world.map_by_id(save_envelope.game_state.party.map_id)
	if saved_map == null or saved_map.topology.cell_at(save_envelope.game_state.party.coordinate) == null:
		return SessionStep.failed(_view_revision, "invalid_saved_location", "The saved party location is unavailable.")
	var replacement_rng := RealmzRng.new()
	if not replacement_rng.restore(save_envelope.rng_state):
		return SessionStep.failed(_view_revision, "invalid_rng_state", "The saved random state is invalid.")
	var replacement_state := GameState.from_data(save_envelope.game_state.to_data())
	if replacement_state == null:
		return SessionStep.failed(_view_revision, "invalid_game_state", "The saved game state is invalid.")
	var replacement_interaction: InteractionRequest = null
	if save_envelope.pending_interaction != null:
		replacement_interaction = InteractionRequest.from_data(save_envelope.pending_interaction.to_data())
		if replacement_interaction == null:
			return SessionStep.failed(_view_revision, "invalid_interaction_state", "The pending interaction is invalid.")
	_content = content
	_state = replacement_state
	_rng = replacement_rng
	_pending_interaction = replacement_interaction
	_view_revision = save_envelope.view_revision
	_started = true
	return SessionStep.completed(_view_revision, [DomainEvent.new("session_restored")])


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, "session_not_started", "Start or restore the session first.")
	if _pending_interaction != null:
		return SessionStep.failed(_view_revision, "interaction_pending", "Respond to the pending interaction first.")
	if intent == null:
		return SessionStep.failed(_view_revision, "invalid_intent", "A typed player intent is required.")
	match intent.kind:
		PlayerIntent.Kind.MOVE:
			return _move(intent.direction)
		PlayerIntent.Kind.SEARCH:
			return _search()
		_:
			return SessionStep.failed(_view_revision, "intent_not_implemented", "This Realmz intent is not implemented in the current slice.")


func respond(response: InteractionResponse) -> SessionStep:
	if _pending_interaction == null:
		return SessionStep.failed(_view_revision, "no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != _pending_interaction.request_id:
		return SessionStep.failed(_view_revision, "interaction_mismatch", "The response does not match the pending request.")
	_pending_interaction = null
	_view_revision += 1
	return SessionStep.completed(_view_revision)


func view() -> GameView:
	if not _started:
		return GameView.new(_view_revision, false, _pending_interaction)
	return GameView.new(_view_revision, true, _pending_interaction, _state.party.map_id, _state.party.coordinate, _state.clock.day(), _state.clock.hour(), _build_map_view())


func snapshot() -> SaveEnvelope:
	if not _started:
		return null
	var envelope := SaveEnvelope.new(_content.campaign_id, _content.package_hash, _content.rules_version, _view_revision, _state, _rng.snapshot(), _pending_interaction)
	return SaveEnvelope.from_data(envelope.to_data())


func rng_trace() -> Array[Dictionary]:
	return [] if _rng == null else _rng.trace()


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
	_view_revision += 1
	var events: Array[DomainEvent] = [DomainEvent.new("search_completed", {"mapId": _state.party.map_id, "x": _state.party.coordinate.x, "y": _state.party.coordinate.y, "roll": first_roll, "discoveredSecrets": discovered})]
	for secret_id: String in discovered:
		events.append(DomainEvent.new("secret_discovered", {"secretId": secret_id}))
	return SessionStep.completed(_view_revision, events)


func _move(direction: Vector2i) -> SessionStep:
	if direction not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		return SessionStep.failed(_view_revision, "invalid_direction", "Movement requires one cardinal direction.")
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
	_execute_cell_triggers(target_map, probe.target_cell, events)
	_check_random_regions(target_map, probe.target_cell, events)
	_view_revision += 1
	return SessionStep.completed(_view_revision, events)


func _movement_blocked(reason: StringName) -> SessionStep:
	_view_revision += 1
	return SessionStep.completed(_view_revision, [DomainEvent.new("movement_blocked", {"reason": String(reason)})])


func _execute_cell_triggers(map: MapDefinition, cell: MapCell, events: Array[DomainEvent]) -> void:
	for trigger_id: String in cell.trigger_ids():
		var trigger := _content.trigger_by_id(trigger_id)
		if trigger == null or not trigger.active or _state.world.trigger_is_disabled(trigger_id):
			continue
		if trigger.chance_percent < 100:
			var chance_roll := _rng.draw(100, StringName("trigger.%s" % trigger.id))
			if chance_roll > trigger.chance_percent:
				continue
		events.append(DomainEvent.new("trigger_fired", {"triggerId": trigger.id}))
		for action: ClassicActionDefinition in trigger.actions():
			if action.opcode == 1:
				var message := _content.message_by_id(action.operand_id)
				events.append(DomainEvent.new("message_shown", {"triggerId": trigger.id, "messageId": action.operand_id, "text": message.text}))
		if trigger.replacement != null and trigger.replacement.changes_terrain():
			var replacement_cell := map.topology.cell_at(trigger.replacement.target_coordinate)
			if replacement_cell != null:
				var terrain_id := "classic.terrain.%d" % trigger.replacement.terrain_id
				_state.world.replace_terrain(map.id, replacement_cell.coordinate, terrain_id)
				events.append(DomainEvent.new("tile_replaced", {"mapId": map.id, "x": replacement_cell.coordinate.x, "y": replacement_cell.coordinate.y, "terrainId": terrain_id}))


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
