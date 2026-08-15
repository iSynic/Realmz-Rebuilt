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
	return [7, 8, 24, 25, 42, 46, 64, 77, 86, 98, 99]


func execute(action: ClassicActionDefinition, _request_id: String, context: Dictionary) -> ScenarioRuntimeOperationResult:
	match action.opcode:
		7:
			return replace_scenario_program(action, context)
		8:
			return branch_to_trigger_program(action, context)
		24:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"action_point_kept", {"triggerId": String(context.get("triggerId", "")), "source": "classic"})], {"kind": "finish"})
		25:
			var trigger_id := String(context.get("triggerId", ""))
			if trigger_id.is_empty():
				return ScenarioRuntimeOperationResult.failed(&"missing_trigger_context", "Classic opcode 25 requires an Action Point origin.")
			_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [DomainEvent.new(&"trigger_disabled", {"triggerId": trigger_id, "source": "classic"})])
		42:
			return _percent_branch(action, context)
		46:
			return _branch_on_quest(action)
		64:
			return _branch_on_game_time(action)
		77:
			return _branch_on_quest_value(action)
		86:
			return _branch_on_misc(action)
		98, 99:
			return ScenarioRuntimeOperationResult.completed(null, [DomainEvent.new(&"classic_control_marker", {"opcode": action.opcode, "operandId": action.operand_id})])
	return super.execute(action, _request_id, context)


func _percent_branch(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 42 requires a five-value Extra Code row.")
	var roll := _rng.draw(100, &"classic.percent-branch")
	if roll > action.extra_code[0]:
		return ScenarioRuntimeOperationResult.completed(false, [DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": false})])
	var event := DomainEvent.new(&"percent_branch_checked", {"chance": action.extra_code[0], "roll": roll, "matched": true})
	match action.extra_code[1]:
		-2:
			var trigger_id := String(context.get("triggerId", ""))
			if not trigger_id.is_empty():
				_game_state.world.disable_trigger(trigger_id)
			return ScenarioRuntimeOperationResult.completed(true, [event], {"kind": "finish"})
		1:
			var branch := _branch_from_values(action.extra_code, false)
			branch.events.append(event)
			return branch
		2:
			return ScenarioRuntimeOperationResult.completed(true, [event], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.completed(true, [event])


func _branch_on_quest(action: ClassicActionDefinition) -> ScenarioRuntimeOperationResult:
	if action.extra_code.size() < 5:
		return ScenarioRuntimeOperationResult.failed(&"missing_extra_code", "Classic opcode 46 requires a five-value Extra Code row.")
	var is_set := _game_state.quest_is_set(action.extra_code[0])
	var condition := action.extra_code[1]
	var should_branch := condition == 2 or condition == 1 and is_set or condition == 0 and not is_set
	return _branch_from_values(action.extra_code, action.gosub) if should_branch else ScenarioRuntimeOperationResult.completed(false)


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


func _branch_from_values(values: Array[int], gosub: bool) -> ScenarioRuntimeOperationResult:
	match values[2]:
		0:
			return _branch_xap(values[3], gosub)
		3:
			return ScenarioRuntimeOperationResult.completed(true, [], {"kind": "finish"})
	return ScenarioRuntimeOperationResult.failed(&"unsupported_branch_mode", "Classic branch mode %d is not available in this execution context." % values[2])


func _branch_target_mode(mode: int, target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	return _branch_xap(target_id, gosub) if mode == 0 else ScenarioRuntimeOperationResult.failed(&"unsupported_branch_target", "Classic branch target mode %d is not available in this execution context." % mode)


func _branch_xap(target_id: int, gosub: bool) -> ScenarioRuntimeOperationResult:
	return ScenarioRuntimeOperationResult.completed(false) if target_id == 0 else ScenarioRuntimeOperationResult.completed(true, [], {"kind": "branch-xap", "targetId": target_id, "gosub": gosub})


func resolve_program_id(program_id: String) -> String:
	return _game_state.scenario_program_id(program_id)


func replace_scenario_program(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
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
			var current_trigger := _content.trigger_by_id(str(context.get("triggerId", "")))
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


func branch_to_trigger_program(action: ClassicActionDefinition, context: Dictionary) -> ScenarioRuntimeOperationResult:
	var current_trigger := _content.trigger_by_id(str(context.get("triggerId", "")))
	if current_trigger == null:
		return ScenarioRuntimeOperationResult.failed(&"missing_trigger_context", "Classic opcode 8 requires an Action Point origin.")
	var target_trigger := _content.trigger_by_map_record(current_trigger.map_id, action.operand_id)
	if target_trigger == null:
		return ScenarioRuntimeOperationResult.failed(&"unknown_trigger", "Classic opcode 8 references unavailable Action Point record %d on map '%s'." % [action.operand_id, current_trigger.map_id])
	return ScenarioRuntimeOperationResult.completed(target_trigger.program_id, [DomainEvent.new(&"scenario_program_redirected", {"triggerId": current_trigger.id, "targetTriggerId": target_trigger.id, "source": "classic"})], {"kind": "branch-program", "programId": target_trigger.program_id, "gosub": false, "context": context.duplicate(true)})
