class_name ClassicWorldTimeOpcodeHandler
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng) -> void:
	_content = content
	_game_state = game_state
	_rng = rng


func opcode_ids() -> Array[int]:
	return [-23, 12, 13, 20, 23, 29, 37, 45, 47, 61, 63, 66, 76, 101, 103, 104, 106]


func execute(action: ClassicActionDefinition, request_id: String, context: Dictionary) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		-23, 23:
			return _mutate_random_region(action, action.opcode == -23)
		12:
			return _mutate_tile(action)
		13:
			return _mutate_triggers(action)
		20:
			return _move_between_maps(action, false, true)
		29:
			return _acquire_player_map(action, request_id)
		37:
			return _move_between_maps(action, true)
		45:
			return _move_between_maps(action, false, false)
		47:
			var quest_id := absi(action.operand_id)
			if not _game_state.set_quest_value(quest_id, 0 if action.operand_id < 0 else 1):
				return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 47 references quest %d outside 0 through 99." % quest_id)
			return ScenarioRuntimeOperationResult.completed(_game_state.quest_value(quest_id), [DomainEvent.new(&"quest_changed", {"questId": quest_id, "value": _game_state.quest_value(quest_id)})])
		61:
			return _shift_party(action)
		63:
			return _alter_game_time(action)
		66:
			_game_state.camping_allowed = action.operand_id == 0
			return ScenarioRuntimeOperationResult.completed(_game_state.camping_allowed, [DomainEvent.new(&"camping_availability_changed", {"allowed": _game_state.camping_allowed, "source": "classic"})])
		76:
			return _adjust_quest_value(action)
		101:
			return _back_up_party()
		103:
			return _test_or_set_party_mode(action)
		104:
			_game_state.random_encounters_enabled = action.operand_id != 0
			return ScenarioRuntimeOperationResult.completed(_game_state.random_encounters_enabled, [DomainEvent.new(&"random_encounters_changed", {"enabled": _game_state.random_encounters_enabled})])
		106:
			return _set_map_darkness(action)
	return super.execute(action, request_id, context)


func _acquire_player_map(action: ClassicActionDefinition, request_id: String) -> ScenarioRuntimeOperationResult:
	var classic_id := absi(action.operand_id)
	var definition := _content.world.player_map_by_classic_id(classic_id)
	if definition == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_player_map", "Classic opcode 29 references unavailable player-map record %d." % classic_id)
	var already_acquired: bool = _game_state.world.has_map(definition.id)
	_game_state.world.acquire_map(definition.id)
	var events: Array[DomainEvent] = [DomainEvent.new(&"player_map_acquired", {"playerMapId": definition.id, "classicId": definition.classic_id, "name": definition.name, "alreadyAcquired": already_acquired, "source": "classic"})]
	if action.operand_id >= 0:
		events.append(DomainEvent.new(&"message_shown", {"text": "You gain a map, to view the map use Maps/Notes in the Menu.", "source": "classic-player-map"}))
		return ScenarioRuntimeOperationResult.completed(definition.id, events)
	var request := InteractionRequest.from_payload(request_id, &"acknowledge", {"prompt": definition.name, "presentation": "player-map", "playerMapId": definition.id})
	return ScenarioRuntimeOperationResult.waiting(request, ScenarioRuntimeContinuation.player_map(definition.id), events)


func _move_between_maps(action: ClassicActionDefinition, dungeon_move: bool, activate_destination: bool = false) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic map movement requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic map movement requires the party's current map.")
	var target_type := (&"dungeon" if action.extra_code[0] == 0 else &"land") if dungeon_move else current_map.level_type
	var map_index := action.extra_code[1] if dungeon_move else current_map.level_index if action.extra_code[0] < 0 else action.extra_code[0]
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[3]) if dungeon_move else Vector2i(_game_state.party.coordinate.x if action.extra_code[1] < 0 else action.extra_code[1], _game_state.party.coordinate.y if action.extra_code[2] < 0 else action.extra_code[2])
	var target_map := _content.world.map_by_type_and_index(target_type, map_index)
	if target_map == null or target_map.topology.cell_at(coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"invalid_teleport", "Classic map movement references an unavailable destination.")
	var source_map_id := _game_state.party.map_id
	var source_coordinate := _game_state.party.coordinate
	_game_state.party.map_id = target_map.id
	_game_state.party.coordinate = coordinate
	_game_state.world.mark_visited(target_map.id, coordinate)
	var sound_id := action.extra_code[4] if dungeon_move else action.extra_code[3]
	var message_id := 0 if dungeon_move else action.extra_code[4]
	var events: Array[DomainEvent] = [DomainEvent.new(&"party_teleported", {"sourceMapId": source_map_id, "sourceX": source_coordinate.x, "sourceY": source_coordinate.y, "mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "soundId": sound_id, "messageId": message_id, "source": "classic"})]
	if sound_id != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": sound_id, "source": "classic-teleport"}))
	if message_id != 0:
		var message := _content.message_by_id(absi(message_id))
		if message == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic teleport references unavailable message %d." % message_id)
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-teleport"}))
	if activate_destination:
		events.append(DomainEvent.new(&"destination_trigger_recheck_requested", {"mapId": target_map.id, "x": coordinate.x, "y": coordinate.y, "source": "classic-opcode-20"}))
		return ScenarioRuntimeOperationResult.completed(target_map.id, events, ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.completed(target_map.id, events)


func _mutate_random_region(action: ClassicActionDefinition, dungeon: bool) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic random-region mutation requires a five-value Extra Code row.")
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic random-region mutation references unavailable map %d." % action.extra_code[0])
	var region := map.random_region_by_index(action.extra_code[1])
	if region == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_random_region", "Classic random-region mutation references unavailable rectangle %d." % action.extra_code[1])
	var previous := _game_state.world.random_region(region)
	var battle_min := previous.battle_minimum if action.extra_code[3] < 0 else action.extra_code[3]
	var battle_max := previous.battle_maximum if action.extra_code[4] < 0 else action.extra_code[4]
	var updated := RandomRegionState.new(region.id, action.extra_code[2], battle_min, battle_max, previous.random_door_percents())
	_game_state.world.set_random_region(updated)
	return ScenarioRuntimeOperationResult.completed(updated.id, [DomainEvent.new(&"random_region_changed", {"regionId": updated.id, "chanceTenThousand": updated.chance_ten_thousand, "battleMinimum": updated.battle_minimum, "battleMaximum": updated.battle_maximum})])


func _mutate_tile(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 12 requires a five-value Extra Code row.")
	var dungeon := action.extra_code[4] != 0
	var map := _content.world.map_by_type_and_index(&"dungeon" if dungeon else &"land", action.extra_code[0])
	var coordinate := Vector2i(action.extra_code[2], action.extra_code[1]) if dungeon else Vector2i(action.extra_code[1], action.extra_code[2])
	if map == null or map.topology.cell_at(coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map_cell", "Classic tile mutation references an unavailable map cell.")
	var terrain_id := "classic.terrain.%d" % action.extra_code[3]
	_game_state.world.replace_terrain(map.id, coordinate, terrain_id)
	return ScenarioRuntimeOperationResult.completed(terrain_id, [DomainEvent.new(&"tile_replaced", {"mapId": map.id, "x": coordinate.x, "y": coordinate.y, "terrainId": terrain_id, "source": "classic"})])


func _mutate_triggers(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 13 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 13 requires the party's current map.")
	var level_type := current_map.level_type
	if action.extra_code[3] < 0:
		level_type = &"dungeon"
	elif action.extra_code[3] > 0:
		level_type = &"land"
	var map := _content.world.map_by_type_and_index(level_type, action.extra_code[0])
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic trigger mutation references unavailable map %d." % action.extra_code[0])
	var record_indexes: Array[int] = []
	if action.extra_code[1] != 0:
		record_indexes.append(action.extra_code[1])
	if action.extra_code[3] != 0:
		for record_index: int in range(absi(action.extra_code[3]), absi(action.extra_code[4]) + 1):
			if not record_indexes.has(record_index):
				record_indexes.append(record_index)
	var changed: Array[String] = []
	for record_index: int in record_indexes:
		var trigger := _content.trigger_by_map_record(map.id, record_index)
		if trigger == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_trigger", "Classic trigger mutation references unavailable record %d on map '%s'." % [record_index, map.id])
		_game_state.world.set_trigger_chance(trigger.id, action.extra_code[2])
		changed.append(trigger.id)
	return ScenarioRuntimeOperationResult.completed(changed, [DomainEvent.new(&"trigger_chances_changed", {"triggerIds": changed, "chancePercent": action.extra_code[2]})])


func _shift_party(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 61 requires a five-value Extra Code row.")
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 61 requires the party's current map.")
	var delta := Vector2i(action.extra_code[1], action.extra_code[2])
	var random_shift := action.extra_code[3] != 0
	if random_shift:
		if action.extra_code[1] < 1 or action.extra_code[2] < 1:
			return ScenarioRuntimeOperationResult.failed(&"invalid_shift_range", "Classic opcode 61 random shift ranges must be positive.")
		var x_sign := 1 if _rng.draw(100, &"classic.opcode61.x-sign") < 50 else -1
		var x_magnitude := _rng.draw_between(1, action.extra_code[1], &"classic.opcode61.x-magnitude")
		var y_sign := 1 if _rng.draw(100, &"classic.opcode61.y-sign") < 50 else -1
		var y_magnitude := _rng.draw_between(1, action.extra_code[2], &"classic.opcode61.y-magnitude")
		delta = Vector2i(x_sign * x_magnitude, y_sign * y_magnitude)
	var source_coordinate := _game_state.party.coordinate
	var target_coordinate := source_coordinate + delta
	if current_map.topology.cell_at(target_coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"shift_out_of_bounds", "Classic opcode 61 shifts the party outside the current map.")
	_game_state.party.coordinate = target_coordinate
	_game_state.world.mark_visited(current_map.id, target_coordinate)
	return ScenarioRuntimeOperationResult.completed(target_coordinate, [DomainEvent.new(&"party_shifted", {
		"mapId": current_map.id,
		"sourceX": source_coordinate.x,
		"sourceY": source_coordinate.y,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"deltaX": delta.x,
		"deltaY": delta.y,
		"random": random_shift,
		"source": "classic",
	})])


func _alter_game_time(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 4:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 63 requires a five-value Extra Code row.")
	var mode := action.extra_code[0]
	var target_minutes := _game_state.clock.total_minutes()
	match mode:
		1:
			var day := _game_state.clock.day() if action.extra_code[1] == -1 else action.extra_code[1]
			var hour := _game_state.clock.hour() if action.extra_code[2] == -1 else action.extra_code[2]
			var minute := _game_state.clock.minute() if action.extra_code[3] == -1 else action.extra_code[3]
			if day < 1 or hour < 0 or hour > 23 or minute < 0 or minute > 59:
				return ScenarioRuntimeOperationResult.failed(&"invalid_game_time", "Classic opcode 63 absolute time is outside the Realmz clock.")
			target_minutes = (day - 1) * RealmzClock.MINUTES_PER_DAY + hour * 60 + minute
		2:
			target_minutes += action.extra_code[1] * RealmzClock.MINUTES_PER_DAY + action.extra_code[2] * 60 + action.extra_code[3]
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_game_time_mode", "Classic opcode 63 requires set or offset mode.")
	if not _game_state.clock.set_total_minutes(target_minutes):
		return ScenarioRuntimeOperationResult.failed(&"invalid_game_time", "Classic opcode 63 cannot move before the start of the Realmz clock.")
	return ScenarioRuntimeOperationResult.completed(target_minutes, [DomainEvent.new(&"game_time_changed", {
		"mode": mode,
		"day": _game_state.clock.day(),
		"hour": _game_state.clock.hour(),
		"minute": _game_state.clock.minute(),
		"totalMinutes": target_minutes,
		"source": "classic",
	})])


func _adjust_quest_value(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 76 requires a five-value Extra Code row.")
	var quest_id := action.extra_code[0]
	if quest_id < 0 or quest_id >= 100:
		return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 76 references quest %d outside 0 through 99." % quest_id)
	var value := clampi(_game_state.quest_value(quest_id) + action.extra_code[1], -127, 127)
	_game_state.set_quest_value(quest_id, value)
	var event := DomainEvent.new(&"quest_value_changed", {"questId": quest_id, "value": value, "delta": action.extra_code[1], "source": "classic"})
	if action.extra_code[3] == 0 or value < action.extra_code[3]:
		return ScenarioRuntimeOperationResult.completed(value, [event])
	if action.extra_code[2] != 1:
		return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic opcode 76 auto-branch target type %d is unavailable." % action.extra_code[2])
	var branch := ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_xap(action.extra_code[4], action.gosub))
	branch.events.append(event)
	return branch


func _back_up_party() -> ScenarioRuntimeOperationResult:
	var current_map := _content.world.map_by_id(_game_state.party.map_id)
	if current_map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 101 requires the party's current map.")
	if current_map.level_type == &"dungeon":
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"party_backup_ignored", {"reason": "dungeon", "source": "classic"})])
	if _game_state.last_move_direction == Vector2i.ZERO:
		return ScenarioRuntimeOperationResult.failed(&"missing_move_direction", "Classic opcode 101 requires a prior party movement direction.")
	var source_coordinate := _game_state.party.coordinate
	var target_coordinate := source_coordinate - _game_state.last_move_direction
	if current_map.topology.cell_at(target_coordinate) == null:
		return ScenarioRuntimeOperationResult.failed(&"backup_out_of_bounds", "Classic opcode 101 backs the party outside the current map.")
	_game_state.party.coordinate = target_coordinate
	_game_state.world.mark_visited(current_map.id, target_coordinate)
	return ScenarioRuntimeOperationResult.completed(target_coordinate, [DomainEvent.new(&"party_backed_up", {
		"mapId": current_map.id,
		"sourceX": source_coordinate.x,
		"sourceY": source_coordinate.y,
		"x": target_coordinate.x,
		"y": target_coordinate.y,
		"directionX": _game_state.last_move_direction.x,
		"directionY": _game_state.last_move_direction.y,
		"source": "classic",
	})])


func _set_map_darkness(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 2:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 106 requires a five-value Extra Code row.")
	if action.extra_code[0] not in [1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_darkness", "Classic opcode 106 darkness value must be 1 or 2.")
	var map := _content.world.map_by_id(_game_state.party.map_id)
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 106 requires the party's current map.")
	var dark := action.extra_code[0] == 2
	var unchanged := _game_state.world.map_is_dark(map) == dark
	if unchanged and action.extra_code[1] != 0:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"map_darkness_unchanged", {"mapId": map.id, "dark": dark})], ScenarioVmDirective.finish())
	_game_state.world.set_map_darkness(map.id, dark)
	return ScenarioRuntimeOperationResult.completed(dark, [DomainEvent.new(&"map_darkness_changed", {"mapId": map.id, "dark": dark, "source": "classic"})])


func _test_or_set_party_mode(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 3:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 103 requires a five-value Extra Code row.")
	if action.extra_code[0] not in [0, 1, 2] or action.extra_code[1] not in [0, 1, 2] or action.extra_code[2] not in [0, 1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_party_mode", "Classic opcode 103 has an invalid boat or camping mode.")
	var should_finish := action.extra_code[0] == 1 and not _game_state.party_in_boat or action.extra_code[0] == 2 and _game_state.party_in_boat
	should_finish = should_finish or action.extra_code[1] == 1 and not _game_state.party_camping or action.extra_code[1] == 2 and _game_state.party_camping
	if action.extra_code[2] == 1:
		_game_state.party_in_boat = true
	elif action.extra_code[2] == 2:
		_game_state.party_in_boat = false
	var event := DomainEvent.new(&"party_mode_checked", {"inBoat": _game_state.party_in_boat, "camping": _game_state.party_camping, "finished": should_finish, "source": "classic"})
	return ScenarioRuntimeOperationResult.completed(not should_finish, [event], ScenarioVmDirective.finish() if should_finish else null)
