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
	add_theme_constant_override("separation", 8)
	var identity_panel := PanelContainer.new()
	identity_panel.name = "PickLockIdentity"
	identity_panel.theme_type_variation = &"ClassicInset"
	identity_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(identity_panel)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(64.0, 64.0)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.texture = _portrait_texture(_body.portrait_id)
	header.add_child(portrait)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = _body.action_label
	title.theme_type_variation = &"ClassicHeading"
	identity.add_child(title)
	var character := Label.new()
	character.text = "%s • Ability %d" % [_body.character_name, _body.chance_percent]
	identity.add_child(character)
	var instruction := Label.new()
	instruction.text = _body.prompt_text()
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.add_theme_color_override("font_color", Color("d5b45d"))
	identity.add_child(instruction)
	header.add_child(identity)
	_countdown = Label.new()
	_countdown.name = "PickLockCountdown"
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_countdown.custom_minimum_size.x = 90.0
	header.add_child(_countdown)
	identity_panel.add_child(header)
	var mechanism_panel := PanelContainer.new()
	mechanism_panel.name = "PickLockMechanism"
	mechanism_panel.theme_type_variation = &"ClassicTextWell"
	mechanism_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(mechanism_panel)
	var mechanism := VBoxContainer.new()
	mechanism.add_theme_constant_override("separation", 4)
	mechanism_panel.add_child(mechanism)
	for index: int in _body.frames[0].size():
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Tumbler %d" % (index + 1)
		label.custom_minimum_size.x = 82.0
		row.add_child(label)
		var tumbler := PickLockTumblerScript.new()
		tumbler.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tumbler)
		mechanism.add_child(row)
		_tumblers.append(tumbler)
	var legend := HBoxContainer.new()
	legend.name = "PickLockLegend"
	legend.add_theme_constant_override("separation", 16)
	for entry: Array in [["Red • not aligned", Color("d77b7b")], ["Gold • within range", Color("e0bc53")], ["Green • set", Color("7bdc8b")]]:
		var label := Label.new()
		label.text = entry[0]
		label.add_theme_color_override("font_color", entry[1])
		legend.add_child(label)
	mechanism.add_child(legend)
	var attempt := Button.new()
	attempt.name = "PickLockStop"
	attempt.text = "Stop tumblers"
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
