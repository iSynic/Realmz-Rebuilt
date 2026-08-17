class_name PickLockInteraction
extends InteractionComponent

const PickLockTumblerScript := preload("res://src/presentation/interaction_components/pick_lock_tumbler.gd")

var _media: ClassicMediaCatalog
var _body: InteractionRequest.PickLockRequestBody
var _frame_index: int
var _elapsed_frames: int
var _tumblers: Array[Control] = []
var _countdown: Label
var _timer: Timer
var _submitted: bool
var _last_second: int = -1


func configure(media: ClassicMediaCatalog) -> void:
	_media = media


func build(request: InteractionRequest) -> void:
	_body = request.body as InteractionRequest.PickLockRequestBody
	if _body == null:
		return
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(64.0, 64.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = _portrait_texture(_body.portrait_id)
	header.add_child(portrait)
	var title := Label.new()
	title.text = "%s\n%s • Ability %d" % [_body.action_label, _body.character_name, _body.chance_percent]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_countdown = Label.new()
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown.custom_minimum_size.x = 90.0
	header.add_child(_countdown)
	add_child(header)
	for index: int in _body.frames[0].size():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%d" % (index + 1)
		label.custom_minimum_size.x = 24.0
		row.add_child(label)
		var tumbler := PickLockTumblerScript.new()
		tumbler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tumbler)
		add_child(row)
		_tumblers.append(tumbler)
	var attempt := Button.new()
	attempt.text = "Open" if _tumblers.is_empty() else "Try now"
	attempt.custom_minimum_size.y = 42.0
	attempt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attempt.pressed.connect(_submit_current_frame)
	add_child(attempt)
	_timer = Timer.new()
	_timer.wait_time = 1.0 / float(_body.frame_rate)
	_timer.timeout.connect(_advance_frame)
	add_child(_timer)
	_render_frame()
	_timer.start()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		_submit_current_frame()


func _advance_frame() -> void:
	if _submitted or _body == null:
		return
	_elapsed_frames += 1
	_frame_index = mini(_elapsed_frames, _body.frames.size() - 1)
	_render_frame()
	if _elapsed_frames >= _body.time_limit_frames:
		_submit_current_frame()


func _render_frame() -> void:
	var positions: Array = _body.frames[_frame_index]
	for index: int in _tumblers.size():
		_tumblers[index].configure(int(positions[index]), _body.yellow_threshold, _body.green_threshold)
	var frames_left := _body.time_limit_frames - _elapsed_frames
	var seconds_left := ceili(float(frames_left) / float(_body.frame_rate))
	_countdown.text = "%d sec" % seconds_left
	if _last_second >= 0 and seconds_left != _last_second and seconds_left > 0:
		presentation_sound_requested.emit(10129)
	_last_second = seconds_left


func _submit_current_frame() -> void:
	if _submitted:
		return
	_submitted = true
	if _timer != null:
		_timer.stop()
	response_body_submitted.emit(InteractionResponse.PickLockBody.new(_frame_index))


func _portrait_texture(asset_id: String) -> Texture2D:
	if _media == null:
		return null
	return _media.image_texture(_media.asset_by_id(asset_id))
