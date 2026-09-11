## Presents the queued Classic flash-message overlay above the application stage.

class_name InteractionFlashController
extends RefCounted

signal sound_requested(sound_id: int)

var _presenter: Control
var _overlay_scene: PackedScene
var _application_rect := Rect2()
var _textbox_rect := Rect2()
var _queue: Array[Dictionary] = []
var _layer: Control
var _panel: PanelContainer
var _shield: ColorRect
var _label: Label


func configure(presenter: Control, overlay_scene: PackedScene) -> void:
	_presenter = presenter
	_overlay_scene = overlay_scene


func set_regions(application_rect: Rect2, textbox_rect: Rect2) -> void:
	_application_rect = application_rect
	_textbox_rect = textbox_rect
	_apply_layout()


func queue_messages(messages: Array[Dictionary]) -> void:
	for message: Dictionary in messages:
		var text := String(message.get("text", "")).strip_edges()
		if not text.is_empty():
			_queue.append({"text": text, "soundId": int(message.get("soundId", 0))})
	_show_next()


func dismiss() -> bool:
	if _panel == null:
		return false
	if _queue.is_empty():
		close(false)
	else:
		_present_next()
	return true


func close(clear_queue: bool = true) -> void:
	if _layer != null:
		var parent := _layer.get_parent()
		if parent != null:
			parent.remove_child(_layer)
		_layer.queue_free()
	_layer = null
	_panel = null
	_shield = null
	_label = null
	if clear_queue:
		_queue.clear()


func is_open() -> bool:
	return _panel != null


func release() -> void:
	if is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
	_panel = null
	_shield = null
	_label = null
	_presenter = null
	_queue.clear()


func _show_next() -> void:
	if _panel != null or _queue.is_empty() or _presenter.get_parent() == null:
		return
	_layer = _overlay_scene.instantiate() as Control
	_layer.z_index = _presenter.z_index + 20
	_presenter.get_parent().add_child(_layer)
	_shield = _layer.get_node("ClassicFlashShield") as ColorRect
	_panel = _layer.get_node("ClassicFlashMessage") as PanelContainer
	_label = _panel.get_node("ClassicFlashContent/ClassicFlashText") as Label
	var acknowledge := _panel.get_node("ClassicFlashContent/ClassicFlashContinue") as Button
	acknowledge.pressed.connect(dismiss)
	_panel.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			dismiss()
	)
	_present_next()
	_apply_layout()


func _present_next() -> void:
	if _panel == null or _label == null or _queue.is_empty():
		return
	var message: Dictionary = _queue.pop_front()
	_label.text = String(message["text"])
	var sound_id := int(message.get("soundId", 0))
	if sound_id > 0:
		sound_requested.emit(sound_id)


func _apply_layout() -> void:
	if _layer == null or _panel == null or _shield == null:
		return
	_layer.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_layer.position = Vector2.ZERO
	_layer.size = (_presenter.get_parent() as Control).size if _presenter.get_parent() is Control else _application_rect.end
	_shield.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_shield.position = _application_rect.position
	_shield.size = _application_rect.size
	var region := InteractionLayoutPolicy.classic_flash_modal_rect(_application_rect, _textbox_rect)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_panel.custom_minimum_size = region.size
	_panel.position = region.position
	_panel.size = region.size
