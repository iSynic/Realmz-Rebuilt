## Reviews the retained combat account without changing a staged combat task.
class_name CombatLogReview
extends RefCounted

var _activity: CombatActivityStrip
var _overlay: Node
var _view: Control
var _restore_focus: WeakRef


func bind(activity: CombatActivityStrip, overlay: Node) -> void:
	_activity = activity
	_overlay = overlay
	_activity.review_requested.connect(open)


func open() -> void:
	if not _activity.has_battle():
		return
	if _view == null:
		_view = (load("res://src/ui/shared/action_log_view.tscn") as PackedScene).instantiate()
		_overlay.add_child(_view)
		_view.close_requested.connect(close)
	var focus := _overlay.get_viewport().gui_get_focus_owner()
	_restore_focus = weakref(focus) if focus != null else null
	_view.present(_activity.lines(), "Combat Log", false)


func is_open() -> bool:
	return _view != null and _view.visible


func close() -> void:
	if _view != null:
		_view.close_console()
	var focus := _restore_focus.get_ref() as Control if _restore_focus != null else null
	if is_instance_valid(focus) and focus.is_visible_in_tree():
		focus.grab_focus()
	_restore_focus = null


func handle_input(event: InputEvent) -> bool:
	if not is_open():
		return false
	_view.handle_input(event)
	return true


func handle_controller(action_id: StringName, direction: Vector2i) -> bool:
	if not is_open():
		return false
	_view.handle_controller(action_id, direction)
	return true


func release() -> void:
	if is_instance_valid(_view):
		_view.queue_free()
	_view = null
