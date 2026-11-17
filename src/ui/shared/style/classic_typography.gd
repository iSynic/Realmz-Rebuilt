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
## UI symbols (check marks, arrows, command glyphs) are absent from every bundled text face. Godot
## sizes a line by the tallest font in its fallback chain, so no font chain carries a platform symbol
## font: symbol-only labels use the SymbolGlyph role, and other text relies on Godot's per-glyph system
## fallback, which enlarges only the lines that actually draw a symbol.
## A platform with no system fonts (the web) has neither, so there the bundled symbol faces join every
## chain. Their line box is cut down to fit inside the text faces', so they stretch no line.
const SYMBOL_FACE_PATHS: Array[String] = [
	"res://src/ui/shared/assets/fonts/NotoSansSymbols2-Realmz.ttf",
	"res://src/ui/shared/assets/fonts/NotoSansSymbols-Realmz.ttf",
	"res://src/ui/shared/assets/fonts/NotoSansMath-Realmz.ttf",
]
## The text faces the symbol faces follow. Black Chancery is left out: its line box is shorter than
## the symbol faces', it sets headings only, and no heading draws a symbol.
const SYMBOL_HOST_PATHS: Array[String] = [THELDROW_PATH, CHICAGO_PATH, CLASSIC_UTILITY_PATH, READABLE_UI_PATH, READABLE_BOLD_PATH, READABLE_NARRATIVE_PATH]
## Menu workspaces root on this theme; it authors a readable sans that follows only an explicit
## interface font choice. The main menu pins its own typography and never follows either.
## The interface font identity that keeps the original Realmz faces.
const CLASSIC_FACES := "classic"
const MENU_THEME_PATH := "res://src/ui/shared/style/menu_controls_theme.tres"

## Holds the text faces that received the symbol faces. A font nobody holds is freed and loaded again
## without them.
static var _symbol_hosts: Array[Font] = []


static func themed_copy(base_theme: Theme, settings: PresentationSettings, interface_size: float = 1.0, fonts: FontResolver = null) -> Theme:
	if OS.has_feature("web"):
		install_symbol_faces(base_theme)
	var result := base_theme.duplicate() as Theme
	ClassicChrome.modernize(result)
	var font_scale := interface_size * settings.interface_text_scale
	var authored_runtime_size := base_theme.get_constant(&"default_font_size", &"ClassicRuntimeMetrics") if base_theme.has_constant(&"default_font_size", &"ClassicRuntimeMetrics") else base_theme.default_font_size
	result.default_font_size = maxi(1, roundi(authored_runtime_size * font_scale))
	_scale_theme(result, interface_size, font_scale, interface_size * settings.narrative_text_scale)
	_apply_font_choices(result, settings, fonts)
	UiThemeService.restyle_menu_types(result)
	return result


## Points the shared menu theme at the player's chosen interface font, or back to its authored sans.
## Call only where the applied application theme changes, never for draft previews.
static func apply_menu_fonts(settings: PresentationSettings, fonts: FontResolver = null) -> void:
	var theme := load(MENU_THEME_PATH) as Theme
	if not theme.has_meta(&"authored_font"):
		theme.set_meta(&"authored_font", theme.default_font)
	# Resolving returns a fresh variation each call; skip unchanged choices so menus don't re-theme.
	if theme.has_meta(&"applied_identity") and String(theme.get_meta(&"applied_identity")) == settings.interface_font:
		return
	theme.set_meta(&"applied_identity", settings.interface_font)
	var authored: Font = theme.get_meta(&"authored_font")
	var selected := authored
	if not settings.interface_font.is_empty():
		selected = (fonts if fonts != null else FontResolver.new()).resolve(settings.interface_font, authored)
	for type_name: StringName in theme.get_font_type_list():
		for key: StringName in theme.get_font_list(type_name):
			theme.set_font(key, type_name, selected)
	theme.default_font = selected


static func _apply_font_choices(theme: Theme, settings: PresentationSettings, fonts: FontResolver) -> void:
	theme.set_constant(&"custom_font_selected", &"ClassicNarrative", 0 if settings.narrative_font.is_empty() else 1)
	theme.set_font(&"font", &"ClassicNarrativeText", theme.get_font(&"normal_font", &"ClassicNarrative"))
	theme.set_font_size(&"font_size", &"ClassicNarrativeText", theme.get_font_size(&"normal_font_size", &"ClassicNarrative"))
	if fonts == null:
		fonts = FontResolver.new()
	# Interface text is the readable sans unless the player picks a face; the original
	# Realmz faces remain available under the CLASSIC_FACES identity.
	if settings.interface_font != CLASSIC_FACES:
		var selected := load(READABLE_UI_PATH) as Font if settings.interface_font.is_empty() else fonts.resolve(settings.interface_font, load(READABLE_UI_PATH) as Font)
		theme.default_font = selected
		for type_name: StringName in theme.get_type_list():
			if type_name in [&"ClassicNarrative", &"ClassicNarrativeText", &"SymbolGlyph"]:
				continue
			for key: StringName in theme.get_font_list(type_name):
				theme.set_font(key, type_name, selected)
		for type_name: StringName in [&"Label", &"Button", &"CheckButton", &"LineEdit", &"TextEdit", &"OptionButton", &"ItemList", &"MenuButton", &"PopupMenu"]:
			theme.set_font(&"font", type_name, selected)
	# Narrative keeps its Classic default when ordinary interface text is overridden.
	var preset := theme.get_font(&"normal_font", &"ClassicNarrative")
	var narrative := fonts.resolve(settings.narrative_font, load(READABLE_NARRATIVE_PATH) as Font) if not settings.narrative_font.is_empty() else preset
	theme.set_font(&"font", &"ClassicNarrativeText", narrative)
	for key: StringName in [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]:
		theme.set_font(key, &"ClassicNarrative", narrative)


static func _scale_theme(theme: Theme, interface_size: float, font_scale: float, narrative_scale: float) -> void:
	var scaled_styles: Dictionary = {}
	for type_name: StringName in theme.get_type_list():
		for key: StringName in theme.get_font_size_list(type_name):
			var scale := narrative_scale if type_name in [&"ClassicNarrative", &"ClassicNarrativeText"] else font_scale
			theme.set_font_size(key, type_name, maxi(1, roundi(theme.get_font_size(key, type_name) * scale)))
		for key: StringName in theme.get_constant_list(type_name):
			theme.set_constant(key, type_name, roundi(theme.get_constant(key, type_name) * interface_size))
		for key: StringName in theme.get_icon_list(type_name):
			var image := theme.get_icon(key, type_name).get_image().duplicate() as Image
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


## Adds the bundled symbol faces behind the bundled text faces and the theme's SymbolGlyph role.
## The text faces are shared resources, so every theme made afterwards has the symbols.
static func install_symbol_faces(base_theme: Theme) -> void:
	if _symbol_hosts.is_empty():
		for path: String in SYMBOL_HOST_PATHS:
			_add_symbol_faces(load(path) as Font)
	if base_theme.has_font(&"font", &"SymbolGlyph"):
		_add_symbol_faces(base_theme.get_font(&"font", &"SymbolGlyph"))


static func _add_symbol_faces(host: Font) -> void:
	if _symbol_hosts.has(host):
		return
	_symbol_hosts.append(host)
	var fallbacks := host.fallbacks
	for path: String in SYMBOL_FACE_PATHS:
		fallbacks.append(load(path) as Font)
	host.fallbacks = fallbacks
