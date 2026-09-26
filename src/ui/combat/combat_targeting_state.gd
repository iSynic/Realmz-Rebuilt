## Presents combat targeting state through the Godot interface.

class_name CombatTargetingState
extends RefCounted

var mode: StringName
var response_body: InteractionResponse.CombatBody
var candidate_ids: Array[String] = []
var area_offsets: Array[Vector2i] = []
var area_rotation_offsets: Array = []
var rotation: int = 0
var legal_coordinates: Array[Vector2i] = []
var maximum_targets: int = 1
var validation_deferred: bool = false
var selected_ids: Array[String] = []
var selected_coordinates: Array[Vector2i] = []
var selected_coordinate := Vector2i(-1, -1)
var hovered_coordinate := Vector2i(-1, -1)
var candidate_index: int = -1
var status_text: String = "Choose a target on the battlefield."


func _init(request: CombatTargetingRequest) -> void:
	mode = request.mode
	response_body = request.response_body.duplicate_body()
	candidate_ids = request.candidate_ids.duplicate()
	area_offsets = request.area_offsets.duplicate()
	for offsets: Variant in request.area_rotation_offsets:
		if offsets is Array:
			area_rotation_offsets.append((offsets as Array).duplicate())
	if area_rotation_offsets.is_empty() and not area_offsets.is_empty():
		area_rotation_offsets.append(area_offsets.duplicate())
	legal_coordinates = request.legal_coordinates.duplicate()
	maximum_targets = request.maximum_targets
	validation_deferred = request.validation_deferred
	if mode in [&"area", &"coordinate_sequence"] and request.default_target_coordinate.x >= 0:
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
	if mode == &"coordinate_sequence":
		if coordinate.x < 0 or coordinate.y < 0:
			status_text = "That battlefield space is unavailable."
			return false
		if selected_coordinates.has(coordinate):
			selected_coordinates.erase(coordinate)
			status_text = "Summon space removed from the ordered selection."
			return true
		if not validation_deferred and not legal_coordinates.has(coordinate):
			status_text = "The summoned creature cannot fit at that space."
			return false
		if not area_offsets.is_empty():
			for chosen: Vector2i in selected_coordinates:
				for offset: Vector2i in area_offsets:
					if area_offsets.has(coordinate + offset - chosen):
						status_text = "Summoned creatures cannot overlap."
						return false
		if selected_coordinates.size() >= maximum_targets:
			status_text = "The selected summon has reached its space limit."
			return false
		selected_coordinates.append(coordinate)
		status_text = "%d of %d summon spaces selected in cast order." % [selected_coordinates.size(), maximum_targets]
		return true
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


func target_with_keyboard() -> bool:
	if mode in [&"combatant", &"sequence"]:
		if candidate_ids.is_empty():
			return false
		var current_index := candidate_ids.find(selected_ids[-1]) if not selected_ids.is_empty() else -1
		selected_ids.assign([candidate_ids[(current_index + 1) % candidate_ids.size()]])
		status_text = "Target selected. Press Space to commit the action."
		return true
	if mode == &"coordinate_sequence":
		var summon_coordinate := hovered_coordinate
		if summon_coordinate.x < 0 or summon_coordinate.y < 0:
			return false
		return select_coordinate(summon_coordinate)
	if mode != &"area":
		return false
	var coordinate := hovered_coordinate
	if not validation_deferred and not legal_coordinates.has(coordinate):
		coordinate = legal_coordinates[0] if not legal_coordinates.is_empty() else Vector2i(-1, -1)
	if coordinate.x < 0 or coordinate.y < 0:
		return false
	return select_coordinate(coordinate)


func cycle_candidate(delta: int) -> bool:
	if mode not in [&"combatant", &"sequence"] or candidate_ids.is_empty() or delta == 0:
		return false
	candidate_index = posmod(candidate_index + delta, candidate_ids.size())
	status_text = "Previewing target %d of %d. Confirm the target or cycle again." % [candidate_index + 1, candidate_ids.size()]
	return true


func previewed_candidate_id() -> String:
	return candidate_ids[candidate_index] if candidate_index >= 0 and candidate_index < candidate_ids.size() else ""


func select_previewed_target() -> bool:
	var candidate_id := previewed_candidate_id()
	if candidate_id.is_empty() and not cycle_candidate(1):
		return false
	return select_combatant(previewed_candidate_id())


func move_coordinate_preview(direction: Vector2i) -> bool:
	if mode not in [&"area", &"coordinate_sequence"] or direction == Vector2i.ZERO:
		return false
	var next := hovered_coordinate + direction
	if hovered_coordinate.x < 0 or hovered_coordinate.y < 0:
		next = legal_coordinates[0] if not legal_coordinates.is_empty() else Vector2i.ZERO
	next = next.clamp(Vector2i.ZERO, Vector2i.ONE * (BattlefieldGrid.SIZE - 1))
	hovered_coordinate = next
	if not validation_deferred and not legal_coordinates.is_empty() and not legal_coordinates.has(next):
		status_text = "That battlefield space is outside the legal target area."
		return true
	status_text = "Previewing battlefield space %d, %d." % [next.x, next.y]
	return true


func rotate_area() -> bool:
	if mode != &"area" or area_rotation_offsets.size() < 2:
		return false
	rotation = (rotation + 1) % area_rotation_offsets.size()
	area_offsets.assign(area_rotation_offsets[rotation])
	status_text = "Area rotated to orientation %d of %d." % [rotation + 1, area_rotation_offsets.size()]
	return true


func can_confirm() -> bool:
	match mode:
		&"combatant", &"sequence":
			return not selected_ids.is_empty()
		&"area":
			return selected_coordinate.x >= 0 and selected_coordinate.y >= 0 if validation_deferred else legal_coordinates.has(selected_coordinate)
		&"coordinate_sequence":
			return not selected_coordinates.is_empty() and (validation_deferred or selected_coordinates.all(func(coordinate: Vector2i) -> bool: return legal_coordinates.has(coordinate)))
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
			result.rotation = rotation
		&"coordinate_sequence":
			result.target_id = ""
			result.target_coordinates = selected_coordinates.duplicate()
	return result
