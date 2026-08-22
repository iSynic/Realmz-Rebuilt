class_name ClassicBitmapButton
extends TextureButton

signal command_requested(command_id: StringName)

const FOCUS_COLOR := Color("f8e36f")
const HOVER_COLOR := Color("80d6e7")
const DISABLED_OVERLAY := Color(0.04, 0.05, 0.055, 0.64)
const CAPTION_COLOR := Color("e7c756")
const SURFACE_COLOR := Color("171a1d")
const SURFACE_DARK := Color("080a0c")
const EDGE_LIGHT := Color("686b68")

var command_id: StringName
var _native_size := Vector2i(50, 50)
var _art_scale: int = 1
var _art_texture: Texture2D
var _pressed_art_texture: Texture2D
var _label: String = ""
var _symbol: StringName = &""
var _physical_pressed: bool = false
var _visual_pressed: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ignore_texture_size = true
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(func() -> void: _physical_pressed = true; queue_redraw())
	button_up.connect(func() -> void: _physical_pressed = false; queue_redraw())
	pressed.connect(func() -> void: command_requested.emit(command_id))


func configure(definition: Dictionary, art_scale: int = 1) -> void:
	command_id = StringName(definition.get("id", &""))
	var asset_id := StringName(definition.get("asset_id", &""))
	var pressed_asset_id := StringName(definition.get("pressed_asset_id", &""))
	_art_texture = ClassicUiAssetCatalog.texture(asset_id)
	_pressed_art_texture = ClassicUiAssetCatalog.texture(pressed_asset_id)
	texture_normal = null
	_native_size = ClassicUiAssetCatalog.native_size(asset_id)
	var pressed_native_size := ClassicUiAssetCatalog.native_size(pressed_asset_id)
	_native_size = Vector2i(maxi(_native_size.x, pressed_native_size.x), maxi(_native_size.y, pressed_native_size.y))
	if _native_size.x <= 0 or _native_size.y <= 0:
		_native_size = Vector2i(50, 50)
	tooltip_text = String(definition.get("tooltip", ""))
	_label = String(definition.get("label", "Command"))
	_symbol = StringName(definition.get("symbol", &""))
	toggle_mode = bool(definition.get("toggle_mode", false))
	var accelerator := String(definition.get("accelerator", ""))
	if not accelerator.is_empty():
		tooltip_text += " [%s]" % accelerator
	set_art_scale(art_scale)


func set_art_scale(value: int) -> void:
	_art_scale = 2 if value >= 2 else 1
	custom_minimum_size = Vector2(maxi(_native_size.x * _art_scale + 6, 62), _native_size.y * _art_scale + 6) if _art_texture != null else Vector2(62.0, 56.0)
	queue_redraw()


func set_visual_pressed(value: bool) -> void:
	if _visual_pressed == value:
		return
	_visual_pressed = value
	queue_redraw()


func is_visually_pressed() -> bool:
	return _physical_pressed or _visual_pressed or button_pressed


func _draw() -> void:
	var rect := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	var pressed := is_visually_pressed()
	var surface_name := &"disabled" if disabled else &"pressed" if pressed else &"hover" if is_hovered() else &"normal"
	var surface := get_theme_stylebox(surface_name, &"Button")
	if surface != null:
		draw_style_box(surface, rect)
	else:
		draw_rect(rect, SURFACE_COLOR, true)
		var leading_edge := SURFACE_DARK if pressed else EDGE_LIGHT
		var trailing_edge := EDGE_LIGHT if pressed else SURFACE_DARK
		draw_line(rect.position, Vector2(rect.end.x, rect.position.y), leading_edge, 2.0)
		draw_line(rect.position, Vector2(rect.position.x, rect.end.y), leading_edge, 2.0)
		draw_line(Vector2(rect.position.x, rect.end.y), rect.end, trailing_edge, 2.0)
		draw_line(Vector2(rect.end.x, rect.position.y), rect.end, trailing_edge, 2.0)
	var pressed_offset := Vector2.ONE if pressed else Vector2.ZERO
	var font := get_theme_font("font", "Button")
	var font_size := maxi(11, get_theme_font_size("font_size", "Button") - 2)
	var displayed_texture := _pressed_art_texture if pressed and _pressed_art_texture != null else _art_texture
	if displayed_texture != null:
		var art_size := Vector2(_native_size * _art_scale)
		var art_rect := Rect2(Vector2(floorf((size.x - art_size.x) * 0.5), floorf((size.y - art_size.y) * 0.5)) + pressed_offset, art_size)
		draw_texture_rect(displayed_texture, art_rect, false)
	elif _symbol == &"yin_yang":
		_draw_yin_yang(Vector2(size.x * 0.5, 19.0) + pressed_offset, 12.0)
		var caption_width := size.x - 8.0
		var caption_size := fitted_caption_font_size(font, _label, caption_width, font_size)
		draw_string(font, Vector2(4.0, size.y - 7.0) + pressed_offset, _label, HORIZONTAL_ALIGNMENT_CENTER, caption_width, caption_size, CAPTION_COLOR)
	else:
		draw_string(font, Vector2(4.0, size.y * 0.5 + font_size * 0.35) + pressed_offset, _label, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, font_size, CAPTION_COLOR)
	if disabled:
		draw_rect(rect, DISABLED_OVERLAY, true)
	elif pressed:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.76, 0.24, 0.14), true)
	if has_focus():
		draw_rect(rect, FOCUS_COLOR, false, 2.0)
	elif is_hovered() and not disabled:
		draw_rect(rect, HOVER_COLOR, false, 1.0)


static func fitted_caption_font_size(font: Font, caption: String, available_width: float, requested_size: int) -> int:
	var candidate := maxi(8, requested_size)
	while candidate > 8 and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, candidate).x > available_width:
		candidate -= 1
	return candidate


func _draw_yin_yang(center: Vector2, radius: float) -> void:
	draw_circle(center, radius, Color("e9e4d2"))
	var dark := Color("141619")
	var half: PackedVector2Array = [center]
	for index: int in 17:
		var angle := PI * 0.5 + PI * float(index) / 16.0
		half.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(half, dark)
	draw_circle(center + Vector2(0.0, -radius * 0.5), radius * 0.5, dark)
	draw_circle(center + Vector2(0.0, radius * 0.5), radius * 0.5, Color("e9e4d2"))
	draw_circle(center + Vector2(0.0, -radius * 0.5), radius * 0.12, Color("e9e4d2"))
	draw_circle(center + Vector2(0.0, radius * 0.5), radius * 0.12, dark)
	draw_arc(center, radius, 0.0, TAU, 32, CAPTION_COLOR, 1.0, true)
