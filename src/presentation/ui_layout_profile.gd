class_name UiLayoutProfile
extends RefCounted

const COMPACT: StringName = &"compact"
const STANDARD: StringName = &"standard"
const WIDE: StringName = &"wide"

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
	var scale := UiLayoutProfile.scale_for(size, scale_mode)
	var effective_width := size.x / scale
	var art_scale := 2 if size.x >= 1600.0 and size.y >= 900.0 and scale_mode in [PresentationSettings.UI_SCALE_AUTO, PresentationSettings.UI_SCALE_150] else 1
	if effective_width < 960.0:
		return UiLayoutProfile.new(COMPACT, scale, 208.0 * scale, 156.0 * scale, 208.0 * scale, 1)
	if effective_width < 1280.0:
		return UiLayoutProfile.new(STANDARD, scale, 256.0 * scale, 176.0 * scale, 256.0 * scale, art_scale)
	return UiLayoutProfile.new(WIDE, scale, 288.0 * scale, 190.0 * scale, 288.0 * scale, art_scale)


static func scale_for(size: Vector2, scale_mode: String) -> float:
	match scale_mode:
		PresentationSettings.UI_SCALE_100:
			return 1.0
		PresentationSettings.UI_SCALE_125:
			return 1.25
		PresentationSettings.UI_SCALE_150:
			return 1.5
	if size.x >= 1920.0 and size.y >= 900.0:
		return 1.5
	if size.x >= 1440.0 and size.y >= 800.0:
		return 1.25
	return 1.0
