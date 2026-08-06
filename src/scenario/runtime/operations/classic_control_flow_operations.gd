class_name ClassicControlFlowOperations
extends RefCounted

var _content: RealmzContent
var _game_state: GameState


func _init(content: RealmzContent, game_state: GameState) -> void:
	_content = content
	_game_state = game_state


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
			var current_map := _content.world.map_by_id(current_trigger.map_id) if current_trigger != null else _content.world.map_by_id(_game_state.party.map_id)
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
