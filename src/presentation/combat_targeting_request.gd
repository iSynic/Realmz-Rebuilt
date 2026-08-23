class_name CombatTargetingRequest
extends RefCounted

var mode: StringName
var response_body: InteractionResponse.CombatBody
var candidate_ids: Array[String] = []
var area_offsets: Array[Vector2i] = []
var area_rotation_offsets: Array = []
var legal_coordinates: Array[Vector2i] = []
var maximum_targets: int = 1
var default_target_coordinate := Vector2i(-1, -1)
var validation_deferred: bool = false


func _init(target_mode: StringName, body: InteractionResponse.CombatBody) -> void:
	mode = target_mode
	response_body = body.duplicate_body() if body != null else null


func is_valid() -> bool:
	return mode in [&"combatant", &"sequence", &"area", &"coordinate_sequence"] and response_body != null and response_body.is_valid()


func supports_rotation() -> bool:
	return mode == &"area" and area_rotation_offsets.size() > 1
