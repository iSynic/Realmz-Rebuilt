## Previews the current draft with the same result-card renderer used in battle.
class_name CombatTextPreferencesPreview
extends Control

const RESULT_LIFETIME_SECONDS := 0.65
const STAGE_COLOR := Color("#293d47")
const ICON_COLOR := Color("#87917b")
const ICON_EDGE := Color("#c8c0a3")

var _motion := PresentationSettings.COMBAT_TEXT_FLOATING
var _size_percent := 100
var _travel_logical_pixels := 32
var _anchor := PresentationSettings.COMBAT_TEXT_ANCHOR_ABOVE_ICON
var _custom_offset_y_logical_pixels := 0
var _speed_percent := 100
var _background_opacity_percent := 50
var _elapsed := 0.0
var _sample: CombatPlaybackFrame


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	_sample = CombatPlaybackFrame.new(&"result", RESULT_LIFETIME_SECONDS)
	_sample.result_kind = &"damage"
	_sample.display_amount = 12
	_sample.display_text = "12"
	_sample.damage_type = 0
	visibility_changed.connect(func() -> void: set_process(is_visible_in_tree()))
	set_process(is_visible_in_tree())


func configure(motion: String, size_percent: int, travel_logical_pixels: int, anchor: String, custom_offset_y_logical_pixels: int, speed_percent: int, background_opacity_percent: int) -> void:
	_motion = PresentationSettings.COMBAT_TEXT_STATIONARY if motion == PresentationSettings.COMBAT_TEXT_STATIONARY else PresentationSettings.COMBAT_TEXT_FLOATING
	_size_percent = clampi(snappedi(size_percent, 5), 75, 200)
	_travel_logical_pixels = clampi(snappedi(travel_logical_pixels, 4), 0, 64)
	_anchor = PresentationSettings.COMBAT_TEXT_ANCHOR_CUSTOM if anchor == PresentationSettings.COMBAT_TEXT_ANCHOR_CUSTOM else PresentationSettings.COMBAT_TEXT_ANCHOR_ABOVE_ICON
	_custom_offset_y_logical_pixels = clampi(snappedi(custom_offset_y_logical_pixels, 2), -64, 64)
	_speed_percent = clampi(snappedi(speed_percent, 25), 25, 200)
	_background_opacity_percent = clampi(snappedi(background_opacity_percent, 25), 0, 100)
	_elapsed = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed = fposmod(_elapsed + delta * float(_speed_percent) / 100.0, RESULT_LIFETIME_SECONDS)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), STAGE_COLOR, true)
	var icon := Rect2(Vector2(size.x * 0.5 - 16.0, size.y * 0.68 - 16.0), Vector2(32.0, 32.0))
	draw_rect(icon, ICON_COLOR, true)
	draw_rect(icon, ICON_EDGE, false, 1.0)
	if _sample == null:
		return
	var font := get_theme_font(&"font", &"ClassicUtility")
	var layout := CombatResultCardLayout.measure(font, _sample, CombatResultCardLayout.raster_scale_for(self), _size_percent, size)
	CombatResultDrawing.draw(
		self,
		_sample,
		icon,
		_elapsed / RESULT_LIFETIME_SECONDS,
		layout,
		float(_background_opacity_percent) / 100.0,
		1.0,
		_motion,
		_travel_logical_pixels,
		_anchor,
		_custom_offset_y_logical_pixels
	)
