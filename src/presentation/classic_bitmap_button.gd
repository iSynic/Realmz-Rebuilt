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
var _label: String = ""


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ignore_texture_size = true
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	pressed.connect(func() -> void: command_requested.emit(command_id))


func configure(definition: Dictionary, art_scale: int = 1) -> void:
	command_id = StringName(definition.get("id", &""))
	var asset_id := StringName(definition.get("asset_id", &""))
	_art_texture = ClassicUiAssetCatalog.texture(asset_id)
	texture_normal = null
	_native_size = ClassicUiAssetCatalog.native_size(asset_id)
	if _native_size.x <= 0 or _native_size.y <= 0:
		_native_size = Vector2i(50, 50)
	tooltip_text = String(definition.get("tooltip", ""))
	_label = String(definition.get("label", "Command"))
	var accelerator := String(definition.get("accelerator", ""))
	if not accelerator.is_empty():
		tooltip_text += " [%s]" % accelerator
	set_art_scale(art_scale)


func set_art_scale(value: int) -> void:
	_art_scale = 2 if value >= 2 else 1
	custom_minimum_size = Vector2(maxi(_native_size.x * _art_scale + 6, 62), _native_size.y * _art_scale + 6) if _art_texture != null else Vector2(62.0, 56.0)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	draw_rect(rect, SURFACE_COLOR, true)
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), EDGE_LIGHT, 2.0)
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), EDGE_LIGHT, 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, SURFACE_DARK, 2.0)
	draw_line(Vector2(rect.end.x, rect.position.y), rect.end, SURFACE_DARK, 2.0)
	var pressed_offset := Vector2.ONE if button_pressed else Vector2.ZERO
	var font := get_theme_font("font", "Button")
	var font_size := maxi(11, get_theme_font_size("font_size", "Button") - 2)
	if _art_texture != null:
		var art_size := Vector2(_native_size * _art_scale)
		var art_rect := Rect2(Vector2(floorf((size.x - art_size.x) * 0.5), floorf((size.y - art_size.y) * 0.5)) + pressed_offset, art_size)
		draw_texture_rect(_art_texture, art_rect, false)
	else:
		draw_string(font, Vector2(4.0, size.y * 0.5 + font_size * 0.35) + pressed_offset, _label, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, font_size, CAPTION_COLOR)
	if disabled:
		draw_rect(rect, DISABLED_OVERLAY, true)
	elif button_pressed:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.76, 0.24, 0.14), true)
	if has_focus():
		draw_rect(rect, FOCUS_COLOR, false, 2.0)
	elif is_hovered() and not disabled:
		draw_rect(rect, HOVER_COLOR, false, 1.0)
