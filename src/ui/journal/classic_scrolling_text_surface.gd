## Owns Classic scrolling text surface presentation behavior for its scene-authored screen.

class_name ClassicScrollingTextSurface
extends PanelContainer

signal double_click_requested

const AUTO_SCROLL_PIXELS_PER_SECOND: float = 20.0
const MANUAL_SCROLL_PIXELS: float = 25.0
const BACKGROUND_RESOURCE_TYPE: String = "ppat"
const BACKGROUND_RESOURCE_ID: int = 129
const STYLE_RESOURCE_TYPE: String = "styl"
const STYLE_RUN_BYTES: int = 20
const DEFAULT_FONT_ID: int = 1601
const DEFAULT_FONT_SIZE: int = 10
const DEFAULT_INK := Color.BLACK

const FONT_ROLE_BODY: StringName = &"body"
const FONT_ROLE_ORNAMENT: StringName = &"ornament"
const FONT_ROLE_UTILITY: StringName = &"utility"
const FONT_ROLE_CHICAGO: StringName = &"chicago"

var _media: ClassicMediaCatalog
var _text: RichTextLabel
var _dragging: bool = false
var _last_drag_y: float = 0.0
var _fonts: Dictionary = {}


func configure(media: ClassicMediaCatalog, text_node_name: StringName = &"ClassicScrollingText") -> void:
	_media = media
	name = "ClassicScrollingTextSurface"
	theme_type_variation = &"ClassicTextWell"
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var background := get_node("ClassicScrollingTextStack/ClassicScrollingTextBackground") as TextureRect
	background.texture = _background_texture()
	_text = get_node("ClassicScrollingTextStack/ClassicScrollingTextMargin/ClassicScrollingText") as RichTextLabel
	_text.name = text_node_name
	_text.gui_input.connect(_on_text_input)
	set_process(true)


func present_asset(asset: MediaAsset, unavailable_text: String = "Scrolling text resource is unavailable.") -> bool:
	if asset == null or _media == null or asset.mime_type != "text/plain":
		present_text(unavailable_text)
		return false
	var text_bytes := _media.read_bytes(asset)
	if text_bytes.is_empty():
		present_text(unavailable_text)
		return false
	var style_asset := _media.asset_by_resource(STYLE_RESOURCE_TYPE, asset.resource_id)
	var style_bytes := _media.read_bytes(style_asset) if style_asset != null else PackedByteArray()
	present_text(text_bytes.get_string_from_utf8(), style_bytes)
	return true


func present_text(text: String, style_bytes: PackedByteArray = PackedByteArray()) -> void:
	if _text == null:
		return
	_text.clear()
	var runs := decode_style_runs(style_bytes, text.length())
	if runs.is_empty():
		_text.text = _normalized_text(text)
		return
	for index: int in runs.size():
		var run: Dictionary = runs[index]
		var start: int = run["start"]
		var finish: int = text.length() if index + 1 >= runs.size() else int(runs[index + 1]["start"])
		if finish <= start:
			continue
		var stack_depth := _push_style(run)
		_text.add_text(_normalized_text(text.substr(start, finish - start)))
		for _ignored: int in stack_depth:
			_text.pop()


func text_label() -> RichTextLabel:
	return _text


func advance(delta_seconds: float) -> void:
	if not _dragging:
		_scroll_by(automatic_scroll_distance(delta_seconds))


func _process(delta: float) -> void:
	advance(delta)


static func automatic_scroll_distance(delta_seconds: float) -> float:
	return maxf(0.0, delta_seconds) * AUTO_SCROLL_PIXELS_PER_SECOND


static func drag_scroll_delta(previous_y: float, current_y: float) -> float:
	if current_y < previous_y:
		return MANUAL_SCROLL_PIXELS
	if current_y > previous_y:
		return -MANUAL_SCROLL_PIXELS
	return 0.0


static func decode_style_runs(bytes: PackedByteArray, text_length: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if bytes.size() < 2:
		return result
	var count := _u16_be(bytes, 0)
	if count == 0 or bytes.size() < 2 + count * STYLE_RUN_BYTES:
		return result
	for index: int in count:
		var offset := 2 + index * STYLE_RUN_BYTES
		var start := _i32_be(bytes, offset)
		if start < 0 or start > text_length:
			continue
		result.append({
			"start": start,
			"source_order": index,
			"height": _i16_be(bytes, offset + 4),
			"ascent": _i16_be(bytes, offset + 6),
			"font": _i16_be(bytes, offset + 8),
			"face": int(bytes[offset + 10]),
			"size": _i16_be(bytes, offset + 12),
			"color": Color(
				float(_u16_be(bytes, offset + 14)) / 65535.0,
				float(_u16_be(bytes, offset + 16)) / 65535.0,
				float(_u16_be(bytes, offset + 18)) / 65535.0,
				1.0
			),
		})
	result.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		var left_start: int = int(left["start"])
		var right_start: int = int(right["start"])
		return left_start < right_start or (left_start == right_start and int(left["source_order"]) < int(right["source_order"]))
	)
	if not result.is_empty() and int(result[0]["start"]) > 0:
		result.push_front({"start": 0, "font": DEFAULT_FONT_ID, "face": 0, "size": DEFAULT_FONT_SIZE, "color": DEFAULT_INK})
	return result


static func classic_font_role(font_id: int) -> StringName:
	match font_id:
		0:
			return FONT_ROLE_CHICAGO
		1, 3, 4, 10, 16, 21:
			return FONT_ROLE_UTILITY
		1602:
			return FONT_ROLE_ORNAMENT
		_:
			return FONT_ROLE_BODY


static func classic_font_size(font_id: int, authored_size: int) -> int:
	if font_id == 4 and authored_size == 9:
		return 11
	if font_id == 21 and authored_size == 12:
		return 9
	return authored_size if authored_size > 0 else DEFAULT_FONT_SIZE


func _push_style(run: Dictionary) -> int:
	var depth := 0
	var font_id: int = int(run.get("font", DEFAULT_FONT_ID))
	var font := _font_for_role(classic_font_role(font_id))
	if font != null:
		_text.push_font(font)
		depth += 1
	_text.push_color(run["color"] as Color)
	depth += 1
	_text.push_font_size(classic_font_size(font_id, int(run["size"])))
	depth += 1
	var face: int = int(run["face"])
	if face & 1:
		_text.push_bold()
		depth += 1
	if face & 2:
		_text.push_italics()
		depth += 1
	if face & 4:
		_text.push_underline()
		depth += 1
	return depth


func _font_for_role(role: StringName) -> Font:
	if _fonts.has(role):
		return _fonts[role] as Font
	var path := ClassicTypography.THELDROW_PATH
	match role:
		FONT_ROLE_ORNAMENT:
			path = ClassicTypography.BLACK_CHANCERY_PATH
		FONT_ROLE_UTILITY:
			path = ClassicTypography.CLASSIC_UTILITY_PATH
		FONT_ROLE_CHICAGO:
			path = ClassicTypography.CHICAGO_PATH
	var source := load(path) as Font
	if source == null and role != FONT_ROLE_BODY:
		source = load(ClassicTypography.THELDROW_PATH) as Font
	_fonts[role] = source
	return source


func _background_texture() -> Texture2D:
	if _media == null:
		return null
	return _media.image_texture(_media.asset_by_resource(BACKGROUND_RESOURCE_TYPE, BACKGROUND_RESOURCE_ID))


func _on_text_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and button.double_click:
			_dragging = false
			double_click_requested.emit()
			accept_event()
			return
		_dragging = button.pressed
		_last_drag_y = button.position.y
		return
	var motion := event as InputEventMouseMotion
	if motion == null or not _dragging:
		return
	_scroll_by(drag_scroll_delta(_last_drag_y, motion.position.y))
	_last_drag_y = motion.position.y
	accept_event()


func _scroll_by(pixels: float) -> void:
	if _text == null or is_zero_approx(pixels):
		return
	var bar := _text.get_v_scroll_bar()
	if bar != null:
		bar.value = clampf(bar.value + pixels, bar.min_value, maxf(bar.min_value, bar.max_value - bar.page))


static func _normalized_text(text: String) -> String:
	return text.replace("\r\n", "\n").replace("\r", "\n")


static func _u16_be(bytes: PackedByteArray, offset: int) -> int:
	return int(bytes[offset]) * 256 + int(bytes[offset + 1])


static func _i16_be(bytes: PackedByteArray, offset: int) -> int:
	var value := _u16_be(bytes, offset)
	return value - 65536 if value >= 32768 else value


static func _i32_be(bytes: PackedByteArray, offset: int) -> int:
	var value := int(bytes[offset]) * 16777216 + int(bytes[offset + 1]) * 65536 + int(bytes[offset + 2]) * 256 + int(bytes[offset + 3])
	return value - 4294967296 if value >= 2147483648 else value
