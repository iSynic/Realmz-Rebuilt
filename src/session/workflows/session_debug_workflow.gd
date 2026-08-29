class_name SessionDebugWorkflow
extends RefCounted

const HARMFUL_CONDITIONS: Array[int] = [
	ConditionRules.RUNS_AWAY, ConditionRules.HELPLESS, ConditionRules.TANGLED,
	ConditionRules.CURSED, ConditionRules.STUPID, ConditionRules.SLOW,
	ConditionRules.POISONED, ConditionRules.TURNED_TO_STONE, ConditionRules.BLIND,
	ConditionRules.DISEASED, ConditionRules.CONFUSED, ConditionRules.ENERGY_DRAIN,
	ConditionRules.HINDERED_ATTACKS, ConditionRules.HINDERED_DEFENSE, ConditionRules.SILENCED,
]


static func warp(context: SessionWorkflowContext, map_id: String, coordinate: Vector2i) -> SessionWorkflowResult:
	var map := context.content.world.map_by_id(map_id)
	if map == null or map.topology.cell_at(coordinate) == null:
		return SessionWorkflowResult.failed(&"debug_location_unavailable", "The requested map coordinate is unavailable.")
	if context.state.combat != null or context.scenario_vm.is_active():
		return SessionWorkflowResult.failed(&"debug_exploration_required", "Warp is available only at a committed exploration boundary.")
	var source_map := context.state.party.map_id
	var source_coordinate := context.state.party.coordinate
	context.state.party.map_id = map.id
	context.state.party.coordinate = coordinate
	context.state.last_move_direction = Vector2i.ZERO
	context.state.world.mark_visited(map.id, coordinate)
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_party_warped", {"fromMapId": source_map, "fromX": source_coordinate.x, "fromY": source_coordinate.y, "mapId": map.id, "x": coordinate.x, "y": coordinate.y})])


static func noclip_step(context: SessionWorkflowContext, direction: Vector2i) -> SessionWorkflowResult:
	if not MapTopology.is_cardinal_direction(direction) and not MapTopology.is_diagonal_direction(direction):
		return SessionWorkflowResult.failed(&"debug_direction_invalid", "No-clip movement requires one adjacent direction.")
	var map := context.content.world.map_by_id(context.state.party.map_id)
	var source := context.state.party.coordinate
	var target := source + direction
	if map == null or map.topology.cell_at(target) == null:
		return SessionWorkflowResult.failed(&"debug_location_unavailable", "No-clip movement cannot leave the current map.")
	if context.state.combat != null or context.scenario_vm.is_active():
		return SessionWorkflowResult.failed(&"debug_exploration_required", "No-clip movement is available only at a committed exploration boundary.")
	context.state.party.coordinate = target
	context.state.last_move_direction = direction
	context.state.world.mark_visited(map.id, target)
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_party_noclip_moved", {"fromMapId": map.id, "fromX": source.x, "fromY": source.y, "mapId": map.id, "x": target.x, "y": target.y})])


static func restore_party(context: SessionWorkflowContext) -> SessionWorkflowResult:
	if context.state.party.characters().is_empty():
		return SessionWorkflowResult.failed(&"debug_party_unavailable", "The party has no characters to restore.")
	for character: CharacterState in context.state.party.characters():
		character.current_health = character.maximum_health
		character.spell_points = character.maximum_spell_points
		for condition: int in HARMFUL_CONDITIONS:
			if character.conditions.value(condition) > 0:
				character.conditions.set_value(condition, 0)
	return SessionWorkflowResult.completed([DomainEvent.new(&"debug_party_restored", {"characterCount": context.state.party.characters().size()})])
