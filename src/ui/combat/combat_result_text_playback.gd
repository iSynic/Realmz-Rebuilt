## Retains recipient-origin result text independently of combat action timing.
class_name CombatResultTextPlayback
extends RefCounted

const LIFETIME_SECONDS := 0.65
const STATUS_LIFETIME_SECONDS := 1.5
const MAX_LABELS := 64

class Cue:
	extends RefCounted
	var frame: CombatPlaybackFrame
	var world_rect: Rect2
	var coordinate: Vector2i
	var target_name: String
	var layout: CombatResultCardLayout
	var font_id := 0
	var elapsed := 0.0
	var lifetime := LIFETIME_SECONDS
	var appearance := 0.0

var enabled := true
var speed_percent := 100
var background_opacity_percent := 50
var motion := "floating"
var size_percent := 100
var travel_logical_pixels := 32
var anchor := "above-icon"
var custom_offset_y_logical_pixels := 0
var _frame: CombatPlaybackFrame
var _seen: Dictionary = {}
var _labels: Array[Cue] = []


func begin_frame(frame: CombatPlaybackFrame) -> void:
	if frame == _frame: return
	_frame = frame
	_seen.clear()


func capture(canvas: Control, frame: CombatPlaybackFrame, rect: Rect2, coordinate: Vector2i, target_name: String, camera: Vector2i, _visible_cells: Vector2i, origin: Vector2) -> void:
	if not enabled or _seen.has(frame) or coordinate.x < 0 or not rect.has_area(): return
	_seen[frame] = true
	var label := Cue.new()
	label.frame = frame
	label.lifetime = LIFETIME_SECONDS if frame.has_numeric_result() else STATUS_LIFETIME_SECONDS
	label.world_rect = Rect2(rect.position + Vector2(camera) * 32.0 - origin, rect.size)
	label.coordinate = coordinate
	label.target_name = target_name
	var font := canvas.get_theme_font(&"font", &"ClassicUtility")
	label.font_id = font.get_instance_id()
	label.layout = CombatResultCardLayout.measure(font, frame, CombatResultCardLayout.raster_scale_for(canvas), _size_percent(), canvas.size)
	if _labels.size() == MAX_LABELS: _labels.pop_front()
	_labels.append(label)


func advance(delta: float) -> bool:
	var had_labels := not _labels.is_empty()
	for label: Cue in _labels:
		label.appearance = minf(1.0, label.appearance + delta / 0.1)
		label.elapsed += delta * float(clampi(speed_percent, 25, 200)) / 100.0
	_labels = _labels.filter(func(label: Cue) -> bool: return label.elapsed < label.lifetime)
	return had_labels


func draw(canvas: Control, camera: Vector2i, visible_cells: Vector2i, origin: Vector2) -> void:
	# Capture order is paint order, so newer words naturally overlap older ones.
	var font := canvas.get_theme_font(&"font", &"ClassicUtility")
	var raster_scale := CombatResultCardLayout.raster_scale_for(canvas)
	var applied_size_percent := _size_percent()
	var applied_motion := "stationary" if motion == "stationary" else "floating"
	var applied_anchor := "custom" if anchor == "custom" else "above-icon"
	var applied_travel := clampi(snappedi(travel_logical_pixels, 4), 0, 64)
	var applied_offset_y := clampi(snappedi(custom_offset_y_logical_pixels, 2), -64, 64)
	for label: Cue in _labels:
		if label.font_id != font.get_instance_id() or not is_equal_approx(label.layout.raster_scale, raster_scale) or label.layout.size_percent != applied_size_percent or label.layout.measured_canvas_size != canvas.size:
			label.font_id = font.get_instance_id()
			label.layout = CombatResultCardLayout.measure(font, label.frame, raster_scale, applied_size_percent, canvas.size)
		var rect := Rect2(label.world_rect.position - Vector2(camera) * 32.0 + origin, label.world_rect.size)
		var progress := label.elapsed / label.lifetime
		var appearance := smoothstep(0.0, 1.0, label.appearance)
		var background := float(clampi(background_opacity_percent, 0, 100)) / 100.0
		if rect.intersects(Rect2(Vector2.ZERO, canvas.size)):
			CombatResultDrawing.draw(canvas, label.frame, rect, progress, label.layout, background, appearance, applied_motion, applied_travel, applied_anchor, applied_offset_y)
		else:
			CombatResultDrawing.draw_offscreen(canvas, label.frame, label.coordinate, label.target_name, camera, visible_cells, origin, appearance * (1.0 - smoothstep(0.65, 1.0, progress)), background, applied_size_percent)


func clear() -> void:
	_labels.clear()
	_seen.clear()
	_frame = null


func _size_percent() -> int:
	return clampi(snappedi(size_percent, 5), 75, 200)
