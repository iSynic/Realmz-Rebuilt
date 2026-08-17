class_name WorldMovementResult
extends RefCounted

var allowed: bool
var reason: StringName
var source_map: MapDefinition
var target_map: MapDefinition
var target_coordinate: Vector2i
var transition: MapTransition
var topology_result: TopologyMoveResult


func _init(
	move_allowed: bool,
	block_reason: StringName,
	from_map: MapDefinition = null,
	to_map: MapDefinition = null,
	to_coordinate: Vector2i = Vector2i(-1, -1),
	map_transition: MapTransition = null,
	cell_result: TopologyMoveResult = null
) -> void:
	allowed = move_allowed
	reason = block_reason
	source_map = from_map
	target_map = to_map
	target_coordinate = to_coordinate
	transition = map_transition
	topology_result = cell_result


static func blocked(block_reason: StringName, from_map: MapDefinition = null, to_map: MapDefinition = null, coordinate: Vector2i = Vector2i(-1, -1), cell_result: TopologyMoveResult = null, map_transition: MapTransition = null) -> WorldMovementResult:
	return WorldMovementResult.new(false, block_reason, from_map, to_map, coordinate, map_transition, cell_result)


static func permitted(from_map: MapDefinition, to_map: MapDefinition, coordinate: Vector2i, map_transition: MapTransition, cell_result: TopologyMoveResult) -> WorldMovementResult:
	return WorldMovementResult.new(true, &"", from_map, to_map, coordinate, map_transition, cell_result)
