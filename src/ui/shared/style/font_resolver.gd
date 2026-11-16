## Resolves selected presentation fonts without changing shared imported resources.
class_name FontResolver
extends RefCounted

class Choice:
	extends RefCounted
	var id: String
	var name: String
	var group: String
	func _init(identity: String, label: String, source_group: String) -> void:
		id = identity
		name = label
		group = source_group

const BUNDLED: Dictionary = {
	"theldrow": ["Theldrow Rebuilt", "res://src/ui/shared/assets/fonts/Theldrow-Rebuilt.ttf"],
	"black-chancery": ["Black Chancery", "res://src/ui/shared/assets/fonts/BlackChancery-Realmz.ttf"],
	"chicago": ["Chicago", "res://src/ui/shared/assets/fonts/ChicagoFLF.ttf"],
	"inter": ["Inter", "res://src/ui/shared/assets/fonts/InterVariable-Castle.ttf"],
	"alegreya-sans": ["Alegreya Sans", "res://src/ui/shared/assets/fonts/AlegreyaSans-Regular.ttf"],
	"alegreya-sans-bold": ["Alegreya Sans Bold", "res://src/ui/shared/assets/fonts/AlegreyaSans-Bold.ttf"],
	"alegreya": ["Alegreya", "res://src/ui/shared/assets/fonts/Alegreya-Variable.ttf"],
}

## Some installed families (such as Windows' Sans Serif Collection, whose lines are 2.7 times the
## font size) declare line metrics far taller than their Latin glyphs. A chosen font whose ascent or
## descent exceeds these multiples of its size is capped to them at every size it can be drawn at,
## so labels, rows and buttons keep ordinary line height. Ordinary fonts are left untouched.
const MAX_ASCENT_RATIO := 1.15
const MAX_DESCENT_RATIO := 0.32
const METRIC_PROBE_SIZE := 16
const METRIC_SIZES := Vector2i(6, 160)

var _imported: Array[Choice] = []
var _import_path: Callable
var _fonts: Dictionary = {}
var _system_names: PackedStringArray
var _system_enumerated := false


func configure_imports(choices: Array[Choice], path_for_identity: Callable) -> void:
	_imported = choices.duplicate()
	_import_path = path_for_identity
	_fonts.clear()


func choices() -> Array[Choice]:
	var result: Array[Choice] = [Choice.new("", "Classic fonts", "")]
	for id: String in BUNDLED:
		result.append(Choice.new("bundled:" + id, BUNDLED[id][0], "Bundled"))
	if not _system_enumerated:
		_system_names = OS.get_system_fonts()
		_system_names.sort()
		_system_enumerated = true
		_fonts.clear()
	for family: String in _system_names:
		result.append(Choice.new("system:" + family, family, "System"))
	result.append_array(_imported)
	return result


func label(identity: String) -> String:
	if identity.is_empty():
		return "Classic fonts"
	if identity.begins_with("bundled:"):
		return String(BUNDLED.get(identity.trim_prefix("bundled:"), ["Unavailable bundled font"])[0])
	if identity.begins_with("system:"):
		return identity.trim_prefix("system:")
	for choice: Choice in _imported:
		if choice.id == identity:
			return choice.name
	return "Unavailable imported font"


func resolve(identity: String, fallback: Font) -> Font:
	if identity.is_empty():
		return fallback
	var selected := _source(identity)
	if selected == null:
		return fallback
	var variation := FontVariation.new()
	variation.base_font = selected
	variation.fallbacks = [fallback] if fallback != null else []
	return variation


## Whether a font's line metrics exceed the ordinary ascent/descent multiples.
static func has_tall_metrics(font: Font) -> bool:
	var size := METRIC_PROBE_SIZE
	return font.get_ascent(size) > ceilf(MAX_ASCENT_RATIO * size) or font.get_descent(size) > ceilf(MAX_DESCENT_RATIO * size)


## Caps a dynamic font's per-size ascent and descent at the ordinary multiples. Godot keeps one
## metric cache per drawn size, so every size in METRIC_SIZES receives its own capped values.
static func cap_line_metrics(font: FontFile) -> FontFile:
	for size: int in range(METRIC_SIZES.x, METRIC_SIZES.y + 1):
		font.set_cache_ascent(0, size, minf(font.get_ascent(size), ceilf(MAX_ASCENT_RATIO * size)))
		font.set_cache_descent(0, size, minf(font.get_descent(size), ceilf(MAX_DESCENT_RATIO * size)))
	return font


func unavailable_message(identity: String) -> String:
	return "%s is unavailable. Using the bundled readable font." % label(identity) if not identity.is_empty() and _source(identity) == null else ""


func _source(identity: String) -> Font:
	if _fonts.has(identity):
		return _fonts[identity] as Font
	var font: Font
	if identity.begins_with("bundled:"):
		var entry: Array = BUNDLED.get(identity.trim_prefix("bundled:"), [])
		if not entry.is_empty():
			font = load(entry[1]) as Font
	elif identity.begins_with("system:"):
		font = _system_source(identity.trim_prefix("system:"))
	elif identity.begins_with("imported:") and _import_path.is_valid():
		var path := String(_import_path.call(identity.trim_prefix("imported:")))
		if not path.is_empty():
			var candidate := FontFile.new()
			if candidate.load_dynamic_font(path) == OK:
				font = cap_line_metrics(candidate) if has_tall_metrics(candidate) else candidate
	_fonts[identity] = font
	return font


func _system_source(family: String) -> Font:
	var path := OS.get_system_font_path(family)
	if path.is_empty():
		return null
	var probe := FontFile.new()
	if probe.load_dynamic_font(path) != OK:
		return null
	# Windows requires an existing family; other platforms may return a substitute.
	if not OS.has_feature("windows") and probe.get_font_name().nocasecmp_to(family) != 0 and not (_system_enumerated and family in _system_names):
		return null
	var font := SystemFont.new()
	font.font_names = PackedStringArray([family])
	# Glyphs missing from the family and its readable fallback chain (such as UI symbols) come from
	# the platform per glyph; that fallback never changes the height of lines that don't use it.
	font.allow_system_fallback = true
	if not has_tall_metrics(font):
		return font
	# Capping needs the family's own file; a collection file holds several faces.
	probe.antialiasing = font.antialiasing
	probe.hinting = font.hinting
	probe.subpixel_positioning = font.subpixel_positioning
	probe.allow_system_fallback = true
	for face: int in probe.get_face_count():
		probe.set_face_index(0, face)
		if probe.get_font_name().nocasecmp_to(family) == 0:
			return cap_line_metrics(probe)
	probe.set_face_index(0, 0)
	return cap_line_metrics(probe)
