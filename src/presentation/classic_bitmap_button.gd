class_name ClassicBitmapButton
extends TextureButton

signal command_requested(command_id: StringName)

const FOCUS_COLOR := Color("f8e36f")
const HOVER_COLOR := Color("80d6e7")
const DISABLED_OVERLAY := Color(0.04, 0.05, 0.055, 0.64)

var command_id: StringName
var _native_size := Vector2i(50, 50)
var _art_scale: int = 1


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ignore_texture_size = true
	stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
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
	texture_normal = ClassicUiAssetCatalog.texture(asset_id)
	_native_size = ClassicUiAssetCatalog.native_size(asset_id)
	if _native_size.x <= 0 or _native_size.y <= 0:
		_native_size = Vector2i(50, 50)
	tooltip_text = String(definition.get("tooltip", ""))
	var accelerator := String(definition.get("accelerator", ""))
	if not accelerator.is_empty():
		tooltip_text += " [%s]" % accelerator
	set_art_scale(art_scale)


func set_art_scale(value: int) -> void:
	_art_scale = 2 if value >= 2 else 1
	custom_minimum_size = Vector2(_native_size * _art_scale) + Vector2(6.0, 6.0)
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	if disabled:
		draw_rect(rect, DISABLED_OVERLAY, true)
	if button_pressed:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.76, 0.24, 0.18), true)
	if has_focus():
		draw_rect(rect, FOCUS_COLOR, false, 2.0)
	elif is_hovered() and not disabled:
		draw_rect(rect, HOVER_COLOR, false, 1.0)
