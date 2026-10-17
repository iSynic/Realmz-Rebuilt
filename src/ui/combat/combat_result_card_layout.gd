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


static func raster_scale_for(canvas: Control) -> float:
	return maxf(1.0, canvas.get_global_transform().get_scale().x)


static func measure(font: Font, frame: CombatPlaybackFrame, raster_scale: float = 1.0) -> CombatResultCardLayout:
	var result := CombatResultCardLayout.new()
	result.raster_scale = maxf(1.0, raster_scale)
	result.font_size = roundi(14.0 * result.raster_scale)
	result.saved_font_size = roundi(12.0 * result.raster_scale)
	result.numeric = frame.result_kind in [&"damage", &"elemental_damage"] or frame.result_kind == &"saved" and frame.display_amount > 0
	result.saved = result.numeric and frame.result_kind == &"saved"
	var text := str(frame.display_amount) if result.numeric else frame.display_text
	if frame.result_kind == &"condition": text = text.trim_prefix("Condition applied: ")
	if frame.result_kind == &"condition_cleared": text = text.trim_prefix("Condition cleared: ") + " cleared"
	var line := ""
	for word: String in text.split(" ", false):
		var next := word if line.is_empty() else line + " " + word
		if not result.numeric and not line.is_empty() and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, result.font_size).x > 56.0 * result.raster_scale:
			result.lines.append(line)
			line = word
		else: line = next
	result.lines.append(line)
	for value: String in result.lines:
		result.width = maxf(result.width, font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, result.font_size).x / result.raster_scale)
	if result.saved: result.width = maxf(result.width, font.get_string_size("Saved", HORIZONTAL_ALIGNMENT_LEFT, -1, result.saved_font_size).x / result.raster_scale)
	result.size = Vector2(ceilf(result.width * result.raster_scale) / result.raster_scale + 10.0, ceilf(font.get_height(result.font_size)) / result.raster_scale * result.lines.size() + 6.0 + (16.0 if result.saved else 0.0))
	return result


func start(target: Rect2, canvas_size: Vector2) -> Vector2:
	return _bounded(Vector2(target.get_center().x - size.x * 0.5, target.position.y - size.y - 2.0), canvas_size)


func finish(target: Rect2, canvas_size: Vector2) -> Vector2:
	return _bounded(Vector2(start(target, canvas_size).x, target.position.y - size.y - 34.0), canvas_size)


func _bounded(point: Vector2, canvas_size: Vector2) -> Vector2:
	return Vector2(clampf(point.x, 3.0, maxf(3.0, canvas_size.x - size.x - 3.0)), clampf(point.y, 3.0, maxf(3.0, canvas_size.y - size.y - 3.0)))
