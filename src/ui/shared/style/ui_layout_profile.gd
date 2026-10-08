## Presents UI layout profile through the Godot interface.

class_name UiLayoutProfile
extends RefCounted

const COMPACT: StringName = &"compact"
const WIDE: StringName = &"wide"
const WIDE_ASPECT: float = 16.0 / 9.0
const WIDE_MINIMUM := Vector2(1280.0, 720.0)
const COMPACT_MINIMUM := Vector2(800.0, 600.0)

var id: StringName
var ui_scale: float
var requested_scale: float
var font_scale: float
var scale_limited: bool
var party_width: float
var context_width: float
var context_is_drawer: bool
var navigation_uses_overflow: bool
var menu_height: float
var bottom_height: float
var command_width: float
var bitmap_scale: int
var application_rect: Rect2


func _init(profile_id: StringName, scale: float, party: float, bottom: float, command: float, art_scale: int) -> void:
	id = profile_id
	ui_scale = scale
	requested_scale = scale
	font_scale = scale
	party_width = party
	context_width = 0.0
	context_is_drawer = false
	navigation_uses_overflow = profile_id == COMPACT
	menu_height = 28.0 * scale
	bottom_height = bottom
	command_width = command
	bitmap_scale = art_scale


static func for_viewport(size: Vector2, scale_mode: String, display_mode: String = PresentationSettings.DISPLAY_INTEGER_CANVAS, text_scale: float = 1.0) -> UiLayoutProfile:
	var canvas_rect := UiLayoutProfile.application_rect_for(size, display_mode)
	var canvas_size := canvas_rect.size
	var requested := UiLayoutProfile.scale_for(canvas_size, scale_mode)
	var maximum := maxf(1.0, minf(canvas_size.x / COMPACT_MINIMUM.x, canvas_size.y / COMPACT_MINIMUM.y))
	var scale := minf(requested, maximum)
	var effective_width := canvas_size.x / scale
	var art_scale := clampi(roundi(scale), 1, 3)
	var profile: UiLayoutProfile
	if effective_width < WIDE_MINIMUM.x - 1.0 or canvas_size.y / scale < WIDE_MINIMUM.y - 1.0:
		var roster_width := (208.0 * maxf(1.0, text_scale) + 80.0 * maxf(0.0, text_scale - 1.0)) * scale
		profile = UiLayoutProfile.new(COMPACT, scale, roster_width, 270.0 * scale, 416.0 * scale, art_scale)
	else:
		profile = UiLayoutProfile.new(WIDE, scale, 352.0 * scale, 190.0 * scale, 288.0 * scale, art_scale)
	profile.requested_scale = requested
	profile.font_scale = scale * text_scale
	profile.scale_limited = scale < requested
	profile.application_rect = canvas_rect
	return profile


static func application_rect_for(size: Vector2, display_mode: String = PresentationSettings.DISPLAY_RESPONSIVE) -> Rect2:
	if display_mode == PresentationSettings.DISPLAY_FILL_WINDOW:
		return Rect2(Vector2.ZERO, size)
	if size.x < WIDE_MINIMUM.x or size.y < WIDE_MINIMUM.y or size.y <= 0.0 or size.x / size.y <= WIDE_ASPECT:
		return Rect2(Vector2.ZERO, size)
	var bounded_width := floorf(size.y * WIDE_ASPECT)
	return Rect2(Vector2(floorf((size.x - bounded_width) * 0.5), 0.0), Vector2(bounded_width, size.y))


static func scale_for(size: Vector2, scale_mode: String) -> float:
	if scale_mode != PresentationSettings.UI_SCALE_AUTO and scale_mode in PresentationSettings.UI_SCALE_MODES:
		return float(scale_mode) / 100.0
	return clampf(minf(size.x / WIDE_MINIMUM.x, size.y / WIDE_MINIMUM.y), 1.0, 3.0)
