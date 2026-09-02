class_name ClassicTypography
extends RefCounted

const BLACK_CHANCERY_PATH := "res://src/presentation/assets/fonts/BlackChancery-Realmz.ttf"
const THELDROW_BITMAP_PATH := "res://src/presentation/assets/fonts/Theldrow-Classic.fnt"
const THELDROW_PATH := "res://src/presentation/assets/fonts/Theldrow-Rebuilt.ttf"
const CHICAGO_PATH := "res://src/presentation/assets/fonts/ChicagoFLF.ttf"
const CLASSIC_UTILITY_PATH := "res://src/presentation/assets/fonts/InterVariable-Castle.ttf"
const READABLE_UI_PATH := "res://src/presentation/assets/fonts/AlegreyaSans-Regular.ttf"
const READABLE_BOLD_PATH := "res://src/presentation/assets/fonts/AlegreyaSans-Bold.ttf"
const READABLE_NARRATIVE_PATH := "res://src/presentation/assets/fonts/Alegreya-Variable.ttf"


static func themed_copy(base_theme: Theme, settings: PresentationSettings) -> Theme:
	var result := base_theme.duplicate(true) as Theme
	result.add_type(&"ClassicTheldrowLineEdit")
	result.set_type_variation(&"ClassicTheldrowLineEdit", &"LineEdit")
	result.add_type(&"ClassicTheldrowOptionButton")
	result.set_type_variation(&"ClassicTheldrowOptionButton", &"OptionButton")
	result.add_type(&"ClassicTheldrowButton")
	result.set_type_variation(&"ClassicTheldrowButton", &"Button")
	result.add_type(&"ClassicUnidentifiedItem")
	result.set_type_variation(&"ClassicUnidentifiedItem", &"Label")
	var classic_mode := settings.typography_mode == PresentationSettings.TYPOGRAPHY_CLASSIC
	result.default_font_size = int(round((17.0 if classic_mode else 15.0) * settings.text_scale))
	if not classic_mode:
		return result
	var readable_ui := load(READABLE_UI_PATH) as Font
	var readable_bold := load(READABLE_BOLD_PATH) as Font
	var readable_narrative := load(READABLE_NARRATIVE_PATH) as Font
	var body := _with_fallback(THELDROW_PATH, readable_ui)
	var ornament := _with_fallback(BLACK_CHANCERY_PATH, readable_bold)
	var utility := _with_fallback(CLASSIC_UTILITY_PATH, readable_ui)
	result.default_font = body
	for type_name: StringName in [&"Label", &"CheckButton"]:
		result.set_font(&"font", type_name, body)
	for type_name: StringName in [&"LineEdit", &"OptionButton", &"ItemList"]:
		result.set_font(&"font", type_name, utility)
	result.set_font(&"normal_font", &"RichTextLabel", body)
	result.set_font(&"font", &"Button", ornament)
	result.set_font(&"font", &"BattleCommandButton", ornament)
	result.set_font(&"font", &"ClassicChoiceButton", ornament)
	result.set_font(&"font", &"ClassicHeading", ornament)
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


static func _with_fallback(path: String, fallback: Font) -> Font:
	var source := load(path) as Font
	if source == null:
		return fallback
	var result := source.duplicate(true) as Font
	var fallbacks: Array[Font] = []
	if fallback != null:
		fallbacks.append(fallback)
	result.fallbacks = fallbacks
	return result
