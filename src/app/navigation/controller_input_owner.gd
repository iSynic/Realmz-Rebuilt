## Normalizes one active desktop controller before application input dispatch.

class_name ControllerInputOwner
extends Node

signal action_pressed(action_id: StringName, repeated: bool)
signal action_released(action_id: StringName)
signal direction_changed(direction: Vector2i, repeated: bool)
signal active_device_changed(device_id: int, prompt_family: String)
signal input_suspended(reason: String)
signal input_resumed
signal binding_captured(action_id: StringName, descriptor: Dictionary)
signal binding_capture_cancelled
signal input_observed(summary: String)

const REPEATING_ACTIONS: Array[StringName] = [
	&"realmz_controller_up",
	&"realmz_controller_down",
	&"realmz_controller_left",
	&"realmz_controller_right",
	&"realmz_controller_scroll_up",
	&"realmz_controller_scroll_down",
	&"realmz_controller_scroll_left",
	&"realmz_controller_scroll_right",
]
const DIRECTION_ACTIONS: Array[StringName] = [
	&"realmz_controller_up",
	&"realmz_controller_down",
	&"realmz_controller_left",
	&"realmz_controller_right",
]
const LEFT_AXES: Array[int] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y]
const RIGHT_AXES: Array[int] = [JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]

var _preferences := ControllerPreferences.new()
var _active_device: int = -1
var _held_actions: Dictionary = {}
var _held_descriptors: Dictionary = {}
var _repeat_remaining_ms: Dictionary = {}
var _axis_values: Dictionary = {}
var _suspended: bool = false
var _awaiting_neutral: bool = false
var _capture_action: StringName = &""
var _direction_change_pending: bool = false
var _direction_settle_frames: int = 0


func _ready() -> void:
	set_process(true)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func configure(preferences: ControllerPreferences) -> void:
	_preferences = preferences.duplicate_value()
	UiInputActions.apply_controller_bindings(_preferences)
	clear_held_input()


func active_device() -> int:
	return _active_device


func prompt_family() -> String:
	return _resolved_prompt_family(_active_device)


func is_suspended() -> bool:
	return _suspended


func begin_binding_capture(action_id: StringName) -> bool:
	if action_id not in ControllerPreferences.ACTIONS:
		return false
	clear_held_input()
	_capture_action = action_id
	return true


func cancel_binding_capture() -> void:
	if _capture_action.is_empty():
		return
	_capture_action = &""
	binding_capture_cancelled.emit()


func handle_input(event: InputEvent) -> bool:
	if not event is InputEventJoypadButton and not event is InputEventJoypadMotion:
		if not _suspended or not ControllerInputRecovery.is_deliberate_external_input(event):
			return false
		ControllerInputRecovery.refresh_connected_axes(_active_device, _axis_values)
		if _awaiting_neutral and _all_axes_neutral():
			_suspended = false
			_awaiting_neutral = false
			input_resumed.emit()
		return true
	if _is_deliberate_takeover(event):
		input_observed.emit(_input_summary(event))
	if not _capture_action.is_empty():
		return _capture_binding(event)
	var device := event.device
	if _active_device >= 0 and device != _active_device:
		if not _is_deliberate_takeover(event):
			return false
		clear_held_input()
		_set_active_device(device)
	elif _active_device < 0 and _is_deliberate_takeover(event):
		_set_active_device(device)
	if device != _active_device: return false
	if event is InputEventJoypadMotion:
		_axis_values[(event as InputEventJoypadMotion).axis] = (event as InputEventJoypadMotion).axis_value
	if _suspended:
		if _awaiting_neutral and event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
			ControllerInputRecovery.refresh_connected_axes(_active_device, _axis_values)
			if _all_axes_neutral():
				_suspended = false
				_awaiting_neutral = false
				input_resumed.emit()
		return true
	var consumed := false
	for descriptor: Dictionary in _preferences.bindings:
		if not _matches_physical_input(descriptor, event):
			continue
		consumed = true
		var action_id := StringName(descriptor["action"])
		var descriptor_key := _descriptor_key(descriptor)
		var now_pressed := _descriptor_pressed(descriptor, event)
		var was_pressed := bool(_held_actions.get(action_id, false))
		if now_pressed:
			_held_descriptors[descriptor_key] = true
		else:
			_held_descriptors.erase(descriptor_key)
		var remains_pressed := _action_has_held_descriptor(action_id)
		if remains_pressed and not was_pressed:
			_held_actions[action_id] = true
			_repeat_remaining_ms[action_id] = _preferences.repeat_initial_ms
			action_pressed.emit(action_id, false)
			if action_id in DIRECTION_ACTIONS:
				_queue_direction_change(event is InputEventJoypadMotion)
		elif not remains_pressed and was_pressed:
			_held_actions.erase(action_id)
			_repeat_remaining_ms.erase(action_id)
			action_released.emit(action_id)
			if action_id in DIRECTION_ACTIONS:
				_queue_direction_change(event is InputEventJoypadMotion)
	return consumed


func suspend(reason: String) -> void:
	clear_held_input(false)
	_suspended = true
	_awaiting_neutral = true
	input_suspended.emit(reason)


func clear_held_input(clear_axes: bool = true) -> void:
	var had_direction := _combined_direction() != Vector2i.ZERO
	for action_id: StringName in _held_actions.keys():
		action_released.emit(action_id)
	_held_actions.clear()
	_held_descriptors.clear()
	_repeat_remaining_ms.clear()
	_direction_change_pending = false
	_direction_settle_frames = 0
	if clear_axes:
		_axis_values.clear()
	if had_direction:
		direction_changed.emit(Vector2i.ZERO, false)


func _process(delta: float) -> void:
	if _suspended:
		return
	if _direction_change_pending:
		if _direction_settle_frames > 0:
			_direction_settle_frames -= 1
		else:
			_direction_change_pending = false
			direction_changed.emit(_combined_direction(), false)
	var elapsed_ms := delta * 1000.0
	var direction_repeat_due := false
	for action_id: StringName in _held_actions.keys():
		if action_id not in REPEATING_ACTIONS:
			continue
		var remaining := float(_repeat_remaining_ms.get(action_id, _preferences.repeat_initial_ms)) - elapsed_ms
		while remaining <= 0.0:
			action_pressed.emit(action_id, true)
			if action_id in DIRECTION_ACTIONS:
				direction_repeat_due = true
			remaining += _preferences.repeat_interval_ms
		_repeat_remaining_ms[action_id] = remaining
	if direction_repeat_due:
		direction_changed.emit(_combined_direction(), true)


func _queue_direction_change(settle_axis_pair: bool) -> void:
	_direction_change_pending = true
	_direction_settle_frames = maxi(_direction_settle_frames, 1 if settle_axis_pair else 0)


func _combined_direction() -> Vector2i:
	return Vector2i(
		int(bool(_held_actions.get(&"realmz_controller_right", false))) - int(bool(_held_actions.get(&"realmz_controller_left", false))),
		int(bool(_held_actions.get(&"realmz_controller_down", false))) - int(bool(_held_actions.get(&"realmz_controller_up", false)))
	)


func _matches_physical_input(descriptor: Dictionary, event: InputEvent) -> bool:
	if descriptor["kind"] == ControllerPreferences.BINDING_BUTTON:
		return event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == int(descriptor["code"])
	return event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis == int(descriptor["code"])


func _descriptor_key(descriptor: Dictionary) -> String:
	return "%s:%s:%d:%d" % [String(descriptor["action"]), String(descriptor["kind"]), int(descriptor["code"]), int(descriptor.get("direction", 0))]


func _action_has_held_descriptor(action_id: StringName) -> bool:
	var prefix := "%s:" % String(action_id)
	for descriptor_key: String in _held_descriptors:
		if descriptor_key.begins_with(prefix):
			return true
	return false


func _capture_binding(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return true
		if button.button_index == JOY_BUTTON_B:
			cancel_binding_capture()
			return true
		var action_id := _capture_action
		_capture_action = &""
		binding_captured.emit(action_id, {"action": String(action_id), "kind": ControllerPreferences.BINDING_BUTTON, "code": button.button_index, "direction": 0})
		return true
	var motion := event as InputEventJoypadMotion
	if absf(motion.axis_value) < _dead_zone_for_axis(motion.axis):
		return true
	var action_id := _capture_action
	_capture_action = &""
	binding_captured.emit(action_id, {"action": String(action_id), "kind": ControllerPreferences.BINDING_AXIS, "code": motion.axis, "direction": 1 if motion.axis_value > 0.0 else -1})
	return true


func _descriptor_pressed(descriptor: Dictionary, event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	var axis_event := event as InputEventJoypadMotion
	var direction := int(descriptor["direction"])
	var threshold := _dead_zone_for_axis(axis_event.axis)
	var release_threshold := maxf(0.0, threshold - _preferences.release_hysteresis)
	var action_id := StringName(descriptor["action"])
	var magnitude := axis_event.axis_value * direction
	return magnitude >= (release_threshold if bool(_held_actions.get(action_id, false)) else threshold)


func _dead_zone_for_axis(axis: int) -> float:
	return _preferences.right_stick_dead_zone if axis in RIGHT_AXES else _preferences.left_stick_dead_zone


func _is_deliberate_takeover(event: InputEvent) -> bool:
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	var axis_event := event as InputEventJoypadMotion
	return absf(axis_event.axis_value) >= _dead_zone_for_axis(axis_event.axis)


func _all_axes_neutral() -> bool:
	for axis: int in _axis_values:
		if absf(float(_axis_values[axis])) >= _dead_zone_for_axis(axis):
			return false
	return true


func _set_active_device(device_id: int) -> void:
	_active_device = device_id
	active_device_changed.emit(device_id, _resolved_prompt_family(device_id))


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	if not connected and device_id == _active_device:
		_active_device = -1
		_axis_values.clear()
		suspend("Controller disconnected. Reconnect, center the controls, then press a button to continue.")
		active_device_changed.emit(-1, _resolved_prompt_family(-1))


func _resolved_prompt_family(device_id: int) -> String:
	if _preferences.prompt_family != ControllerPreferences.PROMPT_AUTO:
		return _preferences.prompt_family
	if device_id < 0:
		return ControllerPreferences.PROMPT_GENERIC
	var identity := Input.get_joy_name(device_id).to_lower()
	if "playstation" in identity or "dualshock" in identity or "dualsense" in identity or "sony" in identity:
		return ControllerPreferences.PROMPT_PLAYSTATION
	if "switch" in identity or "nintendo" in identity or "joy-con" in identity:
		return ControllerPreferences.PROMPT_SWITCH
	if "xbox" in identity or "xinput" in identity:
		return ControllerPreferences.PROMPT_XBOX
	return ControllerPreferences.PROMPT_GENERIC


func _input_summary(event: InputEvent) -> String:
	if event is InputEventJoypadButton:
		return "Device %d • button %d" % [event.device, (event as InputEventJoypadButton).button_index]
	var motion := event as InputEventJoypadMotion
	return "Device %d • axis %d • %+.2f" % [event.device, motion.axis, motion.axis_value]
