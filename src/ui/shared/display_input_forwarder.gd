## Forwards window input through the same display transform used to draw the application.
class_name DisplayInputForwarder
extends RefCounted

var _pointer_inside: bool = false
var _buttons: Dictionary[int, InputEventMouseButton] = {}
var _touches: Dictionary[int, InputEventScreenTouch] = {}


func forward(event: InputEvent, content: SubViewport, geometry: Dictionary) -> bool:
	var rect: Rect2 = geometry["screen_rect"]
	var factor: float = geometry["scale"]
	var transform := Transform2D(Vector2(1.0 / factor, 0.0), Vector2(0.0, 1.0 / factor), -rect.position / factor)
	if event is InputEventMouse:
		var pointer := event as InputEventMouse
		var inside := rect.has_point(pointer.position)
		if inside != _pointer_inside:
			_pointer_inside = inside
			if inside:
				content.notify_mouse_entered()
			else:
				content.notify_mouse_exited()
		var button := event as InputEventMouseButton
		var captured_release := button != null and not button.pressed and _buttons.has(button.button_index)
		if not inside and not captured_release:
			return false
		if button != null:
			if button.pressed: _buttons[button.button_index] = button.duplicate()
			else: _buttons.erase(button.button_index)
			if captured_release and not inside:
				_move_mouse_outside(content)
		content.push_input(event.xformed_by(transform), false)
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and not touch.canceled:
			if not rect.has_point(touch.position): return false
			_touches[touch.index] = touch.duplicate()
		elif not _touches.erase(touch.index):
			return false
		if touch.canceled:
			_move_touch_outside(content, touch.index)
		content.push_input(event.xformed_by(transform), false)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index): return false
		content.push_input(event.xformed_by(transform), false)
	else:
		content.push_input(event, false)
	return true


func cancel(content: SubViewport) -> void:
	# BaseButton retains pressing_inside until motion; release coordinates alone do not cancel it.
	_move_mouse_outside(content)
	for button: InputEventMouseButton in _buttons.values():
		button.pressed = false
		button.button_mask = 0
		button.position = Vector2(-1, -1)
		button.global_position = button.position
		content.push_input(button, false)
	for touch: InputEventScreenTouch in _touches.values():
		_move_touch_outside(content, touch.index)
		touch.pressed = false
		touch.canceled = true
		touch.position = Vector2(-1, -1)
		content.push_input(touch, false)
	_buttons.clear()
	_touches.clear()
	content.notify_mouse_exited()
	_pointer_inside = false


func _move_mouse_outside(content: SubViewport) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(-1, -1)
	motion.global_position = motion.position
	content.push_input(motion, false)


func _move_touch_outside(content: SubViewport, index: int) -> void:
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = Vector2(-1, -1)
	content.push_input(drag, false)
