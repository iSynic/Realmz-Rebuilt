class_name CombatTargetingState
extends RefCounted

var mode: StringName
var response_payload: Dictionary
var candidate_ids: Array[String] = []
var area_offsets: Array[Vector2i] = []
var legal_coordinates: Array[Vector2i] = []
var maximum_targets: int = 1
var selected_ids: Array[String] = []
var selected_coordinate := Vector2i(-1, -1)
var hovered_coordinate := Vector2i(-1, -1)
var status_text: String = "Choose a target on the battlefield."


func _init(target_mode: StringName, base_response_payload: Dictionary) -> void:
	mode = target_mode
	response_payload = base_response_payload.duplicate(true)


func select_combatant(combatant_id: String) -> bool:
	if mode not in [&"combatant", &"sequence"] or combatant_id.is_empty() or not candidate_ids.has(combatant_id):
		status_text = "That combatant is not a legal target for the selected action."
		return false
	if mode == &"combatant":
		selected_ids.assign([combatant_id])
		status_text = "Target selected. Confirm to commit the action."
		return true
	if selected_ids.has(combatant_id):
		selected_ids.erase(combatant_id)
		status_text = "Target removed from the ordered selection."
		return true
	if selected_ids.size() >= maximum_targets:
		status_text = "The selected spell has reached its target limit."
		return false
	selected_ids.append(combatant_id)
	status_text = "%d of %d targets selected in cast order." % [selected_ids.size(), maximum_targets]
	return true


func select_coordinate(coordinate: Vector2i) -> bool:
	if mode != &"area":
		return false
	selected_coordinate = coordinate
	if not legal_coordinates.has(coordinate):
		status_text = "That center is outside the rules-owned range, line of sight, or safe mask boundary."
		return false
	status_text = "Area center is legal. Confirm to commit the spell."
	return true


func can_confirm() -> bool:
	match mode:
		&"combatant", &"sequence":
			return not selected_ids.is_empty()
		&"area":
			return legal_coordinates.has(selected_coordinate)
	return false


func committed_payload() -> Dictionary:
	if not can_confirm():
		return {}
	var payload := response_payload.duplicate(true)
	match mode:
		&"combatant":
			payload["targetId"] = selected_ids[0]
		&"sequence":
			payload["targetId"] = ""
			payload["targetIds"] = selected_ids.duplicate()
		&"area":
			payload["targetId"] = ""
			payload["targetCoordinate"] = [selected_coordinate.x, selected_coordinate.y]
			payload["rotation"] = 0
	return payload


func selection_data() -> Dictionary:
	return {
		"mode": String(mode),
		"selectedIds": selected_ids.duplicate(),
		"selectedCoordinate": [selected_coordinate.x, selected_coordinate.y],
		"maximumTargets": maximum_targets,
		"canConfirm": can_confirm(),
		"status": status_text,
	}
