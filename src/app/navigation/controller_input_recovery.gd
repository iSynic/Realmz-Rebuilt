## Samples connected-pad axes at a suspension acknowledgement boundary.

class_name ControllerInputRecovery
extends RefCounted


static func refresh_connected_axes(device_id: int, axis_values: Dictionary) -> void:
	if device_id < 0 or device_id not in Input.get_connected_joypads():
		return
	for axis: int in range(JOY_AXIS_MAX):
		axis_values[axis] = Input.get_joy_axis(device_id, axis)


static func is_deliberate_external_input(event: InputEvent) -> bool:
	return (event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo) or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
