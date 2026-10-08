## Presents Classic typography through the Godot interface.

class_name ClassicTypography
extends RefCounted

const BLACK_CHANCERY_PATH := "res://src/ui/shared/assets/fonts/BlackChancery-Realmz.ttf"
const THELDROW_BITMAP_PATH := "res://src/ui/shared/assets/fonts/Theldrow-Classic.fnt"
const THELDROW_PATH := "res://src/ui/shared/assets/fonts/Theldrow-Rebuilt.ttf"
const CHICAGO_PATH := "res://src/ui/shared/assets/fonts/ChicagoFLF.ttf"
const CLASSIC_UTILITY_PATH := "res://src/ui/shared/assets/fonts/InterVariable-Castle.ttf"
const READABLE_UI_PATH := "res://src/ui/shared/assets/fonts/AlegreyaSans-Regular.ttf"
const READABLE_BOLD_PATH := "res://src/ui/shared/assets/fonts/AlegreyaSans-Bold.ttf"
const READABLE_NARRATIVE_PATH := "res://src/ui/shared/assets/fonts/Alegreya-Variable.ttf"


static func themed_copy(base_theme: Theme, settings: PresentationSettings, interface_size: float = 1.0) -> Theme:
	var result := base_theme.duplicate() as Theme
	result.add_type(&"ClassicTheldrowLineEdit")
	result.set_type_variation(&"ClassicTheldrowLineEdit", &"LineEdit")
	result.add_type(&"ClassicTheldrowOptionButton")
	result.set_type_variation(&"ClassicTheldrowOptionButton", &"OptionButton")
	result.add_type(&"ClassicTheldrowButton")
	result.set_type_variation(&"ClassicTheldrowButton", &"Button")
	result.add_type(&"ClassicUnidentifiedItem")
	result.set_type_variation(&"ClassicUnidentifiedItem", &"Label")
	var classic_mode := settings.typography_mode == PresentationSettings.TYPOGRAPHY_CLASSIC
	var font_scale := interface_size * settings.text_scale
	result.default_font_size = int(round((17.0 if classic_mode else 15.0) * font_scale))
	_scale_theme(result, interface_size, font_scale)
	if not classic_mode:
		return result
	var readable_ui := load(READABLE_UI_PATH) as Font
	var readable_bold := load(READABLE_BOLD_PATH) as Font
	var readable_narrative := load(READABLE_NARRATIVE_PATH) as Font
	var body := _with_fallback(THELDROW_PATH, readable_ui)
	var ornament := _with_fallback(BLACK_CHANCERY_PATH, readable_bold)
	var utility := _with_fallback(CLASSIC_UTILITY_PATH, readable_ui)
	result.default_font = body
	result.set_font(&"font", &"ClassicRosterText", body)
	result.set_font(&"font", &"ClassicRosterAuto", body)
	for type_name: StringName in [&"Label", &"CheckButton"]:
		result.set_font(&"font", type_name, body)
	for type_name: StringName in [&"LineEdit", &"OptionButton", &"ItemList"]:
		result.set_font(&"font", type_name, utility)
	result.set_font(&"normal_font", &"RichTextLabel", body)
	result.set_font(&"font", &"Button", ornament)
	result.set_font(&"font", &"BattleCommandButton", ornament)
	result.set_font(&"font", &"ClassicChoiceButton", ornament)
	result.set_font(&"font", &"ClassicHeading", ornament)
	result.set_font(&"font", &"ClassicCommandCaption", ornament)
	result.set_font(&"normal_font", &"ClassicNarrative", _with_fallback(THELDROW_PATH, readable_narrative))
	result.set_font(&"font", &"MenuButton", body)
	result.set_font(&"font", &"PopupMenu", body)
	result.set_font(&"font", &"ClassicUtility", utility)
	result.set_font(&"font", &"ClassicTheldrowLineEdit", body)
	result.set_font(&"font", &"ClassicTheldrowOptionButton", body)
	result.set_font(&"font", &"ClassicTheldrowButton", body)
	result.set_font(&"font", &"ClassicUnidentifiedItem", body)
	result.set_color(&"font_color", &"ClassicUnidentifiedItem", Color.TRANSPARENT)
	result.set_color(&"font_outline_color", &"ClassicUnidentifiedItem", Color("8fcfd1"))
	result.set_constant(&"outline_size", &"ClassicUnidentifiedItem", 2)
	result.set_font(&"font", &"Classic3DHelp", _with_fallback(CHICAGO_PATH, readable_ui))
	return result


static func _scale_theme(theme: Theme, interface_size: float, font_scale: float) -> void:
	var scaled_styles: Dictionary = {}
	for type_name: StringName in theme.get_type_list():
		for key: StringName in theme.get_font_size_list(type_name):
			theme.set_font_size(key, type_name, maxi(1, roundi(theme.get_font_size(key, type_name) * font_scale)))
		for key: StringName in theme.get_constant_list(type_name):
			theme.set_constant(key, type_name, roundi(theme.get_constant(key, type_name) * interface_size))
		for key: StringName in theme.get_icon_list(type_name):
			var image := theme.get_icon(key, type_name).get_image()
			var scale := clampi(roundi(interface_size), 1, 3)
			image.resize(image.get_width() * scale, image.get_height() * scale, Image.INTERPOLATE_NEAREST)
			theme.set_icon(key, type_name, ImageTexture.create_from_image(image))
		for key: StringName in theme.get_stylebox_list(type_name):
			var style := theme.get_stylebox(key, type_name)
			if not scaled_styles.has(style):
				var scaled := style.duplicate() as StyleBox
				for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
					scaled.set_content_margin(side, scaled.get_content_margin(side) * interface_size)
				scaled_styles[style] = scaled
			theme.set_stylebox(key, type_name, scaled_styles[style])


static func _with_fallback(path: String, fallback: Font) -> Font:
	var source := load(path) as Font
	if source == null:
		return fallback
	var result := FontVariation.new()
	result.base_font = source
	var fallbacks: Array[Font] = []
	if fallback != null:
		fallbacks.append(fallback)
	result.fallbacks = fallbacks
	return result
