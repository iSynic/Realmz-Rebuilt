## Presents the dynamic pick lock interaction without owning gameplay state.

class_name PickLockInteraction
extends InteractionComponent

const TUMBLER_ROW_SCENE_PATH := "res://src/ui/shared/interactions/pick_lock_tumbler_row.tscn"

var _media: ClassicMediaCatalog
var _body: PickLockRequestBody
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
	_body = request.body as PickLockRequestBody
	if _body == null:
		return
	var portrait := %Portrait as TextureRect
	portrait.texture = _portrait_texture(_body.portrait_id)
	(%ActionTitle as Label).text = _body.action_label
	(%CharacterFact as Label).text = "%s • Ability %d" % [_body.character_name, _body.chance_percent]
	(%Instruction as Label).text = _body.prompt_text()
	_countdown = %PickLockCountdown
	var rows := %TumblerRows as VBoxContainer
	for index: int in _body.frames[0].size():
		var row := (load(TUMBLER_ROW_SCENE_PATH) as PackedScene).instantiate() as HBoxContainer
		rows.add_child(row)
		(row.get_node("Label") as Label).text = "Tumbler %d" % (index + 1)
		var tumbler := row.get_node("Tumbler") as PickLockTumbler
		_tumblers.append(tumbler)
	(%PickLockStop as Button).pressed.connect(_submit_current_frame)
	_timer = %Timer
	_timer.wait_time = 1.0 / float(_body.frame_rate)
	_timer.timeout.connect(_advance_frame)
	_render_frame()
	if is_inside_tree():
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
