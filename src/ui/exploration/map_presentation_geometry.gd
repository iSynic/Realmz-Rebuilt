## Calculates viewport, discovery, LOS, debug-outline, and pointer geometry for 2D maps.

class_name MapPresentationGeometry
extends RefCounted

const CLASSIC_VIEW_CELLS := Vector2i(15, 13)
const RETAINED_PROJECTION_MARGIN_CELLS := Vector2i.ONE
const DARKNESS_MASK_SIZE := Vector2(320.0, 320.0)


static func random_region_outline_segments(region_bounds: Rect2i, viewport_bounds: Rect2i) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var clipped := region_bounds.intersection(viewport_bounds)
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return result
	if region_bounds.position.x >= viewport_bounds.position.x and region_bounds.position.x <= viewport_bounds.end.x:
		result.append(PackedVector2Array([Vector2(region_bounds.position.x, clipped.position.y), Vector2(region_bounds.position.x, clipped.end.y)]))
	if region_bounds.end.x >= viewport_bounds.position.x and region_bounds.end.x <= viewport_bounds.end.x:
		result.append(PackedVector2Array([Vector2(region_bounds.end.x, clipped.position.y), Vector2(region_bounds.end.x, clipped.end.y)]))
	if region_bounds.position.y >= viewport_bounds.position.y and region_bounds.position.y <= viewport_bounds.end.y:
		result.append(PackedVector2Array([Vector2(clipped.position.x, region_bounds.position.y), Vector2(clipped.end.x, region_bounds.position.y)]))
	if region_bounds.end.y >= viewport_bounds.position.y and region_bounds.end.y <= viewport_bounds.end.y:
		result.append(PackedVector2Array([Vector2(clipped.position.x, region_bounds.end.y), Vector2(clipped.end.x, region_bounds.end.y)]))
	return result


static func has_currently_hidden_cell(cells: Array[MapCellView]) -> bool:
	return cells.any(func(cell: MapCellView) -> bool: return not cell.visible)


static func los_cell_requires_blackout(uses_los: bool, was_seen: bool) -> bool:
	return uses_los and not was_seen


static func darkness_mask_rect(party_rect: Rect2) -> Rect2:
	return Rect2(party_rect.position - DARKNESS_MASK_SIZE * 0.5, DARKNESS_MASK_SIZE)


static func facing_label(direction: Vector2i) -> String:
	var horizontal := "W" if direction.x < 0 else "E" if direction.x > 0 else ""
	var vertical := "N" if direction.y < 0 else "S" if direction.y > 0 else ""
	return "%s%s" % [vertical, horizontal] if not vertical.is_empty() or not horizontal.is_empty() else "—"


static func camera_top_left(party_coordinate: Vector2i, map_size: Vector2i, viewport_cells: Vector2i) -> Vector2i:
	var maximum := Vector2i(maxi(map_size.x - viewport_cells.x, 0), maxi(map_size.y - viewport_cells.y, 0))
	return Vector2i(
		clampi(party_coordinate.x - viewport_cells.x / 2, 0, maximum.x),
		clampi(party_coordinate.y - viewport_cells.y / 2, 0, maximum.y)
	)


static func classic_visible_rect(party_coordinate: Vector2i, map_size: Vector2i) -> Rect2i:
	var view_size := Vector2i(mini(CLASSIC_VIEW_CELLS.x, map_size.x), mini(CLASSIC_VIEW_CELLS.y, map_size.y))
	var maximum := Vector2i(maxi(map_size.x - view_size.x, 0), maxi(map_size.y - view_size.y, 0))
	var origin := Vector2i(clampi(party_coordinate.x - 8, 0, maximum.x), clampi(party_coordinate.y - 6, 0, maximum.y))
	return Rect2i(origin, view_size)


static func land_discovery_coordinates(visited: Array[Vector2i], map_size: Vector2i) -> Dictionary:
	var result: Dictionary = {}
	for coordinate: Vector2i in visited:
		append_land_discovery(result, coordinate, map_size)
	return result


static func viewport_cells_for(control_size: Vector2, header_height: float, native_cell_size: float) -> Vector2i:
	return Vector2i(
		maxi(1, floori(control_size.x / native_cell_size)),
		maxi(1, floori((control_size.y - header_height) / native_cell_size))
	)


static func projection_cells_for(control_size: Vector2, header_height: float, native_cell_size: float) -> Vector2i:
	return viewport_cells_for(control_size, header_height, native_cell_size) + RETAINED_PROJECTION_MARGIN_CELLS * 2


static func map_draw_origin_for(control_size: Vector2, minimum_origin: Vector2, native_cell_size: float, viewport_cells: Vector2i) -> Vector2:
	var map_pixel_size := Vector2(viewport_cells) * native_cell_size
	var available_height := maxf(control_size.y - minimum_origin.y, 0.0)
	return Vector2(
		maxf(minimum_origin.x, floorf((control_size.x - map_pixel_size.x) * 0.5)),
		minimum_origin.y + maxf(0.0, floorf((available_height - map_pixel_size.y) * 0.5))
	)


static func dungeon_discovery_coordinates(visited: Array[Vector2i]) -> Dictionary:
	var result: Dictionary = {}
	for coordinate: Vector2i in visited:
		append_dungeon_discovery(result, coordinate)
	return result


static func darkness_overlay_alpha(saved_darkness_level: int) -> float:
	if saved_darkness_level < 0:
		return 0.45
	return lerpf(0.72, 0.12, float(clampi(saved_darkness_level, 0, 6)) / 6.0)


static func land_direction_at(position: Vector2, party_rect: Rect2) -> Vector2i:
	var horizontal := -1 if position.x < party_rect.position.x else 1 if position.x > party_rect.end.x else 0
	var vertical := -1 if position.y < party_rect.position.y else 1 if position.y > party_rect.end.y else 0
	return Vector2i(horizontal, vertical)


static func append_land_discovery(result: Dictionary, coordinate: Vector2i, map_size: Vector2i) -> void:
	var visible_rect := classic_visible_rect(coordinate, map_size)
	for y: int in range(visible_rect.position.y, visible_rect.end.y):
		for x: int in range(visible_rect.position.x, visible_rect.end.x):
			result[Vector2i(x, y)] = true


static func append_dungeon_discovery(result: Dictionary, coordinate: Vector2i) -> void:
	for y: int in range(coordinate.y - 1, coordinate.y + 2):
		for x: int in range(coordinate.x - 1, coordinate.x + 2):
			result[Vector2i(x, y)] = true
