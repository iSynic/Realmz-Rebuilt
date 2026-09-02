class_name ClassicControlFlowOperations
extends ClassicOpcodeHandler

var _content: RealmzContent
var _game_state: GameState
var _rng: RealmzRng


func _init(content: RealmzContent, game_state: GameState, rng: RealmzRng) -> void:
	_content = content
	_game_state = game_state
	_rng = rng


func opcode_ids() -> Array[int]:
	return [7, 8, 24, 25, 42, 46, 58, 59, 64, 72, 77, 78, 84, 85, 86, 98, 99]


func execute(action: ClassicActionDefinition, request_id: String, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		7:
			return replace_scenario_program(action, context)
		8:
			return branch_to_trigger_program(action, context)
		24:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"action_point_kept", {"triggerId": context.trigger_id, "source": "classic"})], ScenarioVmDirective.finish_timeline())
		25:
			var trigger_id := _opcode_25_trigger_id(context)
			var events: Array[DomainEvent] = []
			if not trigger_id.is_empty():
				_game_state.world.disable_trigger(trigger_id)
				events.append(DomainEvent.new(&"trigger_disabled", {"triggerId": trigger_id, "source": "classic"}))
			return ScenarioRuntimeOperationResult.completed(true, events, ScenarioVmDirective.finish_timeline())
		42:
			return _percent_branch(action, context)
		46:
			return _branch_on_quest(action, context)
		58:
			return _branch_on_difficulty(action, context)
		59:
			return _branch_on_faced_tile_source_defect(action, context)
		64:
			return _branch_on_game_time(action)
		72:
			return _branch_on_quest_range(action)
		77:
			return _branch_on_quest_value(action)
		78:
			return _branch_on_faced_tile_semantic(action)
		85:
			return _branch_to_random_destination(action)
		86:
			return _branch_on_misc(action)
		84, 98, 99:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"classic_control_marker", {"opcode": action.opcode, "operandId": action.operand_id})])
	return super.execute(action, request_id, context)


func _percent_branch(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 42 requires a five-value Extra Code row.")
	var roll := _rng.draw(100, &"classic.percent-branch")
	if roll > action.extra_code[0]:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": false})])
	var event := DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": true})
	match action.extra_code[1]:
		-2:
			var trigger_id := context.trigger_id
			if not trigger_id.is_empty():
				_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [event], ScenarioVmDirective.finish())
		1:
			var branch := _branch_from_values(action.extra_code, false, context)
			branch.events.append(event)
			return branch
		2:
			return ScenarioRuntimeOperationResult.completed(true, [event], ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.completed(true, [event])


func _branch_on_difficulty(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 58 requires a five-value Extra Code row.")
	var matched := _game_state.difficulty >= action.extra_code[0]
	var event := DomainEvent.new(&"difficulty_branch_checked", {"difficulty": _game_state.difficulty, "minimum": action.extra_code[0], "matched": matched, "behavior": action.extra_code[1]})
	if not matched:
		return ScenarioRuntimeOperationResult.completed(false, [event])
	match action.extra_code[1]:
		-2:
			if not context.trigger_id.is_empty():
				_game_state.world.disable_trigger(context.trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [event], ScenarioVmDirective.finish_timeline())
		1:
			var branch := _branch_from_values(action.extra_code, action.gosub, context)
			branch.events.append(event)
			return branch
		2:
			return ScenarioRuntimeOperationResult.completed(true, [event, DomainEvent.new(&"action_point_kept", {"triggerId": context.trigger_id, "source": "classic-opcode-58"})], ScenarioVmDirective.finish_timeline())
	return ScenarioRuntimeOperationResult.completed(true, [event])


func _branch_on_faced_tile_source_defect(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 59 requires a five-value Extra Code row.")
	var map := _content.world.map_by_id(_game_state.party.map_id)
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 59 requires the party's current map.")
	var direction := _game_state.last_move_direction
	if map.level_type == &"dungeon":
		direction = _dungeon_heading_vector(_game_state.dungeon_heading)
	elif direction == Vector2i.ZERO:
		direction = Vector2i.UP
	var faced_coordinate := _game_state.party.coordinate + direction
	var cell := map.topology.effective_cell_at(faced_coordinate, _game_state.world)
	if cell == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_faced_tile", "Classic opcode 59 faces outside the current map.")
	var normalized_tile := cell.render_tile
	for marker_band: int in 3:
		if normalized_tile >= 1000:
			normalized_tile -= 1000
	var event := DomainEvent.new(&"faced_tile_branch_checked", {"expectedTile": action.extra_code[0], "normalizedTile": normalized_tile, "x": faced_coordinate.x, "y": faced_coordinate.y, "behavior": action.extra_code[1], "sourceDefect": "comparison-omitted", "source": "classic-opcode-59"})
	# newland.c normalizes the faced tile through three marker bands but never
	# compares it. Preserve that source defect: the authored behavior is unconditional.
	match action.extra_code[1]:
		-2:
			if not context.trigger_id.is_empty():
				_game_state.world.disable_trigger(context.trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [event], ScenarioVmDirective.finish_timeline())
		1:
			var branch := _branch_from_values(action.extra_code, action.gosub, context)
			branch.events.append(event)
			return branch
		2:
			return ScenarioRuntimeOperationResult.completed(true, [event, DomainEvent.new(&"action_point_kept", {"triggerId": context.trigger_id, "source": "classic-opcode-59"})], ScenarioVmDirective.finish_timeline())
	return ScenarioRuntimeOperationResult.completed(true, [event])


static func _dungeon_heading_vector(heading: int) -> Vector2i:
	match heading:
		2: return Vector2i.RIGHT
		3: return Vector2i.DOWN
		4: return Vector2i.LEFT
	return Vector2i.UP


func _branch_on_quest(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 46 requires a five-value Extra Code row.")
	var is_set := _game_state.quest_is_set(action.extra_code[0])
	var condition := action.extra_code[1]
	var should_branch := condition == 2 or condition == 1 and is_set or condition == 0 and not is_set
	return _branch_from_values(action.extra_code, action.gosub, context) if should_branch else ScenarioRuntimeOperationResult.completed(false)


func _branch_on_game_time(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 64 requires a five-value Extra Code row.")
	var day_limit := action.extra_code[0]
	var hour_limit := action.extra_code[1]
	if day_limit < -1 or hour_limit < -1 or hour_limit > 23:
		return ScenarioRuntimeOperationResult.failed(&"invalid_game_time_test", "Classic opcode 64 has an invalid day or hour limit.")
	var before_or_equal := (day_limit == -1 or _game_state.clock.day() <= day_limit) and (hour_limit == -1 or _game_state.clock.hour() <= hour_limit)
	var target_id := action.extra_code[3] if before_or_equal else action.extra_code[4]
	var branch := _branch_xap(target_id, action.gosub)
	branch.events.append(DomainEvent.new(&"game_time_branch_checked", {"day": _game_state.clock.day(), "hour": _game_state.clock.hour(), "dayLimit": day_limit, "hourLimit": hour_limit, "beforeOrEqual": before_or_equal, "targetId": target_id}))
	return branch


func _branch_on_quest_range(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 72 requires a five-value Extra Code row.")
	var first := action.extra_code[0]
	var last := action.extra_code[1]
	if first < 0 or first >= 100 or last < 0 or last >= 100:
		return ScenarioRuntimeOperationResult.failed(&"invalid_quest_range", "Classic opcode 72 references quests outside 0 through 99.")
	var all_set := true
	for quest_id: int in range(first, last + 1):
		if not _game_state.quest_is_set(quest_id):
			all_set = false
	var event := DomainEvent.new(&"quest_range_branch_checked", {"firstQuestId": first, "lastQuestId": last, "allSet": all_set, "targetMode": action.extra_code[3], "targetId": action.extra_code[4], "source": "classic"})
	if not all_set:
		return ScenarioRuntimeOperationResult.completed(false, [event])
	var branch := _branch_to_destination(action.extra_code[3], action.extra_code[4], action.gosub)
	branch.events.append(event)
	return branch


func _branch_to_random_destination(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 85 requires a five-value Extra Code row.")
	var mode := action.extra_code[0]
	var low_id := action.extra_code[1]
	var high_id := action.extra_code[2]
	if mode not in [0, 1, 2] or low_id < 0 or high_id < low_id:
		return ScenarioRuntimeOperationResult.failed(&"invalid_random_branch", "Classic opcode 85 requires a destination mode and an inclusive nonnegative range.")
	var events: Array[DomainEvent] = []
	if action.extra_code[3] != 0:
		events.append(DomainEvent.new(&"sound_requested", {"soundId": absi(action.extra_code[3]), "waitForCompletion": action.extra_code[3] < 0, "source": "classic-opcode-85"}))
	if action.extra_code[4] != 0:
		var message := _content.message_by_id(absi(action.extra_code[4]))
		if message == null:
			return ScenarioRuntimeOperationResult.failed(&"unknown_message", "Classic opcode 85 references unavailable message %d." % action.extra_code[4])
		events.append(DomainEvent.new(&"message_shown", {"messageId": message.id, "text": message.text, "source": "classic-opcode-85"}))
	var target_id := _rng.draw_between(low_id, high_id, &"classic.opcode85.destination")
	var branch := _branch_to_destination(mode, target_id, action.gosub)
	branch.events.append_array(events)
	branch.events.append(DomainEvent.new(&"random_destination_selected", {"mode": mode, "lowId": low_id, "highId": high_id, "targetId": target_id, "source": "classic-opcode-85"}))
	return branch


func _branch_on_quest_value(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 77 requires a five-value Extra Code row.")
	var quest_id := action.extra_code[0]
	if quest_id < 0 or quest_id >= 100:
		return ScenarioRuntimeOperationResult.failed(&"invalid_quest", "Classic opcode 77 references quest %d outside 0 through 99." % quest_id)
	var matched := _game_state.quest_value(quest_id) >= action.extra_code[1]
	var target_id := action.extra_code[4] if matched else action.extra_code[3]
	var event := DomainEvent.new(&"quest_value_branch_checked", {"questId": quest_id, "value": _game_state.quest_value(quest_id), "minimum": action.extra_code[1], "matched": matched, "targetId": target_id})
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(matched, [event])
	var branch := _branch_target_mode(action.extra_code[2], target_id, action.gosub)
	branch.events.append(event)
	return branch


func _branch_on_faced_tile_semantic(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5 or action.extra_code[0] < 1 or action.extra_code[0] > 7 or action.extra_code[2] not in [0, 1, 2]:
		return ScenarioRuntimeOperationResult.failed(&"invalid_faced_tile_test", "Classic opcode 78 requires a faced-tile test and destination mode.")
	var map := _content.world.map_by_id(_game_state.party.map_id)
	if map == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 78 requires the party's current map.")
	var direction := _game_state.last_move_direction
	if map.level_type == &"dungeon":
		direction = _dungeon_heading_vector(_game_state.dungeon_heading)
	elif direction == Vector2i.ZERO:
		direction = Vector2i.UP
	var faced_coordinate := _game_state.party.coordinate + direction
	var cell := map.topology.effective_cell_at(faced_coordinate, _game_state.world)
	if cell == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_faced_tile", "Classic opcode 78 faces outside the current map.")
	var matched := false
	match action.extra_code[0]:
		1: matched = cell.is_shore
		2: matched = cell.boat_requirement != 0
		3: matched = cell.is_path
		4: matched = cell.blocks_los
		5: matched = cell.fly_float_required
		6: matched = cell.is_forest
		7: matched = cell.render_tile == action.extra_code[1]
	var target_id := action.extra_code[4] if matched else action.extra_code[3]
	var event := DomainEvent.new(&"faced_tile_semantic_checked", {"testKind": action.extra_code[0], "expectedTile": action.extra_code[1], "matched": matched, "targetMode": action.extra_code[2], "targetId": target_id, "x": faced_coordinate.x, "y": faced_coordinate.y, "source": "classic-opcode-78"})
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(matched, [event])
	var branch := _branch_to_destination(action.extra_code[2], target_id, action.gosub)
	branch.events.append(event)
	return branch


func _branch_on_misc(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 86 requires a five-value Extra Code row.")
	var test_kind := action.extra_code[0]
	var expected := action.extra_code[1]
	var selected_only := expected < 0 and test_kind in [0, 1, 2, 5, 6]
	var characters := _game_state.selected_characters() if selected_only else _game_state.party.characters()
	var matched := false
	match test_kind:
		0:
			for character: CharacterState in characters:
				var caste := _content.caste_by_id(character.caste_id)
				if caste != null and caste.classic_id == absi(expected):
					matched = true
					break
		1:
			for character: CharacterState in characters:
				var race := _content.race_by_id(character.race_id)
				if race != null and race.classic_id == absi(expected):
					matched = true
					break
		2:
			for character: CharacterState in characters:
				if character.gender == absi(expected):
					matched = true
					break
		3:
			matched = _game_state.party_in_boat
		4:
			matched = _game_state.party_camping
		5:
			for character: CharacterState in characters:
				var caste := _content.caste_by_id(character.caste_id)
				if caste != null and caste.caste_class == absi(expected):
					matched = true
					break
		6:
			if absi(expected) < 1 or absi(expected) > 32:
				return ScenarioRuntimeOperationResult.failed(&"invalid_race_descriptor", "Classic opcode 86 race descriptor is outside 1 through 32.")
			var descriptor_mask := 1 << (absi(expected) - 1)
			for character: CharacterState in characters:
				var race := _content.race_by_id(character.race_id)
				if race != null and (race.descriptor_flags & descriptor_mask) != 0:
					matched = true
					break
		7:
			var total_level := 0
			for character: CharacterState in _game_state.party.characters():
				total_level += character.level
			matched = total_level > expected
		8:
			var selected_level := 0
			for character: CharacterState in _game_state.selected_characters():
				selected_level += character.level
			matched = selected_level > expected
		_:
			return ScenarioRuntimeOperationResult.failed(&"invalid_misc_branch", "Classic opcode 86 test kind is unavailable.")
	var target_id := action.extra_code[3] if matched else action.extra_code[4]
	var event := DomainEvent.new(&"misc_branch_checked", {"testKind": test_kind, "expected": expected, "matched": matched, "targetId": target_id})
	if target_id == 0:
		return ScenarioRuntimeOperationResult.completed(matched, [event])
	var branch := _branch_target_mode(action.extra_code[2], target_id, action.gosub)
	branch.events.append(event)
	return branch


func _branch_from_values(values: Array[int], gosub: bool, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	match values[2]:
		0:
			return _branch_xap(values[3], gosub)
		1, 2:
			return _branch_encounter_result(values[2], values[3], values[4], gosub, context)
		3:
			return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.finish())
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_mode", "Classic branch mode %d is not available in this execution context." % values[2])


func _branch_target_mode(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	return _branch_xap(target_id, gosub) if mode == 0 else ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is not available in this execution context." % mode)


func _branch_to_destination(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	match mode:
		0: return _branch_xap(target_id, gosub)
		1: return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.enter_encounter(&"simple", target_id, gosub))
		2: return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.enter_encounter(&"complex", target_id, gosub))
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is unavailable." % mode)


func _branch_encounter_result(mode: int, result_index: int, entry_cursor: int, gosub: bool, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var kind := &"simple" if mode == 1 else &"complex"
	if context == null or context.encounter_kind != kind or context.encounter_id < 0:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_context", "Classic branch mode %d requires an active %s Encounter result." % [mode, String(kind).capitalize()])
	if result_index < 0 or result_index > 3 or entry_cursor < 0 or entry_cursor > 7:
		return ScenarioRuntimeOperationResult.failed(&"invalid_encounter_branch", "Classic encounter-result branches require result 0 through 3 and code cursor 0 through 7.")
	var program_id := "%s:%d:result:%d" % [String(kind), context.encounter_id, result_index]
	return ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_program_at(program_id, gosub, context, entry_cursor))


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	return ScenarioRuntimeOperationResult.completed(false) if target_id == 0 else ScenarioRuntimeOperationResult.completed(true, [], ScenarioVmDirective.branch_xap(target_id, gosub))


func _opcode_25_trigger_id(context: ScenarioExecutionContext) -> String:
	if context != null and not context.trigger_id.is_empty():
		return context.trigger_id
	if context == null:
		return ""
	for program_id: String in [context.origin_program_id, context.original_program_id]:
		if program_id.begins_with("trigger:"):
			var trigger_id := program_id.trim_prefix("trigger:")
			var trigger := _content.trigger_by_id(trigger_id)
			if trigger != null and trigger.program_id == program_id:
				return trigger.id
	return ""


func resolve_program_id(program_id: String) -> String:
	return _game_state.scenario_program_id(program_id)


func replace_scenario_program(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 7 requires a five-value Extra Code row.")
	var values := action.extra_code
	var source_program_id := "xap:%d" % int(values[2])
	var target_program_id := ""
	match int(values[0]):
		-1:
			target_program_id = "simple:%d:result:%d" % [int(values[1]), int(values[4])]
		-2:
			target_program_id = "complex:%d:result:%d" % [int(values[1]), int(values[4])]
		_:
			var current_trigger := _content.trigger_by_id(context.trigger_id)
			var current_map: MapDefinition = null
			if current_trigger != null and not current_trigger.map_id.is_empty():
				current_map = _content.world.map_by_id(current_trigger.map_id)
			if current_map == null:
				current_map = _content.world.map_by_id(_game_state.party.map_id)
			if current_map == null:
				return ScenarioRuntimeOperationResult.failed(&"missing_trigger_context", "Classic opcode 7 cannot resolve the current map.")
			var level_type := current_map.level_type
			if int(values[3]) != 0:
				if int(values[3]) not in [1, 2]:
					return ScenarioRuntimeOperationResult.failed(&"invalid_map_type", "Classic opcode 7 map type must be 1 for land or 2 for dungeon.")
				level_type = &"land" if int(values[3]) == 1 else &"dungeon"
			var target_map := _content.world.map_by_type_and_index(level_type, int(values[0]))
			if target_map == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_map", "Classic opcode 7 references unavailable %s map %d." % [String(level_type), int(values[0])])
			var target_trigger := _content.trigger_by_map_record(target_map.id, int(values[1]))
			if target_trigger == null:
				return ScenarioRuntimeOperationResult.failed(&"unknown_trigger", "Classic opcode 7 references unavailable Action Point record %d on map '%s'." % [int(values[1]), target_map.id])
			target_program_id = target_trigger.program_id
	if _content.scenario.program_by_id(source_program_id) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_scenario_program", "Classic opcode 7 references unavailable source XAP %d." % int(values[2]))
	if _content.scenario.program_by_id(target_program_id) == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_scenario_program", "Classic opcode 7 references unavailable target program '%s'." % target_program_id)
	_game_state.set_scenario_program_override(target_program_id, source_program_id)
	return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"scenario_program_replaced", {"sourceProgramId": target_program_id, "targetProgramId": source_program_id, "source": "classic"})])


func branch_to_trigger_program(action: ClassicActionDefinition, context: ScenarioExecutionContext) -> ScenarioRuntimeOperationResult:
	var current_trigger := _content.trigger_by_id(context.trigger_id)
	if current_trigger == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_trigger_context", "Classic opcode 8 requires an Action Point origin.")
	var target_trigger := _content.trigger_by_map_record(current_trigger.map_id, action.operand_id)
	if target_trigger == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_trigger", "Classic opcode 8 references unavailable Action Point record %d on map '%s'." % [action.operand_id, current_trigger.map_id])
	return ScenarioRuntimeOperationResult.completed(target_trigger.program_id, [DomainEvent.new(&"scenario_program_redirected", {"triggerId": current_trigger.id, "targetTriggerId": target_trigger.id, "source": "classic"})], ScenarioVmDirective.branch_program(target_trigger.program_id, false, context))
