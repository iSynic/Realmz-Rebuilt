## Presents Classic torch command button through the Godot interface.

class_name ClassicTorchCommandButton
extends BaseButton

signal command_requested(command_id: StringName)

const FLAME_FRAME_IDS: Array[StringName] = [
	&"torch.frame.146", &"torch.frame.147", &"torch.frame.148", &"torch.frame.149",
	&"torch.frame.150", &"torch.frame.151", &"torch.frame.152", &"torch.frame.153",
]
const BODY_ASSET_ID: StringName = &"torch.frame.154"
const FRAME_INTERVAL := 1.0 / 6.0
const FOCUS_COLOR := Color("f8e36f")
const HOVER_COLOR := Color("80d6e7")
const CAPTION_COLOR := Color("e7c756")
const SURFACE_DARK := Color("080a0c")
const EDGE_LIGHT := Color("686b68")
const DISABLED_OVERLAY := Color(0.04, 0.05, 0.055, 0.64)

@export var command_id: StringName = &"torch"
var _flame_frames: Array[Texture2D] = []
var _body_texture: Texture2D
var _light_remaining: int
var _has_torch: bool
var _frame_index: int
var _frame_elapsed: float


func _ready() -> void:
	$CommandMargin.minimum_size_changed.connect(update_minimum_size)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(62.0, 146.0)
	for asset_id: StringName in FLAME_FRAME_IDS:
		_flame_frames.append(_remove_classic_matte(ClassicUiAssetCatalog.texture(asset_id)))
	_body_texture = _remove_classic_matte(ClassicUiAssetCatalog.texture(BODY_ASSET_ID))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	pressed.connect(func() -> void: command_requested.emit(command_id))
	set_process(false)


func sync_status(light_remaining: int, has_torch: bool, can_activate: bool, reason: String = "") -> void:
	_light_remaining = maxi(0, light_remaining)
	_has_torch = has_torch
	disabled = not can_activate
	tooltip_text = reason if not reason.is_empty() else "Use another Torch" if _light_remaining > 0 else "Light a Torch"
	if not _has_torch or _light_remaining <= 0:
		_frame_index = 0
		_frame_elapsed = 0.0
	set_process(_has_torch and _light_remaining > 0)
	queue_redraw()


func _process(delta: float) -> void:
	_frame_elapsed += delta
	if _frame_elapsed < FRAME_INTERVAL:
		return
	var frame_count := maxi(1, _flame_frames.size())
	var advanced := floori(_frame_elapsed / FRAME_INTERVAL)
	_frame_elapsed -= float(advanced) * FRAME_INTERVAL
	_frame_index = (_frame_index + advanced) % frame_count
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ONE, size - Vector2(2.0, 2.0))
	var pressed := is_pressed()
	var leading_edge := SURFACE_DARK if pressed else EDGE_LIGHT
	var trailing_edge := EDGE_LIGHT if pressed else SURFACE_DARK
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), leading_edge, 2.0)
	draw_line(rect.position, Vector2(rect.position.x, rect.end.y), leading_edge, 2.0)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, trailing_edge, 2.0)
	draw_line(Vector2(rect.end.x, rect.position.y), rect.end, trailing_edge, 2.0)
	var pressed_offset := Vector2.ONE if pressed else Vector2.ZERO
	if _has_torch:
		_draw_torch_art(pressed_offset)
	if disabled:
		draw_rect(rect, DISABLED_OVERLAY, true)
	elif pressed:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.76, 0.24, 0.14), true)
	if has_focus():
		draw_rect(rect, FOCUS_COLOR, false, 2.0)
	elif is_hovered() and not disabled:
		draw_rect(rect, HOVER_COLOR, false, 1.0)


func _get_minimum_size() -> Vector2:
	var margin := get_node_or_null("CommandMargin") as MarginContainer
	return margin.get_combined_minimum_size() if margin != null else Vector2.ZERO


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	var stage := get_node("CommandMargin/CommandContent/IconStage") as Control
	UiSizing.minimum_size(stage, Vector2(32, 110) * profile.bitmap_scale / profile.ui_scale)
	queue_redraw()


func _draw_torch_art(offset: Vector2) -> void:
	if _body_texture == null:
		return
	var segments := _fuel_segment_count()
	var profile := UiSizing.profile_for(self)
	var art_scale := profile.bitmap_scale if profile != null else 1
	var body_size := _body_texture.get_size() * art_scale
	var stage := get_node("CommandMargin/CommandContent/IconStage") as Control
	var center_x := floorf((size.x - body_size.x) * 0.5)
	var base_y := stage.global_position.y - global_position.y + stage.size.y * 0.75 + 3.5 * art_scale
	for segment_index: int in segments:
		draw_texture_rect(_body_texture, Rect2(Vector2(center_x, base_y - float(segment_index + 1) * 7.0 * art_scale) + offset, body_size), false)
	if _light_remaining <= 0 or _flame_frames.is_empty():
		return
	var flame := _flame_frames[_frame_index]
	if flame == null:
		return
	var flame_size := flame.get_size() * art_scale
	var flame_x := floorf((size.x - flame_size.x) * 0.5)
	var flame_y := maxf(stage.global_position.y - global_position.y, base_y - float(segments) * 7.0 * art_scale - flame_size.y + 6.0 * art_scale)
	draw_texture_rect(flame, Rect2(Vector2(flame_x, flame_y) + offset, flame_size), false)


func _fuel_segment_count() -> int:
	return maxi(1, floori(float(_light_remaining) / 31.0) + 1) if _light_remaining > 0 else 2


func _remove_classic_matte(texture: Texture2D) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.convert(Image.FORMAT_RGBA8)
	for y: int in image.get_height():
		for x: int in image.get_width():
			var color := image.get_pixel(x, y)
			var red := roundi(color.r * 255.0)
			var green := roundi(color.g * 255.0)
			var blue := roundi(color.b * 255.0)
			if red == green and green == blue and red in [0x33, 0x44, 0x55, 0x66]:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
	return ImageTexture.create_from_image(image)
