class_name CombatTargetingState
extends RefCounted

var mode: StringName
var response_body: InteractionResponse.CombatBody
var candidate_ids: Array[String] = []
var area_offsets: Array[Vector2i] = []
var legal_coordinates: Array[Vector2i] = []
var maximum_targets: int = 1
var validation_deferred: bool = false
var selected_ids: Array[String] = []
var selected_coordinate := Vector2i(-1, -1)
var hovered_coordinate := Vector2i(-1, -1)
var status_text: String = "Choose a target on the battlefield."


func _init(request: CombatTargetingRequest) -> void:
	mode = request.mode
	response_body = request.response_body.duplicate_body()
	candidate_ids = request.candidate_ids.duplicate()
	area_offsets = request.area_offsets.duplicate()
	legal_coordinates = request.legal_coordinates.duplicate()
	maximum_targets = request.maximum_targets
	validation_deferred = request.validation_deferred
	if mode == &"area" and request.default_target_coordinate.x >= 0:
		hovered_coordinate = request.default_target_coordinate


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
	if validation_deferred and coordinate.x >= 0 and coordinate.y >= 0:
		status_text = "Target selected. Confirm to validate and cast."
		return true
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
			return selected_coordinate.x >= 0 and selected_coordinate.y >= 0 if validation_deferred else legal_coordinates.has(selected_coordinate)
	return false


func committed_body() -> InteractionResponse.CombatBody:
	if not can_confirm():
		return null
	var result := response_body.duplicate_body()
	match mode:
		&"combatant":
			result.target_id = selected_ids[0]
		&"sequence":
			result.target_id = ""
			result.target_ids = selected_ids.duplicate()
		&"area":
			result.target_id = ""
			result.target_coordinate = selected_coordinate
			result.has_target_coordinate = true
			result.rotation = 0
	return result
