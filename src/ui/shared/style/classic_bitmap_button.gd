## Presents Classic bitmap button through the Godot interface.

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

@export var command_id: StringName
## A text-only button in a row of actions: shorter than the picture buttons.
@export var compact := false
## The row's main action: drawn with an accent wash and edge.
@export var primary := false
## Set by CommandIconLayout for the fixed footer, where art commands keep their caption band.
var _fixed_footer_caption := false
var visual_asset_id: StringName
var _native_size := Vector2i(50, 50)
var _art_scale: int = 1
var _art_texture: Texture2D
var _pressed_art_texture: Texture2D
var _label: String = ""
var _action_style: StyleBoxFlat
var _caption_lines: Array[String] = []
var _icon_caption_layout: bool = false
var _physical_pressed: bool = false
var _visual_pressed: bool = false
var _interface_size := 1.0
var _show_command_title: bool = true
var _fit_hidden_art: bool = false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ignore_texture_size = true
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(queue_redraw)
	mouse_exited.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	button_down.connect(func() -> void: _set_physical_pressed(true))
	button_up.connect(func() -> void: _set_physical_pressed(false))
	pressed.connect(func() -> void: command_requested.emit(command_id))
	resized.connect(queue_redraw)
	get_node("CommandMargin/CommandContent/IconStage").item_rect_changed.connect(queue_redraw)
	get_node("CommandMargin").minimum_size_changed.connect(update_minimum_size)


func _get_minimum_size() -> Vector2:
	var margin := get_node_or_null("CommandMargin") as MarginContainer
	return margin.get_combined_minimum_size() if margin != null else Vector2.ZERO


func _set_physical_pressed(pressed: bool) -> void:
	_physical_pressed = pressed
	queue_redraw()


func configure(definition: Dictionary, art_scale: int = 1) -> void:
	command_id = StringName(definition.get("id", &""))
	var asset_id := StringName(definition.get("asset_id", &""))
	visual_asset_id = asset_id
	var pressed_asset_id := StringName(definition.get("pressed_asset_id", &""))
	var direct_path := String(definition.get("asset_path", ""))
	# A runtime-composed texture (the Allies command) takes precedence over catalog art.
	var source_texture := load(direct_path) as Texture2D if not direct_path.is_empty() else ClassicUiAssetCatalog.texture(asset_id)
	var supplied: Variant = definition.get("art_texture")
	if supplied is Texture2D:
		source_texture = supplied
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
	_caption_lines.clear()
	var caption_lines_data: Variant = definition.get("caption_lines", [])
	if caption_lines_data is Array:
		for line: Variant in caption_lines_data:
			var caption_line := String(line).strip_edges()
			if not caption_line.is_empty():
				_caption_lines.append(caption_line)
	if _caption_lines.is_empty():
		_caption_lines.append(_label)
	_icon_caption_layout = not StringName(definition.get("group", &"")).is_empty()
	toggle_mode = bool(definition.get("toggle_mode", false))
	var accelerator := String(definition.get("accelerator", ""))
	if not accelerator.is_empty():
		tooltip_text += " [%s]" % accelerator
	accessibility_name = _label
	accessibility_description = tooltip_text
	set_art_scale(art_scale)
	_bind_caption()


func has_visual_art() -> bool:
	return _art_texture != null


func set_modular_icon_layout(art_scale: int, padding: int) -> void:
	var profile := UiSizing.profile_for(self)
	set_art_scale(art_scale if art_scale > 0 else profile.bitmap_scale if profile != null else 1)
	CommandIconLayout.apply(self, Vector2(_native_size), art_scale, padding)


func radial_art_texture() -> Texture2D:
	return _art_texture


func caption_text() -> String:
	return _label


func set_command_title_visible(visible: bool, fit_art_to_button: bool = false) -> void:
	_show_command_title = visible
	_fit_hidden_art = fit_art_to_button
	var caption := get_node_or_null("CommandMargin/CommandContent/CaptionBand/Caption") as Label
	var divider := get_node_or_null("CommandMargin/CommandContent/CaptionBand/Divider") as Control
	if caption != null:
		caption.modulate.a = 1.0 if visible else 0.0
	if divider != null:
		divider.modulate.a = 1.0 if visible else 0.0
	refresh_caption_band()
	queue_redraw()


## A hidden title gives its band's height back, so a multi-line caption cannot make the row taller.
## `in_fixed_footer` (from CommandIconLayout) keeps the band for art commands whose title is shown there.
func refresh_caption_band(in_fixed_footer: int = -1) -> void:
	if in_fixed_footer >= 0:
		_fixed_footer_caption = in_fixed_footer == 1
	var band := get_node_or_null("CommandMargin/CommandContent/CaptionBand") as Control
	if band != null:
		band.visible = _art_texture == null or ((_icon_caption_layout or _fixed_footer_caption) and _show_command_title)


func set_art_scale(value: int) -> void:
	_art_scale = clampi(value, 1, 3)
	var profile := UiSizing.profile_for(self)
	_interface_size = profile.ui_scale if profile != null else 1.0
	custom_minimum_size = Vector2(62.0, 70.0) * _interface_size if _icon_caption_layout else Vector2(maxi(_native_size.x * _art_scale + 6, 62), _native_size.y * _art_scale + 6) if _art_texture != null else Vector2(62.0, 38.0 if compact else 56.0) * _interface_size
	var stage := get_node_or_null("CommandMargin/CommandContent/IconStage") as Control
	if stage != null:
		stage.custom_minimum_size = Vector2(_native_size * _art_scale)
		UiSizing.minimum_size(stage, stage.custom_minimum_size / _interface_size)
	queue_redraw()


func _bind_caption() -> void:
	var caption := get_node("CommandMargin/CommandContent/CaptionBand/Caption") as Label
	caption.text = "\n".join(_caption_lines)
	UiSizing.font_size(caption, &"font_size", 17 if _caption_lines.size() > 1 or _art_texture == null else 15)
	refresh_caption_band()
	get_node("CommandMargin/CommandContent/IconStage").visible = _art_texture != null
	(get_node("CommandMargin/CommandContent") as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER if _art_texture == null else BoxContainer.ALIGNMENT_BEGIN
	get_node("CommandMargin/CommandContent/CaptionBand/Divider").visible = _art_texture != null
	if not _icon_caption_layout and _art_texture != null:
		caption.text = ""


func set_visual_pressed(value: bool) -> void:
	if _visual_pressed == value:
		return
	_visual_pressed = value
	queue_redraw()


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	set_art_scale(profile.bitmap_scale)


func is_visually_pressed() -> bool:
	return _physical_pressed or _visual_pressed or button_pressed


func _draw() -> void:
	var rect := Rect2(Vector2(1.0, 1.0), size - Vector2(2.0, 2.0))
	var pressed := is_visually_pressed()
	if compact:
		_draw_action(rect, pressed)
		return
	var surface_name := &"disabled" if disabled else &"pressed" if pressed else &"hover" if _pointed() else &"normal"
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
	var displayed_texture := _pressed_art_texture if pressed and _pressed_art_texture != null else _art_texture
	if displayed_texture != null:
		var stage := get_node("CommandMargin/CommandContent/IconStage") as Control
		var icon_stage := Rect2(Vector2.ZERO, size) if _icon_caption_layout and not _show_command_title else Rect2(stage.global_position - global_position, stage.size) if _icon_caption_layout else Rect2(Vector2.ZERO, size)
		var art_scale := _fitted_art_scale() if not _show_command_title and _fit_hidden_art else _art_scale
		var art_size := Vector2(_native_size * art_scale)
		var art_rect := Rect2(Vector2(floorf(icon_stage.position.x + (icon_stage.size.x - art_size.x) * 0.5), floorf(icon_stage.position.y + (icon_stage.size.y - art_size.y) * 0.5)) + pressed_offset, art_size)
		draw_texture_rect(displayed_texture, art_rect, false)
	if disabled:
		draw_rect(rect, DISABLED_OVERLAY, true)
	elif pressed:
		draw_rect(rect.grow(-1.0), Color(0.95, 0.76, 0.24, 0.14), true)
	if has_focus():
		draw_rect(rect, FOCUS_COLOR, false, 2.0)
	elif _pointed() and not disabled:
		draw_rect(rect, HOVER_COLOR, false, 1.0)


## A text action in the menu chrome: a themed fill inside the theme's double hairline, the
## main action filled with the accent, an unavailable one faded.
func _draw_action(rect: Rect2, pressed: bool) -> void:
	var colors := UiThemeService.current().colors
	var lit := (_pointed() or pressed or has_focus()) and not disabled
	var fill: Color = colors[&"surface"] if disabled else colors[&"accent"] if primary else colors[&"selected"] if pressed else colors[&"field"] if lit else colors[&"raised"]
	if primary and lit: fill = fill.lightened(0.14)
	var edge := Color(colors[&"border"], 0.7) if disabled else colors[&"accent"] if lit or primary else Color(colors[&"accent"], 0.55)
	if _action_style == null:
		_action_style = StyleBoxFlat.new()
		_action_style.set_corner_radius_all(3)
	_action_style.bg_color = fill
	_action_style.border_color = edge
	_action_style.set_border_width_all(2 if has_focus() else 1)
	draw_style_box(_action_style, rect)
	draw_rect(rect.grow(-3.0), Color(colors[&"accent_text"] if primary and not disabled else edge, 0.3), false, 1.0)
	var caption := get_node("CommandMargin/CommandContent/CaptionBand/Caption") as Label
	var ink: Color = colors[&"muted"] if disabled else colors[&"accent_text"] if primary else colors[&"text"]
	if caption.get_theme_color(&"font_color") != ink: caption.add_theme_color_override(&"font_color", ink)
	caption.modulate.a = 0.55 if disabled else 1.0


## Hovered by the pointer, but not while something is being dragged over it: a button that is
## not a drop target should not light up as one.
func _pointed() -> bool:
	return is_hovered() and not get_viewport().gui_is_dragging()


func _fitted_art_scale() -> int:
	if _native_size.x <= 0 or _native_size.y <= 0:
		return 1
	var available := size - Vector2(8.0, 8.0)
	return clampi(floori(minf(available.x / float(_native_size.x), available.y / float(_native_size.y))), 1, 3)


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
