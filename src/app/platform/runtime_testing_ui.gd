## Catalogues visible controls and delivers real viewport input in isolated fixtures.
class_name RuntimeTestingUi
extends RefCounted

const CONTROL_LIMIT := 512
var _root: Control
var _observer: RuntimeTestingObserver
var _controls: Dictionary = {}


func _init(root: Control, observer: RuntimeTestingObserver) -> void:
	_root = root
	_observer = observer


func controls() -> Dictionary:
	_controls.clear()
	var records: Array[Dictionary] = []
	var pending: Array[Node] = [_root]
	var visited := 0
	while not pending.is_empty():
		var node := pending.pop_back() as Node
		visited += 1
		if visited > 10000 or records.size() >= CONTROL_LIMIT:
			return {"controls": records, "controlsTruncated": true, "coordinateSpace": "window"}
		if node is Control and not node.is_visible_in_tree():
			continue
		if node is BaseButton:
			var rect: Rect2 = node.get_global_rect()
			if rect.has_area() and rect.intersects(_root.get_viewport_rect()):
				var display := _root.get_viewport().get_parent() as DisplayCompositor
				var window_rect := display.logical_to_window_rect(rect) if display != null else rect
				var path := String(_root.get_path_to(node))
				var identity := path.sha256_text().left(24)
				_controls[identity] = weakref(node)
				var label: String = node.caption_text() if node is ClassicBitmapButton else node.text if node is Button else String(node.name)
				records.append({"controlId": identity, "label": label, "path": path, "enabled": not node.disabled, "focused": node.has_focus(), "tooltip": node.tooltip_text, "rect": {"x": window_rect.position.x, "y": window_rect.position.y, "width": window_rect.size.x, "height": window_rect.size.y}})
		pending.append_array(node.get_children())
	var focus := _root.get_viewport().gui_get_focus_owner()
	var focus_path := String(_root.get_path_to(focus)) if focus != null and _root.is_ancestor_of(focus) else ""
	return {"controls": records, "controlsTruncated": false, "coordinateSpace": "window", "focusControlId": focus_path.sha256_text().left(24) if not focus_path.is_empty() else null, "focusPath": focus_path if not focus_path.is_empty() else null}


func execute(params: Dictionary) -> Dictionary:
	if params.get("action") == "controller-button":
		return _controller_button(params)
	if params.get("action") == "controller-axis":
		return _controller_axis(params)
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["controlId", "action"]) or not params["controlId"] is String or params["action"] != "click":
		return _observer.rejected("unsupported_ui_action", "UI input supports click, bounded controller-button, or bounded controller-axis input.")
	if DisplayServer.get_name() == "headless":
		return _observer.rejected("ui_unavailable", "A rendered fixture window is required for UI-control proof.")
	controls()
	var reference := _controls.get(params["controlId"]) as WeakRef
	var button := reference.get_ref() as BaseButton if reference != null else null
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return _observer.rejected("control_unavailable", "The selected control is no longer visible and enabled.")
	var viewport := _root.get_viewport()
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	viewport.push_input(motion, true)
	var hovered := viewport.gui_get_hovered_control()
	if hovered != button and (hovered == null or not button.is_ancestor_of(hovered)):
		return _observer.rejected("control_occluded", "The selected control is covered by another input surface.")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = position
	press.global_position = position
	press.pressed = true
	var before_revision := _observer.revision
	viewport.push_input(press, true)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	viewport.push_input(release, true)
	var committed_step := _observer.last_step if _observer.revision != before_revision else null
	_observer.revision += 1
	if committed_step != null and committed_step.state == SessionStep.State.FAILED:
		return _observer.rejected(String(committed_step.error_code), committed_step.error_message)
	return _observer.accepted({"mode": "ui-control-execution", "controlId": params["controlId"], "input": "viewport-mouse-press-release", "observation": _observer.observe({"diagnostics": "complete"})["result"]})


func _controller_button(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["action", "button", "pressed"]) or not RuntimeTestingFixtureRequest.integer(params.get("button"), 0, 127) or not params.get("pressed") is bool:
		return _observer.rejected("invalid_params", "Controller button input requires button 0..127 and a pressed boolean.")
	if DisplayServer.get_name() == "headless":
		return _observer.rejected("ui_unavailable", "A rendered fixture window is required for controller input proof.")
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = int(params["button"])
	event.pressed = params["pressed"]
	return _push_controller_event(event, "button-%d-%s" % [event.button_index, "press" if event.pressed else "release"])


func _controller_axis(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["action", "axis", "value"]) or not RuntimeTestingFixtureRequest.integer(params.get("axis"), 0, 7) or not (params.get("value") is int or params.get("value") is float) or not is_finite(float(params["value"])) or absf(float(params["value"])) > 1.0:
		return _observer.rejected("invalid_params", "Controller axis input requires axis 0..7 and a finite value from -1 through 1.")
	if DisplayServer.get_name() == "headless":
		return _observer.rejected("ui_unavailable", "A rendered fixture window is required for controller input proof.")
	var event := InputEventJoypadMotion.new()
	event.device = 0
	event.axis = int(params["axis"])
	event.axis_value = float(params["value"])
	return _push_controller_event(event, "axis-%d-%+.3f" % [event.axis, event.axis_value])


func _push_controller_event(event: InputEvent, input_description: String) -> Dictionary:
	var before_revision := _observer.revision
	_root.get_viewport().push_input(event, true)
	var committed_step := _observer.last_step if _observer.revision != before_revision else null
	_observer.revision += 1
	if committed_step != null and committed_step.state == SessionStep.State.FAILED:
		return _observer.rejected(String(committed_step.error_code), committed_step.error_message)
	return _observer.accepted({"mode": "controller-input", "input": input_description, "observation": _observer.observe({"diagnostics": "complete"})["result"], "focus": controls()})
