## Preserves keyboard focus and scroll position while an authored workspace rebinds.
class_name WorkspaceFocusController
extends RefCounted

var _focus_keys: Dictionary = {}


func prepare(body: Node, route_id: StringName) -> void:
	_assign_keys(body, route_id)


func focus_first(body: Node) -> void:
	_focus_first(body)


func store(root: Control, route_id: StringName) -> void:
	var viewport := root.get_viewport()
	if viewport == null:
		return
	var owner := viewport.gui_get_focus_owner()
	if owner != null and root.is_ancestor_of(owner) and owner.has_meta("focus_key"):
		_focus_keys[route_id] = String(owner.get_meta("focus_key"))


func restore(
		root: Control,
		body: Node,
		scroll: ScrollContainer,
		route_id: StringName,
		reset_scroll_to_top: bool,
		_previous_scroll_horizontal: int,
		previous_scroll_vertical: int
) -> String:
	var wanted := String(_focus_keys.get(route_id, ""))
	var focus_match := _find_focus_key(body, wanted) if not wanted.is_empty() else null
	if focus_match != null:
		focus_match.grab_focus()
	else:
		_focus_first(body)
	if scroll != null:
		# Focus settles before rebuilt layout and must not drag the scroll view.
		scroll.scroll_horizontal = 0
		scroll.scroll_vertical = 0 if reset_scroll_to_top else previous_scroll_vertical
	var viewport := root.get_viewport()
	var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
	return String(focus_owner.get_meta("focus_key", "")) if focus_owner != null and root.is_ancestor_of(focus_owner) else ""


func _assign_keys(parent: Node, route_id: StringName, next_index: int = 0) -> int:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			if not child.has_meta("focus_key"):
				child.set_meta("focus_key", "%s:%d" % [route_id, next_index])
			next_index += 1
		next_index = _assign_keys(child, route_id, next_index)
	return next_index


func _find_focus_key(parent: Node, key: String) -> Control:
	for child: Node in parent.get_children():
		if child is Control and child.has_meta("focus_key") and String(child.get_meta("focus_key")) == key:
			return child
		var nested := _find_focus_key(child, key)
		if nested != null:
			return nested
	return null


func _focus_first(parent: Node) -> void:
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.visible and control.focus_mode != Control.FOCUS_NONE and not (control is BaseButton and (control as BaseButton).disabled):
				control.grab_focus()
				return
		_focus_first(child)
		var viewport := parent.get_viewport()
		var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
		if focus_owner != null and parent.is_ancestor_of(focus_owner):
			return
