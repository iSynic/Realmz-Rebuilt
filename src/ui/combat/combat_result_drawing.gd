## Draws presentation-only result cards rising from the recipient.
class_name CombatResultDrawing
extends RefCounted

# Rebuilt damage accents; these do not recolor authored Castle effect art.
const DAMAGE_OUTLINES: Dictionary = {
	1: Color("#ee8849"), 2: Color("#69cff2"), 3: Color("#e6ce59"),
	4: Color("#86c86d"), 5: Color("#c597ef"),
}
const NEUTRAL_OUTLINE := Color("#afb7c0")


static func draw(canvas: Control, frame: CombatPlaybackFrame, target_rect: Rect2, elapsed_fraction: float = -1.0, layout: CombatResultCardLayout = null, background_opacity: float = 0.5, appearance: float = 1.0, motion: String = "floating", travel_logical_pixels: int = 32, anchor: String = "above-icon", custom_offset_y_logical_pixels: int = 0) -> void:
	var font := canvas.get_theme_font(&"font", &"ClassicUtility")
	if layout == null: layout = CombatResultCardLayout.measure(font, frame, CombatResultCardLayout.raster_scale_for(canvas), 100, canvas.size)
	var progress := clampf(frame.progress if elapsed_fraction < 0.0 else elapsed_fraction, 0.0, 1.0)
	var position := layout.animated_position(target_rect, canvas.size, progress, motion, travel_logical_pixels, anchor, custom_offset_y_logical_pixels)
	position.x = clampf(position.x, 3.0, maxf(3.0, canvas.size.x - layout.size.x - 3.0))
	position.y = clampf(position.y, 3.0, maxf(3.0, canvas.size.y - layout.size.y - 3.0))
	var opacity := appearance * (1.0 - smoothstep(0.65, 1.0, progress))
	var scale := layout.raster_scale
	# Rasterize at viewport density while retaining the world-relative card geometry.
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / scale)
	canvas.draw_rect(Rect2(position * scale, layout.size * scale), Color(0.02, 0.025, 0.03, background_opacity * opacity))
	var saved_offset := 16.0 * scale * float(layout.size_percent) / 100.0
	var point := position * scale + Vector2(5.0 * scale, 3.0 * scale + font.get_ascent(layout.font_size) + (saved_offset if layout.saved else 0.0))
	for index: int in layout.lines.size():
		_draw_line(canvas, font, frame, layout.lines[index], point + Vector2(0.0, float(index) * ceilf(font.get_height(layout.font_size))), layout.width * scale, opacity, layout.numeric, layout.font_size, scale)
	if layout.saved:
		canvas.draw_string_outline(font, point - Vector2(0.0, saved_offset), "Saved", HORIZONTAL_ALIGNMENT_CENTER, layout.width * scale, layout.saved_font_size, roundi(2.0 * scale), Color(0.0, 0.0, 0.0, opacity))
		canvas.draw_string(font, point - Vector2(0.0, saved_offset), "Saved", HORIZONTAL_ALIGNMENT_CENTER, layout.width * scale, layout.saved_font_size, Color(1.0, 1.0, 1.0, opacity))
	canvas.draw_set_transform(Vector2.ZERO)


static func _draw_line(canvas: Control, font: Font, frame: CombatPlaybackFrame, text: String, point: Vector2, width: float, opacity: float, numeric: bool, font_size: int, scale: float) -> void:
	var ink := Color.BLACK if frame.effect_resource_id in [162, 163, 164, 167] else Color.RED if frame.effect_resource_id == 159 else Color.WHITE
	if frame.result_kind == &"monster_status": ink = Color(1.0, 0.90, 0.56)
	if frame.result_kind == &"healing": ink = Color(0.72, 1.0, 0.72)
	var outline := Color.WHITE if ink == Color.BLACK else Color.BLACK
	var outline_size := 2
	if numeric and frame.display_amount > 0:
		ink = Color.WHITE
		outline = DAMAGE_OUTLINES.get(frame.damage_type, NEUTRAL_OUTLINE)
		outline_size = 3
		canvas.draw_string_outline(font, point, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, roundi(5.0 * scale), Color(0.0, 0.0, 0.0, opacity))
	ink.a = opacity
	outline.a = opacity
	canvas.draw_string_outline(font, point, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, roundi(outline_size * scale), outline)
	canvas.draw_string(font, point, text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size, ink)


static func offscreen_rect(canvas: Control, frame: CombatPlaybackFrame, coordinate: Vector2i, target_name: String, camera: Vector2i, visible_cells: Vector2i, origin: Vector2, text_size_percent: int = 100) -> Rect2:
	var font := canvas.get_theme_font(&"font", &"ClassicUtility")
	var scale := CombatResultCardLayout.raster_scale_for(canvas)
	var text_scale := float(clampi(snappedi(text_size_percent, 5), 75, 200)) / 100.0
	var target_font_size := roundi(12.0 * scale * text_scale)
	var result_font_size := roundi(14.0 * scale * text_scale)
	var width := maxf(font.get_string_size(target_name, HORIZONTAL_ALIGNMENT_LEFT, -1, target_font_size).x, font.get_string_size(frame.display_text, HORIZONTAL_ALIGNMENT_LEFT, -1, result_font_size).x) / scale + 30.0
	return BattlefieldPresentationGeometry.offscreen_indicator_rect(coordinate, camera, visible_cells, origin, Vector2(minf(width, canvas.size.x - 8.0), 46.0 * text_scale), canvas.size)


static func draw_offscreen(canvas: Control, frame: CombatPlaybackFrame, coordinate: Vector2i, target_name: String, camera: Vector2i, visible_cells: Vector2i, draw_origin: Vector2, opacity: float = 1.0, background_opacity: float = 0.5, text_size_percent: int = 100) -> void:
	var font := canvas.get_theme_font(&"font", &"ClassicUtility")
	var badge := offscreen_rect(canvas, frame, coordinate, target_name, camera, visible_cells, draw_origin, text_size_percent)
	if not badge.has_area(): return
	var scale := CombatResultCardLayout.raster_scale_for(canvas)
	var text_scale := float(clampi(snappedi(text_size_percent, 5), 75, 200)) / 100.0
	badge = Rect2(badge.position * scale, badge.size * scale)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / scale)
	var direction := (BattlefieldPresentationGeometry.cell_rect(coordinate, camera, draw_origin).get_center() - (draw_origin + Vector2(visible_cells) * BattlefieldPresentationGeometry.NATIVE_CELL_SIZE * 0.5)).normalized()
	var arrow_center := badge.position + Vector2(12.0, 14.0) * scale
	var arrow_base := arrow_center - direction * 4.0 * scale
	var arrow_side := Vector2(-direction.y, direction.x) * 4.0 * scale
	var arrow := PackedVector2Array([arrow_center + direction * 6.0 * scale, arrow_base + arrow_side, arrow_base - arrow_side])
	var text_color := Color(0.72, 1.0, 0.72, opacity) if frame.result_kind == &"healing" else Color(1.0, 0.95, 0.82, opacity)
	canvas.draw_rect(badge, Color(0.02, 0.025, 0.03, background_opacity * opacity), true)
	canvas.draw_rect(badge, Color(0.86, 0.72, 0.30, 0.95 * opacity), false, 2.0 * scale)
	canvas.draw_colored_polygon(arrow, Color(1.0, 0.86, 0.28, opacity))
	canvas.draw_string(font, badge.position + Vector2(23.0, 16.0 * text_scale) * scale, target_name, HORIZONTAL_ALIGNMENT_LEFT, badge.size.x - 27.0 * scale, roundi(12.0 * scale * text_scale), text_color)
	canvas.draw_string(font, badge.position + Vector2(23.0, 36.0 * text_scale) * scale, frame.display_text, HORIZONTAL_ALIGNMENT_LEFT, badge.size.x - 27.0 * scale, roundi(14.0 * scale * text_scale), text_color)
	canvas.draw_set_transform(Vector2.ZERO)
