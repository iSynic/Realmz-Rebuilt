class_name UiLayoutProfile
extends RefCounted

const COMPACT: StringName = &"compact"
const WIDE: StringName = &"wide"
const WIDE_ASPECT: float = 16.0 / 9.0
const WIDE_MINIMUM := Vector2(1280.0, 720.0)

var id: StringName
var ui_scale: float
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
	party_width = party
	context_width = 0.0
	context_is_drawer = false
	navigation_uses_overflow = profile_id == COMPACT
	menu_height = 28.0 * scale
	bottom_height = bottom
	command_width = command
	bitmap_scale = art_scale


static func for_viewport(size: Vector2, scale_mode: String) -> UiLayoutProfile:
	var canvas_rect := UiLayoutProfile.application_rect_for(size)
	var canvas_size := canvas_rect.size
	var scale := UiLayoutProfile.scale_for(canvas_size, scale_mode)
	var effective_width := canvas_size.x / scale
	var art_scale := 2 if canvas_size.x >= 1600.0 and canvas_size.y >= 900.0 and scale_mode in [PresentationSettings.UI_SCALE_AUTO, PresentationSettings.UI_SCALE_150] else 1
	var profile: UiLayoutProfile
	if effective_width < 1280.0:
		profile = UiLayoutProfile.new(COMPACT, scale, 208.0 * scale, 156.0 * scale, 208.0 * scale, 1)
	else:
		profile = UiLayoutProfile.new(WIDE, scale, 352.0 * scale, 190.0 * scale, 288.0 * scale, art_scale)
	profile.application_rect = canvas_rect
	return profile


static func application_rect_for(size: Vector2) -> Rect2:
	if size.x < WIDE_MINIMUM.x or size.y < WIDE_MINIMUM.y or size.y <= 0.0 or size.x / size.y <= WIDE_ASPECT:
		return Rect2(Vector2.ZERO, size)
	var bounded_width := floorf(size.y * WIDE_ASPECT)
	return Rect2(Vector2(floorf((size.x - bounded_width) * 0.5), 0.0), Vector2(bounded_width, size.y))


static func scale_for(size: Vector2, scale_mode: String) -> float:
	match scale_mode:
		PresentationSettings.UI_SCALE_100:
			return 1.0
		PresentationSettings.UI_SCALE_125:
			return 1.25
		PresentationSettings.UI_SCALE_150:
			return 1.5
	if size.x >= 3840.0 and size.y >= 2160.0:
		return 3.0
	if size.x >= 2560.0 and size.y >= 1440.0:
		return 2.0
	if size.x >= 1920.0 and size.y >= 900.0:
		return 1.5
	if size.x >= 1440.0 and size.y >= 800.0:
		return 1.25
	return 1.0
