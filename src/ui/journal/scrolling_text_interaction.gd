## Presents the dynamic scrolling text interaction without owning gameplay state.

class_name ScrollingTextInteraction
extends InteractionComponent

var _media: ClassicMediaCatalog
var _surface: ClassicScrollingTextSurface
var _done: Button
var _submitted: bool = false


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	var body := request.body as AcknowledgeRequestBody
	if body == null or body.presentation != &"classic-scrolling-text":
		return
	_surface = %ClassicScrollingTextWell as ClassicScrollingTextSurface
	_surface.configure(_media)
	_surface.double_click_requested.connect(_complete)
	var asset := _media.asset_by_resource(body.resource_type, body.resource_id) if body.has_resource and _media != null else null
	if asset != null:
		_surface.present_asset(asset)
	else:
		_surface.present_text(body.prompt)
	_done = %ClassicScrollingTextDone as Button
	_done.pressed.connect(_complete)
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
