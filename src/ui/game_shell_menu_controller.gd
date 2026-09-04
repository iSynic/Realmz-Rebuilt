## Populates shell menus and routes enabled selections to their named owner.
class_name GameShellMenuController
extends RefCounted

var _owner_ref: WeakRef
var _actions: Dictionary = {}
var _connected: Dictionary = {}


func _init(owner: Control) -> void:
	_owner_ref = weakref(owner)


func _owner():
	return _owner_ref.get_ref()


func fill(menu: MenuButton, entries: Array[Dictionary]) -> void:
	var owner = _owner()
	var popup := menu.get_popup()
	popup.clear()
	var actions: Dictionary = {}
	var enabled_count := 0
	for index: int in entries.size():
		var entry := entries[index]
		popup.add_item(String(entry["label"]), index)
		var reason := String(entry.get("disabled_reason", ""))
		if reason.is_empty() and entry.has("route"):
			reason = GameShell.route_change_reason(owner._current_view)
		if not reason.is_empty():
			entry["disabled_reason"] = reason
		actions[index] = entry
		if not reason.is_empty():
			popup.set_item_disabled(index, true)
			popup.set_item_tooltip(index, reason)
		else:
			enabled_count += 1
	_actions[menu.get_instance_id()] = actions
	menu.disabled = enabled_count == 0
	if not _connected.has(menu.get_instance_id()):
		popup.id_pressed.connect(_on_item_pressed.bind(menu))
		_connected[menu.get_instance_id()] = true


func _on_item_pressed(item_id: int, menu: MenuButton) -> void:
	var owner = _owner()
	var entry: Dictionary = _actions.get(menu.get_instance_id(), {}).get(item_id, {})
	if entry.is_empty() or not String(entry.get("disabled_reason", "")).is_empty():
		return
	if entry.has("route"):
		owner._navigator.open_screen(StringName(entry["route"]))
	elif entry.has("command"):
		owner._command_controller.activate(StringName(entry["command"]))
	elif entry.has("system"):
		owner.handle_system_action_requested(StringName(entry["system"]), entry.get("value"))
