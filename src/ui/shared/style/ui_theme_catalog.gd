## The interface themes the player can choose in Preferences › Display.

class_name UiThemeCatalog
extends RefCounted

## The authored look's id: the palette colours are mapped from, and the fallback for an unknown id.
## It is not the theme a new profile starts with (`PresentationSettings.DEFAULT_INTERFACE_THEME`).
const DEFAULT_ID := PresentationSettings.AUTHORED_INTERFACE_THEME
const SLATE_TILE := "res://src/ui/shared/assets/ui/themes/slate-wall-tile.png"

## Art made for one theme lives here as `<theme id>-tile.png`, `<theme id>-frame.png` (tinted
## with the accent) or `<theme id>-frame-color.png` (drawn as painted). A file that exists is
## picked up without code changes; see docs/features/interface-theme-art-brief.md.
const THEME_ART_DIR := "res://src/ui/shared/assets/ui/themes/"
## Dimming used for a theme that gains a tile but was authored flat.
const DEFAULT_TILE_DIM := 0.2

static var _palettes: Array[UiThemePalette] = []


static func all() -> Array[UiThemePalette]:
	if _palettes.is_empty():
		_palettes = _build()
		for palette: UiThemePalette in _palettes:
			adopt_theme_art(palette, THEME_ART_DIR)
	return _palettes


## The palette for `theme_id`; an unknown id (a theme since removed) gives the default.
static func by_id(theme_id: String) -> UiThemePalette:
	for palette: UiThemePalette in all():
		if palette.id == theme_id:
			return palette
	return all()[0]


static func default_palette() -> UiThemePalette:
	return all()[0]


## {label, id} entries for a Preferences option picker.
static func options() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for palette: UiThemePalette in all():
		result.append({"label": palette.title, "id": palette.id})
	return result


## Points `palette` at any art named after its id in `directory`.
static func adopt_theme_art(palette: UiThemePalette, directory: String) -> void:
	var tile := "%s%s-tile.png" % [directory, palette.id]
	if ResourceLoader.exists(tile):
		palette.background_texture = tile
		if palette.background_dim <= 0.0:
			palette.background_dim = DEFAULT_TILE_DIM
	for suffix: String in ["-frame-color.png", "-frame.png"]:
		var frame := "%s%s%s" % [directory, palette.id, suffix]
		if ResourceLoader.exists(frame):
			palette.frame_texture = frame
			palette.frame_tinted = suffix == "-frame.png"
			return


## Colours per theme: backdrop, surface, raised, border, field, selected, accent, accent text, text, muted, good, bad.
static func _build() -> Array[UiThemePalette]:
	var slate: Array[String] = ["0b0e10", "151a1e", "1b2227", "2c363d", "232c32"]
	var slate_text: Array[String] = ["e3e8ea", "8b9ba3", "79cf9a"]
	return [
		UiThemePalette.new(DEFAULT_ID, "Midnight Gold", ["0a0f14", "15222f", "1a2b39", "2a3f4d", "263f4c", "24343d", "ddba6a", "101a24", "e2e2da", "8fa3ae", "75c889", "ef7770"]),
		# The default colours over a canvas tile; the default theme itself stays exactly as authored.
		# Shown as Midnight Canvas; the id keeps its first name so saved choices and the tile file still match.
		UiThemePalette.new("midnight-leather", "Midnight Canvas", ["0a0f14", "15222f", "1a2b39", "2a3f4d", "263f4c", "24343d", "ddba6a", "101a24", "e2e2da", "8fa3ae", "75c889", "ef7770"]).with_frame(&"gilt"),
		UiThemePalette.new("slate-gold", "Slate Gold", slate + (["2a2619", "ddba6a", "1c1405"] as Array[String]) + slate_text + (["ee7a74"] as Array[String])).with_background(SLATE_TILE, 0.45, &"metal"),
		UiThemePalette.new("slate-bone", "Slate Bone", slate + (["282927", "d8d2c2", "16150f"] as Array[String]) + slate_text + (["ee7a74"] as Array[String])).with_background(SLATE_TILE, 0.45, &"flourish"),
		UiThemePalette.new("slate-copper", "Slate Copper", slate + (["2e2119", "e0894b", "1c0d04"] as Array[String]) + slate_text + (["f07a8a"] as Array[String])).with_background(SLATE_TILE, 0.45, &"metal"),
		UiThemePalette.new("slate-ice", "Slate Ice", slate + (["1f2c33", "7fc7d9", "0b1418"] as Array[String]) + slate_text + (["ee7a74"] as Array[String])).with_background(SLATE_TILE, 0.45, &"flourish"),
		UiThemePalette.new("ember", "Ember", ["120d0b", "1e1613", "271c18", "3d2b23", "33241e", "2f221c", "e0894b", "1a0f0a", "ede3da", "a8968a", "8fc47a", "f07a8a"]).with_frame(&"forged"),
		UiThemePalette.new("verdant", "Verdant", ["07100c", "0f1d17", "14271f", "22392d", "1a3026", "183026", "c6d77e", "0d160f", "e3eade", "8ea596", "7fcf8e", "ef7a6c"]).with_frame(&"vine"),
		UiThemePalette.new("arcane", "Arcane", ["0b0a16", "151327", "1c1932", "2e2a4c", "252143", "241f40", "b9a2ff", "140f26", "e7e4f3", "9893b8", "7fd1a4", "f07a8a"]).with_frame(&"flourish"),
		UiThemePalette.new("steel", "Steel", ["0b0e10", "151a1e", "1b2227", "2c363d", "232c32", "1f2c33", "7fc7d9", "0b1418", "e3e8ea", "8b9ba3", "79cf9a", "ee7a74"]).with_frame(&"metal"),
	]
