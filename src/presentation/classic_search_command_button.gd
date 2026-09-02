class_name ClassicSearchCommandButton
extends BaseButton

signal command_requested(command_id: StringName)

const ATLAS_ASSET_ID: StringName = &"effects.search_animation"
const FRAME_SIZE := Vector2(32.0, 32.0)
const FRAME_COUNT := 8
const FRAME_ROW_Y := 128.0
const FRAME_INTERVAL := 1.0 / 5.0
const FOCUS_COLOR := Color("f8e36f")
const HOVER_COLOR := Color("80d6e7")
const CAPTION_COLOR := Color("e7c756")
const SURFACE_COLOR := Color("171a1d")
const SURFACE_DARK := Color("080a0c")
const EDGE_LIGHT := Color("686b68")
const DISABLED_OVERLAY := Color(0.04, 0.05, 0.055, 0.64)

var command_id: StringName = &"search_mode"
var _atlas: Texture2D
var _searching: bool
var _frame_index: int
var _frame_elapsed: float


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_ALL
	toggle_mode = true
	custom_minimum_size = Vector2(62.0, 70.0)
	_atlas = remove_classic_matte(ClassicUiAssetCatalog.texture(ATLAS_ASSET_ID))
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(queue_redraw)
	button_up.connect(queue_redraw)
	pressed.connect(func() -> void: command_requested.emit(command_id))
	set_process(false)


func sync_status(searching: bool, can_activate: bool, reason: String = "") -> void:
	_searching = searching
	disabled = not can_activate
	set_pressed_no_signal(searching)
	tooltip_text = reason if not reason.is_empty() else "Stop searching" if searching else "Search continuously"
	if not searching:
		_frame_index = 0
		_frame_elapsed = 0.0
	set_process(searching)
	queue_redraw()


func _process(delta: float) -> void:
	_frame_elapsed += delta
	if _frame_elapsed < FRAME_INTERVAL:
		return
	var advanced := floori(_frame_elapsed / FRAME_INTERVAL)
	_frame_elapsed -= float(advanced) * FRAME_INTERVAL
	_frame_index = (_frame_index + advanced) % FRAME_COUNT
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ONE, size - Vector2(2.0, 2.0))
	var pressed := is_pressed()
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
	if _atlas != null:
		var frame_rect := Rect2(Vector2(float(_frame_index) * FRAME_SIZE.x, FRAME_ROW_Y), FRAME_SIZE)
		var destination := Rect2(Vector2(floorf((size.x - FRAME_SIZE.x) * 0.5), 4.0) + pressed_offset, FRAME_SIZE)
		draw_texture_rect_region(_atlas, destination, frame_rect)
	var font := get_theme_font("font", "Button")
	var font_size := maxi(11, get_theme_font_size("font_size", "Button") - 2)
	draw_line(Vector2(5.0, size.y - 20.0), Vector2(size.x - 5.0, size.y - 20.0), Color(0.04, 0.05, 0.055, 0.9), 1.0)
	var caption_size := ClassicBitmapButton.fitted_caption_font_size(font, "Search", size.x - 8.0, font_size)
	draw_string(font, Vector2(4.0, size.y - 6.0) + pressed_offset, "Search", HORIZONTAL_ALIGNMENT_CENTER, size.x - 8.0, caption_size, CAPTION_COLOR)
	if disabled:
		draw_rect(rect, DISABLED_OVERLAY, true)
	elif pressed:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.76, 0.24, 0.14), true)
	if has_focus():
		draw_rect(rect, FOCUS_COLOR, false, 2.0)
	elif is_hovered() and not disabled:
		draw_rect(rect, HOVER_COLOR, false, 1.0)


static func remove_classic_matte(texture: Texture2D) -> Texture2D:
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
			if red == green and green == blue and red in [0x33, 0x44, 0x55, 0x66, 0x77, 0x88]:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
	return ImageTexture.create_from_image(image)
