class_name CombatUndoState
extends RefCounted

var actor_id: String
var start_position: Vector2i
var round_number: int
var turn_index: int
var available: bool = true


func _init(source_actor_id: String, source_position: Vector2i, source_round: int, source_turn_index: int) -> void:
	actor_id = source_actor_id
	start_position = source_position
	round_number = source_round
	turn_index = source_turn_index


func to_data() -> Dictionary:
	return {
		"actorId": actor_id,
		"startPosition": [start_position.x, start_position.y],
		"round": round_number,
		"turnIndex": turn_index,
		"available": available,
	}
