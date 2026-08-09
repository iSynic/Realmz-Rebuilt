class_name BattlefieldStepResult
extends RefCounted

var allowed: bool = false
var reason: StringName = &"unknown"
var destination: Vector2i = Vector2i(-1, -1)
var movement_cost: int = 0
var occupant_id: String = ""


static func permitted(target: Vector2i, cost: int) -> BattlefieldStepResult:
	var result := BattlefieldStepResult.new()
	result.allowed = true
	result.reason = &""
	result.destination = target
	result.movement_cost = cost
	return result


static func blocked(block_reason: StringName, target: Vector2i = Vector2i(-1, -1), occupant: String = "") -> BattlefieldStepResult:
	var result := BattlefieldStepResult.new()
	result.reason = block_reason
	result.destination = target
	result.occupant_id = occupant
	return result
