## Measures exact result words and their recipient-relative reading path.
class_name CombatResultCardLayout
extends RefCounted

var lines: PackedStringArray = []
var numeric := false
var saved := false
var width := 0.0
var size := Vector2.ZERO
var raster_scale := 1.0
var font_size := 14
var saved_font_size := 12
var size_percent := 100
var measured_canvas_size := Vector2.ZERO


static func raster_scale_for(canvas: Control) -> float:
	return maxf(1.0, canvas.get_global_transform().get_scale().x)


static func measure(font: Font, frame: CombatPlaybackFrame, raster_scale: float = 1.0, text_size_percent: int = 100, canvas_size: Vector2 = Vector2.ZERO) -> CombatResultCardLayout:
	var result := CombatResultCardLayout.new()
	result.measured_canvas_size = canvas_size
	result.raster_scale = maxf(1.0, raster_scale)
	result.size_percent = clampi(snappedi(text_size_percent, 5), 75, 200)
	var text_scale := float(result.size_percent) / 100.0
	result.font_size = roundi(14.0 * result.raster_scale * text_scale)
	result.saved_font_size = roundi(12.0 * result.raster_scale * text_scale)
	result.numeric = frame.result_kind in [&"damage", &"elemental_damage"] or frame.result_kind == &"saved" and frame.display_amount > 0
	result.saved = result.numeric and frame.result_kind == &"saved"
	var text := str(frame.display_amount) if result.numeric else frame.display_text
	if frame.result_kind == &"condition": text = text.trim_prefix("Condition applied: ")
	if frame.result_kind == &"condition_cleared": text = text.trim_prefix("Condition cleared: ") + " cleared"
	var wrap_width := 56.0
	result.measure_words(font, text, wrap_width)
	# Keep the existing compact shape unless enlarged words exceed the viewport.
	# Widen the card before clamping its anchor; never shrink the chosen font.
	var maximum_width := maxf(56.0, canvas_size.x - 16.0)
	while not result.numeric and canvas_size.y > 0.0 and result.size.y > canvas_size.y - 6.0 and wrap_width < maximum_width:
		wrap_width = minf(maximum_width, wrap_width * 2.0)
		result.measure_words(font, text, wrap_width)
	return result


func measure_words(font: Font, text: String, wrap_width: float) -> void:
	lines.clear()
	width = 0.0
	var line := ""
	for word: String in text.split(" ", false):
		var next := word if line.is_empty() else line + " " + word
		if not numeric and not line.is_empty() and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > wrap_width * raster_scale:
			lines.append(line)
			line = word
		else: line = next
	lines.append(line)
	for value: String in lines:
		width = maxf(width, font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x / raster_scale)
	if saved: width = maxf(width, font.get_string_size("Saved", HORIZONTAL_ALIGNMENT_LEFT, -1, saved_font_size).x / raster_scale)
	size = Vector2(ceilf(width * raster_scale) / raster_scale + 10.0, ceilf(font.get_height(font_size)) / raster_scale * lines.size() + 6.0 + (16.0 * float(size_percent) / 100.0 if saved else 0.0))


func start(target: Rect2, canvas_size: Vector2, anchor: String = "above-icon", custom_offset_y_logical_pixels: int = 0) -> Vector2:
	if anchor == "custom":
		var center := target.get_center() + Vector2(0.0, float(clampi(snappedi(custom_offset_y_logical_pixels, 2), -64, 64)))
		return _bounded(center - size * 0.5, canvas_size)
	return _bounded(Vector2(target.get_center().x - size.x * 0.5, target.position.y - size.y - 2.0), canvas_size)


func finish(target: Rect2, canvas_size: Vector2, travel_logical_pixels: int = 32, anchor: String = "above-icon", custom_offset_y_logical_pixels: int = 0) -> Vector2:
	var travel := clampi(snappedi(travel_logical_pixels, 4), 0, 64)
	if anchor == "custom":
		var initial := start(target, canvas_size, anchor, custom_offset_y_logical_pixels)
		return _bounded(Vector2(initial.x, initial.y - travel), canvas_size)
	return _bounded(Vector2(target.get_center().x - size.x * 0.5, target.position.y - size.y - 2.0 - travel), canvas_size)


func animated_position(target: Rect2, canvas_size: Vector2, progress: float, motion: String = "floating", travel_logical_pixels: int = 32, anchor: String = "above-icon", custom_offset_y_logical_pixels: int = 0) -> Vector2:
	var initial := start(target, canvas_size, anchor, custom_offset_y_logical_pixels)
	if motion == "stationary":
		return initial
	return initial.lerp(finish(target, canvas_size, travel_logical_pixels, anchor, custom_offset_y_logical_pixels), smoothstep(0.0, 1.0, clampf(progress, 0.0, 1.0)))


func _bounded(point: Vector2, canvas_size: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 3.0, maxf(3.0, canvas_size.x - size.x - 3.0)), clampf(point.y, 3.0, maxf(3.0, canvas_size.y - size.y - 3.0)))
