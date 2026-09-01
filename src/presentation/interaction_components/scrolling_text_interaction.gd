class_name ScrollingTextInteraction
extends InteractionComponent

const AUTO_SCROLL_PIXELS_PER_SECOND: float = 20.0
const MANUAL_SCROLL_PIXELS: float = 25.0
const BACKGROUND_RESOURCE_TYPE: String = "ppat"
const BACKGROUND_RESOURCE_ID: int = 129

var _media: ClassicMediaCatalog
var _text: RichTextLabel
var _done: Button
var _dragging: bool = false
var _last_drag_y: float = 0.0
var _submitted: bool = false


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.AcknowledgeBody
	if body == null or body.presentation != &"classic-scrolling-text":
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var well := PanelContainer.new()
	well.name = "ClassicScrollingTextWell"
	well.theme_type_variation = &"ClassicTextWell"
	well.clip_contents = true
	well.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(well)
	var stack := Control.new()
	stack.name = "ClassicScrollingTextStack"
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.add_child(stack)
	var background := TextureRect.new()
	background.name = "ClassicScrollingTextBackground"
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	background.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_TILE
	background.texture = _background_texture()
	stack.add_child(background)
	var text_margin := MarginContainer.new()
	text_margin.name = "ClassicScrollingTextMargin"
	text_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text_margin.add_theme_constant_override("margin_left", 8)
	text_margin.add_theme_constant_override("margin_top", 6)
	text_margin.add_theme_constant_override("margin_right", 8)
	text_margin.add_theme_constant_override("margin_bottom", 6)
	stack.add_child(text_margin)
	_text = RichTextLabel.new()
	_text.name = "ClassicScrollingText"
	_text.theme_type_variation = &"ClassicNarrative"
	_text.add_theme_color_override("default_color", Color(0.035, 0.025, 0.05, 1.0))
	_text.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	_text.add_theme_constant_override("outline_size", 0)
	_text.bbcode_enabled = false
	_text.fit_content = false
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.scroll_active = true
	_text.scroll_following = false
	_text.selection_enabled = false
	_text.mouse_filter = Control.MOUSE_FILTER_STOP
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.text = _scrolling_text(body)
	_text.gui_input.connect(_on_text_input)
	text_margin.add_child(_text)
	var footer := HBoxContainer.new()
	footer.name = "ClassicScrollingTextActions"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(footer)
	_done = Button.new()
	_done.name = "ClassicScrollingTextDone"
	_done.text = "Done"
	_done.custom_minimum_size = Vector2(140.0, 38.0)
	_done.theme_type_variation = &"ClassicChoiceButton"
	_done.pressed.connect(_complete)
	footer.add_child(_done)
	set_process(true)


func _background_texture() -> Texture2D:
	if _media == null:
		return null
	return _media.image_texture(_media.asset_by_resource(BACKGROUND_RESOURCE_TYPE, BACKGROUND_RESOURCE_ID))


func _scrolling_text(body: InteractionRequest.AcknowledgeBody) -> String:
	if body == null or not body.has_resource or _media == null:
		return body.prompt if body != null else ""
	var asset := _media.asset_by_resource(body.resource_type, body.resource_id)
	if asset == null or asset.mime_type != "text/plain":
		return "Scrolling text resource is unavailable."
	var bytes := _media.read_bytes(asset)
	return bytes.get_string_from_utf8() if not bytes.is_empty() else "Scrolling text resource is unavailable."


func _process(delta: float) -> void:
	_scroll_by(automatic_scroll_distance(delta))


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode not in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		return
	_complete()
	get_viewport().set_input_as_handled()


func handle_back() -> bool:
	_complete()
	return true


func preferred_initial_focus() -> Control:
	return _done


static func automatic_scroll_distance(delta_seconds: float) -> float:
	return maxf(0.0, delta_seconds) * AUTO_SCROLL_PIXELS_PER_SECOND


static func drag_scroll_delta(previous_y: float, current_y: float) -> float:
	if current_y < previous_y:
		return MANUAL_SCROLL_PIXELS
	if current_y > previous_y:
		return -MANUAL_SCROLL_PIXELS
	return 0.0


func _on_text_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed and button.double_click:
			_dragging = false
			_complete()
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


func _complete() -> void:
	if _submitted:
		return
	_submitted = true
	set_process(false)
	response_body_submitted.emit(InteractionResponse.AcknowledgeBody.new())
