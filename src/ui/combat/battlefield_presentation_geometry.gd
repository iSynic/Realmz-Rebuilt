## Calculates camera, input, combatant, footprint, and playback geometry for battle presentation.

class_name BattlefieldPresentationGeometry
extends RefCounted

const NATIVE_CELL_SIZE := 32.0
const HEADER_HEIGHT := 38.0


static func actor_position(combat: CombatView, party_members: Array[CharacterView], actor_id: String) -> Vector2i:
	if combat == null or combat.battlefield == null or actor_id.is_empty():
		return Vector2i(-1, -1)
	for character: CharacterView in party_members:
		if character.id == actor_id:
			return combat.battlefield.character_position(actor_id)
	return combat.battlefield.monster_position(actor_id)


static func actor_name(combat: CombatView, party_members: Array[CharacterView], actor_id: String) -> String:
	for character: CharacterView in party_members:
		if character.id == actor_id:
			return character.name
	if combat != null:
		for monster: MonsterView in combat.monsters:
			if monster.id == actor_id:
				return monster.name
	return actor_id if not actor_id.is_empty() else "Waiting"


static func combatant_at(combat: CombatView, party_members: Array[CharacterView], coordinate: Vector2i) -> String:
	if combat == null or combat.battlefield == null:
		return ""
	for character: CharacterView in party_members:
		if combat.battlefield.character_position(character.id) == coordinate:
			return character.id
	for monster: MonsterView in combat.monsters:
		if combat.battlefield.monster_footprint(monster.id).has(coordinate):
			return monster.id
	return ""


static func click_direction(origin: Vector2i, destination: Vector2i) -> Vector2i:
	var offset := destination - origin
	return Vector2i(signi(offset.x), signi(offset.y))


static func click_direction_for_point(active_cell: Rect2, point: Vector2) -> Vector2i:
	var offset := point - active_cell.get_center()
	if offset.length_squared() <= 36.0:
		return Vector2i.ZERO
	var horizontal := absf(offset.x)
	var vertical := absf(offset.y)
	if horizontal > vertical * 2.41421356:
		return Vector2i(signi(roundi(offset.x)), 0)
	if vertical > horizontal * 2.41421356:
		return Vector2i(0, signi(roundi(offset.y)))
	return Vector2i(signi(roundi(offset.x)), signi(roundi(offset.y)))


static func viewport_cells_for(control_size: Vector2) -> Vector2i:
	return Vector2i(
		mini(BattlefieldGrid.SIZE, maxi(1, floori(control_size.x / NATIVE_CELL_SIZE))),
		mini(BattlefieldGrid.SIZE, maxi(1, floori((control_size.y - HEADER_HEIGHT) / NATIVE_CELL_SIZE)))
	)


static func camera_top_left(active_position: Vector2i, visible_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(BattlefieldGrid.SIZE, BattlefieldGrid.SIZE) - visible_cells
	return Vector2i(
		clampi(active_position.x - floori(float(visible_cells.x) / 2.0), 0, maximum.x),
		clampi(active_position.y - floori(float(visible_cells.y) / 2.0), 0, maximum.y)
	)


static func camera_focus_id_for(frame: CombatPlaybackFrame, inspected_focus_id: String, active_actor_id: String) -> String:
	if frame != null and not frame.camera_focus_id.is_empty():
		return frame.camera_focus_id
	if not inspected_focus_id.is_empty():
		return inspected_focus_id
	return active_actor_id


static func tracked_camera_top_left(current_camera: Vector2i, focus_position: Vector2i, visible_cells: Vector2i, force_recenter: bool = false) -> Vector2i:
	if force_recenter or current_camera.x < 0 or not coordinate_is_visible(focus_position, current_camera, visible_cells) or coordinate_is_at_viewport_edge(focus_position, current_camera, visible_cells):
		return camera_top_left(focus_position, visible_cells)
	return current_camera


static func coordinate_is_at_viewport_edge(coordinate: Vector2i, camera: Vector2i, visible_cells: Vector2i) -> bool:
	return coordinate.x <= camera.x or coordinate.y <= camera.y or coordinate.x >= camera.x + visible_cells.x - 1 or coordinate.y >= camera.y + visible_cells.y - 1


static func battlefield_draw_origin(control_size: Vector2, visible_cells: Vector2i) -> Vector2:
	var pixel_size := Vector2(visible_cells) * NATIVE_CELL_SIZE
	return Vector2(
		floorf((control_size.x - pixel_size.x) * 0.5),
		HEADER_HEIGHT + floorf(maxf(control_size.y - HEADER_HEIGHT - pixel_size.y, 0.0) * 0.5)
	)


static func coordinate_for_point(local_position: Vector2, camera: Vector2i, visible_cells: Vector2i, control_size: Vector2) -> Vector2i:
	var relative := local_position - battlefield_draw_origin(control_size, visible_cells)
	if relative.x < 0.0 or relative.y < 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(floori(relative.x / NATIVE_CELL_SIZE), floori(relative.y / NATIVE_CELL_SIZE))
	if cell.x < 0 or cell.y < 0 or cell.x >= visible_cells.x or cell.y >= visible_cells.y:
		return Vector2i(-1, -1)
	return camera + cell


static func coordinate_is_visible(coordinate: Vector2i, camera: Vector2i, visible_cells: Vector2i) -> bool:
	return coordinate.x >= camera.x and coordinate.y >= camera.y and coordinate.x < camera.x + visible_cells.x and coordinate.y < camera.y + visible_cells.y


static func cell_rect(coordinate: Vector2i, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	return Rect2(draw_origin + Vector2(coordinate - camera) * NATIVE_CELL_SIZE, Vector2.ONE * NATIVE_CELL_SIZE)


static func footprint_rect(footprint: Array[Vector2i], camera: Vector2i, draw_origin: Vector2) -> Rect2:
	if footprint.is_empty():
		return Rect2()
	var minimum := footprint[0]
	var maximum := footprint[0]
	for coordinate: Vector2i in footprint:
		minimum = Vector2i(mini(minimum.x, coordinate.x), mini(minimum.y, coordinate.y))
		maximum = Vector2i(maxi(maximum.x, coordinate.x), maxi(maximum.y, coordinate.y))
	return Rect2(draw_origin + Vector2(minimum - camera) * NATIVE_CELL_SIZE, Vector2(maximum - minimum + Vector2i.ONE) * NATIVE_CELL_SIZE)


static func interpolated_draw_position(frame: CombatPlaybackFrame, camera: Vector2i, draw_origin: Vector2) -> Vector2:
	var from := draw_origin + Vector2(frame.from_coordinate - camera) * NATIVE_CELL_SIZE
	var to := draw_origin + Vector2(frame.to_coordinate - camera) * NATIVE_CELL_SIZE
	return from.lerp(to, frame.progress)


static func moving_footprint_rect(footprint: Array[Vector2i], footprint_anchor: Vector2i, frame: CombatPlaybackFrame, camera: Vector2i, draw_origin: Vector2) -> Rect2:
	var rect := footprint_rect(footprint, camera, draw_origin)
	if not rect.has_area() or frame == null or frame.kind != &"move_start":
		return rect
	var anchor_position := cell_rect(footprint_anchor, camera, draw_origin).position
	rect.position += interpolated_draw_position(frame, camera, draw_origin) - anchor_position
	return rect


static func classic_monster_icon_id(base_icon_id: int, facing_right: bool) -> int:
	return base_icon_id + 308 if facing_right else base_icon_id
