class_name TopologyMoveResult
extends RefCounted

var allowed: bool
var reason: StringName
var target_cell: MapCell
var door_id: String
var secret_id: String


static func permitted(cell: MapCell, linked_door_id: String = "", linked_secret_id: String = "") -> TopologyMoveResult:
	var result := TopologyMoveResult.new()
	result.allowed = true
	result.target_cell = cell
	result.door_id = linked_door_id
	result.secret_id = linked_secret_id
	return result


static func blocked(block_reason: StringName, cell: MapCell = null) -> TopologyMoveResult:
	var result := TopologyMoveResult.new()
	result.reason = block_reason
	result.target_cell = cell
	return result
