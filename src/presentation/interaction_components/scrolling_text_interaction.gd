class_name ScrollingTextInteraction
extends InteractionComponent

const ClassicScrollingTextSurfaceType := preload("res://src/presentation/screens/classic_scrolling_text_surface.gd")

var _media: ClassicMediaCatalog
var _surface: ClassicScrollingTextSurface
var _done: Button
var _submitted: bool = false


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as InteractionRequest.AcknowledgeBody
	if body == null or body.presentation != &"classic-scrolling-text":
		return
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_surface = ClassicScrollingTextSurfaceType.new() as ClassicScrollingTextSurface
	_surface.configure(_media)
	_surface.name = "ClassicScrollingTextWell"
	_surface.double_click_requested.connect(_complete)
	var asset := _media.asset_by_resource(body.resource_type, body.resource_id) if body.has_resource and _media != null else null
	if asset != null:
		_surface.present_asset(asset)
	else:
		_surface.present_text(body.prompt)
	add_child(_surface)
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
	set_process(false)


func _process(delta: float) -> void:
	if _surface != null:
		_surface.advance(delta)


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
	return ClassicScrollingTextSurface.automatic_scroll_distance(delta_seconds)


static func drag_scroll_delta(previous_y: float, current_y: float) -> float:
	return ClassicScrollingTextSurface.drag_scroll_delta(previous_y, current_y)


func _complete() -> void:
	if _submitted:
		return
	_submitted = true
	response_body_submitted.emit(InteractionResponse.AcknowledgeBody.new())
