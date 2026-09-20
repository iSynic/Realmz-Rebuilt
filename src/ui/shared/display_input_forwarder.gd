## Forwards window input through the same display transform used to draw the application.
class_name DisplayInputForwarder
extends RefCounted

var _pointer_inside: bool = false


func forward(event: InputEvent, content: SubViewport, geometry: Dictionary) -> bool:
	if event is InputEventMouse:
		var pointer := event as InputEventMouse
		var rect: Rect2 = geometry["screen_rect"]
		var inside := rect.has_point(pointer.position)
		if inside != _pointer_inside:
			_pointer_inside = inside
			if inside:
				content.notify_mouse_entered()
			else:
				content.notify_mouse_exited()
		if not inside:
			return false
		var factor: float = geometry["scale"]
		var transform := Transform2D(Vector2(1.0 / factor, 0.0), Vector2(0.0, 1.0 / factor), -rect.position / factor)
		content.push_input(event.xformed_by(transform), false)
	else:
		content.push_input(event, false)
	return true
