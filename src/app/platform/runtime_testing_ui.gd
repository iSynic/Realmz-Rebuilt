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
			return {"controls": records, "controlsTruncated": true}
		if node is Control and not node.is_visible_in_tree():
			continue
		if node is BaseButton:
			var rect: Rect2 = node.get_global_rect()
			if rect.has_area() and rect.intersects(_root.get_viewport_rect()):
				var path := String(_root.get_path_to(node))
				var identity := path.sha256_text().left(24)
				_controls[identity] = weakref(node)
				var label: String = node.caption_text() if node is ClassicBitmapButton else node.text if node is Button else String(node.name)
				records.append({"controlId": identity, "label": label, "path": path, "enabled": not node.disabled, "tooltip": node.tooltip_text, "rect": {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y}})
		pending.append_array(node.get_children())
	return {"controls": records, "controlsTruncated": false}


func execute(params: Dictionary) -> Dictionary:
	if not RuntimeTestingFixtureRequest.exact_fields(params, ["controlId", "action"]) or not params["controlId"] is String or params["action"] != "click":
		return _observer.rejected("unsupported_ui_action", "UI input currently supports click on an observed visible controlId.")
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
