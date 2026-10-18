## Adapts Android system Back and suspension to the retained application viewport.
class_name AndroidLifecycleHost
extends Node

signal suspending
signal resumed

@export var content: SubViewport
var _suspended := false
var _was_paused := false


func _ready() -> void:
	if OS.has_feature("android"):
		get_tree().quit_on_go_back = false


func _notification(what: int) -> void:
	if not OS.has_feature("android") or not is_node_ready(): return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and not _suspended:
		for pressed: bool in [true, false]:
			var key := InputEventKey.new()
			key.keycode = KEY_ESCAPE
			key.physical_keycode = KEY_ESCAPE
			key.pressed = pressed
			content.push_input(key, false)
	elif what == NOTIFICATION_APPLICATION_PAUSED and not _suspended:
		suspending.emit()
		content.propagate_notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
		_was_paused = get_tree().paused
		_suspended = true
		get_tree().paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED and _suspended:
		get_tree().paused = _was_paused
		_suspended = false
		resumed.emit()
