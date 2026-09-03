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
var visual_asset_id: StringName
var _native_size := Vector2i(50, 50)
var _art_scale: int = 1
var _art_texture: Texture2D
var _pressed_art_texture: Texture2D
var _label: String = ""
var _icon_caption_layout: bool = false
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
	visual_asset_id = asset_id
	var pressed_asset_id := StringName(definition.get("pressed_asset_id", &""))
	var direct_path := String(definition.get("asset_path", ""))
	var source_texture := load(direct_path) as Texture2D if not direct_path.is_empty() else ClassicUiAssetCatalog.texture(asset_id)
	var source_pressed_texture := ClassicUiAssetCatalog.texture(pressed_asset_id)
	var art_region: Array = definition.get("art_region", [])
	var art_clear_regions: Array = definition.get("art_clear_regions", [])
	var art_mask := StringName(definition.get("art_mask", &""))
	_art_texture = _prepare_art_texture(source_texture, art_region, art_clear_regions, art_mask)
	_pressed_art_texture = _prepare_art_texture(source_pressed_texture, art_region, art_clear_regions, art_mask)
	texture_normal = null
	_native_size = Vector2i(_art_texture.get_size()) if _art_texture != null else Vector2i.ZERO
	var pressed_native_size := Vector2i(_pressed_art_texture.get_size()) if _pressed_art_texture != null else Vector2i.ZERO
	_native_size = Vector2i(maxi(_native_size.x, pressed_native_size.x), maxi(_native_size.y, pressed_native_size.y))
	if _native_size.x <= 0 or _native_size.y <= 0:
		_native_size = Vector2i(50, 50)
	tooltip_text = String(definition.get("tooltip", ""))
	_label = String(definition.get("label", "Command"))
	_icon_caption_layout = not StringName(definition.get("group", &"")).is_empty()
	toggle_mode = bool(definition.get("toggle_mode", false))
	var accelerator := String(definition.get("accelerator", ""))
	if not accelerator.is_empty():
		tooltip_text += " [%s]" % accelerator
	set_art_scale(art_scale)


func has_visual_art() -> bool:
	return _art_texture != null


func set_art_scale(value: int) -> void:
	_art_scale = 2 if value >= 2 else 1
	custom_minimum_size = Vector2(62.0, 70.0) if _icon_caption_layout else Vector2(maxi(_native_size.x * _art_scale + 6, 62), _native_size.y * _art_scale + 6) if _art_texture != null else Vector2(62.0, 56.0)
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
		var icon_stage := Rect2(Vector2(4.0, 3.0), Vector2(size.x - 8.0, 43.0)) if _icon_caption_layout else Rect2(Vector2.ZERO, size)
		var effective_scale := maxi(1, mini(_art_scale, mini(floori(icon_stage.size.x / float(_native_size.x)), floori(icon_stage.size.y / float(_native_size.y))))) if _icon_caption_layout else _art_scale
		var art_size := Vector2(_native_size * effective_scale)
		var art_rect := Rect2(Vector2(floorf(icon_stage.position.x + (icon_stage.size.x - art_size.x) * 0.5), floorf(icon_stage.position.y + (icon_stage.size.y - art_size.y) * 0.5)) + pressed_offset, art_size)
		draw_texture_rect(displayed_texture, art_rect, false)
	if _icon_caption_layout:
		draw_line(Vector2(5.0, size.y - 20.0), Vector2(size.x - 5.0, size.y - 20.0), Color(0.04, 0.05, 0.055, 0.9), 1.0)
		var caption_width := size.x - 8.0
		var caption_size := fitted_caption_font_size(font, _label, caption_width, font_size)
		draw_string(font, Vector2(4.0, size.y - 6.0) + pressed_offset, _label, HORIZONTAL_ALIGNMENT_CENTER, caption_width, caption_size, CAPTION_COLOR)
	elif displayed_texture == null:
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


func _prepare_art_texture(texture: Texture2D, region_data: Array, clear_regions: Array, mask: StringName) -> Texture2D:
	if texture == null:
		return null
	var image := texture.get_image()
	if image == null or image.is_empty():
		return texture
	image.convert(Image.FORMAT_RGBA8)
	if region_data.size() == 4:
		var requested := Rect2i(int(region_data[0]), int(region_data[1]), int(region_data[2]), int(region_data[3]))
		var bounded := requested.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		if bounded.size.x > 0 and bounded.size.y > 0:
			image = image.get_region(bounded)
	for clear_data: Variant in clear_regions:
		if clear_data is not Array or (clear_data as Array).size() != 4:
			continue
		var clear_array := clear_data as Array
		var requested_clear := Rect2i(int(clear_array[0]), int(clear_array[1]), int(clear_array[2]), int(clear_array[3]))
		var bounded_clear := requested_clear.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
		for y: int in range(bounded_clear.position.y, bounded_clear.end.y):
			for x: int in range(bounded_clear.position.x, bounded_clear.end.x):
				var color := image.get_pixel(x, y)
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
	if mask == &"circle":
		var center := (Vector2(image.get_size()) - Vector2.ONE) * 0.5
		var radius := float(mini(image.get_width(), image.get_height())) * 0.5
		for y: int in image.get_height():
			for x: int in image.get_width():
				if Vector2(x, y).distance_squared_to(center) > radius * radius:
					var color := image.get_pixel(x, y)
					image.set_pixel(x, y, Color(color.r, color.g, color.b, 0.0))
	return ImageTexture.create_from_image(image)
