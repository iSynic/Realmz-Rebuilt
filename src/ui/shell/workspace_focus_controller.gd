## Preserves semantic focus and nested scroll position while an authored workspace rebinds.
class_name WorkspaceFocusController
extends RefCounted

const IDENTITY_FIELDS: Array[StringName] = [
	&"item_instance_id", &"spell_id", &"character_id", &"player_map_id",
	&"location_note_id", &"journal_message_id", &"save_id", &"setting_id",
	&"definition_id", &"action_id", &"operation",
]

var _focus_states: Dictionary = {}
var _scroll_states: Dictionary = {}


func prepare(body: Node, route_id: StringName) -> void:
	_assign_keys(body, body, route_id)


func focus_first(body: Node) -> void:
	_focus_first(body)


func store(root: Control, body: Node, route_id: StringName) -> void:
	if root == null or body == null:
		return
	var controls := _focusable_controls(body)
	var keys: Array[String] = []
	for control: Control in controls:
		keys.append(String(control.get_meta("focus_key", "")))
	var viewport := root.get_viewport()
	var owner := viewport.gui_get_focus_owner() if viewport != null else null
	if owner != null and body.is_ancestor_of(owner) and owner.has_meta("focus_key"):
		var key := String(owner.get_meta("focus_key"))
		_focus_states[route_id] = {"key": key, "index": keys.find(key), "order": keys}
	_store_scrolls(body, route_id)


func restore(root: Control, body: Node, scroll: ScrollContainer, route_id: StringName, reset_scroll_to_top: bool, previous_scroll_horizontal: int, previous_scroll_vertical: int) -> String:
	var viewport := root.get_viewport()
	var current := viewport.gui_get_focus_owner() if viewport != null else null
	if current != null and current.is_visible_in_tree() and not body.is_ancestor_of(current):
		return String(current.get_meta("focus_key", ""))
	_restore_scrolls(body, route_id)
	if scroll != null and not _scroll_states.has(route_id):
		scroll.scroll_horizontal = 0 if reset_scroll_to_top else previous_scroll_horizontal
		scroll.scroll_vertical = 0 if reset_scroll_to_top else previous_scroll_vertical
	var state: Dictionary = _focus_states.get(route_id, {})
	var wanted := String(state.get("key", ""))
	var focus_match := _find_focus_key(body, wanted) if not wanted.is_empty() else null
	if focus_match == null:
		var candidates := _focusable_controls(body)
		var prior_index := int(state.get("index", -1))
		if prior_index >= 0 and not candidates.is_empty():
			focus_match = candidates[mini(prior_index, candidates.size() - 1)]
	if focus_match != null:
		focus_match.grab_focus()
		_reveal(focus_match)
	else:
		_focus_first(body)
	var focus_owner := viewport.gui_get_focus_owner() if viewport != null else null
	return String(focus_owner.get_meta("focus_key", "")) if focus_owner != null and body.is_ancestor_of(focus_owner) else ""


func _assign_keys(parent: Node, body: Node, route_id: StringName) -> void:
	for child: Node in parent.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			if not child.has_meta("focus_key") or bool(child.get_meta("generated_focus_key", false)):
				child.set_meta("focus_key", _semantic_key(child as Control, body, route_id))
				child.set_meta("generated_focus_key", true)
			if not child.has_meta("focus_group"):
				child.set_meta("focus_group", "route:%s" % route_id)
		_assign_keys(child, body, route_id)


func _semantic_key(control: Control, body: Node, route_id: StringName) -> String:
	var cursor: Node = control
	while cursor != null and cursor != body.get_parent():
		for field: StringName in IDENTITY_FIELDS:
			if cursor.has_meta(field):
				return "%s:%s=%s:%s" % [route_id, field, str(cursor.get_meta(field)), control.name]
		cursor = cursor.get_parent()
	return "%s:path=%s" % [route_id, String(body.get_path_to(control))]


func _find_focus_key(parent: Node, key: String) -> Control:
	for child: Node in parent.get_children():
		if child is Control and child.has_meta("focus_key") and String(child.get_meta("focus_key")) == key:
			return child
		var nested := _find_focus_key(child, key)
		if nested != null:
			return nested
	return null


func _focusable_controls(parent: Node) -> Array[Control]:
	var result: Array[Control] = []
	for child: Node in parent.get_children():
		if child is Control:
			var control := child as Control
			if control.is_inside_tree() and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE:
				result.append(control)
		result.append_array(_focusable_controls(child))
	return result


func _focus_first(parent: Node) -> void:
	for control: Control in _focusable_controls(parent):
		if not (control is BaseButton and (control as BaseButton).disabled):
			control.grab_focus()
			_reveal(control)
			return


func _store_scrolls(body: Node, route_id: StringName) -> void:
	var values: Dictionary = {}
	for candidate: Node in body.find_children("*", "ScrollContainer", true, false):
		var scroll := candidate as ScrollContainer
		values[String(body.get_path_to(scroll))] = Vector2i(scroll.scroll_horizontal, scroll.scroll_vertical)
	_scroll_states[route_id] = values


func _restore_scrolls(body: Node, route_id: StringName) -> void:
	var values: Dictionary = _scroll_states.get(route_id, {})
	for path: String in values:
		var scroll := body.get_node_or_null(NodePath(path)) as ScrollContainer
		if scroll != null:
			var position: Vector2i = values[path]
			scroll.scroll_horizontal = position.x
			scroll.scroll_vertical = position.y


func _reveal(control: Control) -> void:
	var ancestor := control.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(control)
			return
		ancestor = ancestor.get_parent()
