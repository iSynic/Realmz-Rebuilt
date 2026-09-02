class_name CombatPlaybackFrame
extends RefCounted

var kind: StringName
var duration_seconds: float
var progress: float = 0.0
var actor_id: String = ""
var target_id: String = ""
var camera_focus_id: String = ""
var from_coordinate := Vector2i(-1, -1)
var to_coordinate := Vector2i(-1, -1)
var combatant_positions: Dictionary = {}
var hidden_combatant_ids: Array[String] = []
var result_kind: StringName = &""
var display_text: String = ""
var display_amount: int = 0
var effect_resource_type: String = "cicn"
var effect_resource_id: int = 0
var battle_tile_id: int = 0
var sound_event: DomainEvent
var automatic: bool = false


func _init(frame_kind: StringName, frame_duration_seconds: float) -> void:
	kind = frame_kind
	duration_seconds = maxf(frame_duration_seconds, 0.0)


func position_for(combatant_id: String) -> Vector2i:
	var value: Variant = combatant_positions.get(combatant_id)
	if value is Vector2i:
		return value
	return Vector2i(-1, -1)


func hides(combatant_id: String) -> bool:
	return hidden_combatant_ids.has(combatant_id)
