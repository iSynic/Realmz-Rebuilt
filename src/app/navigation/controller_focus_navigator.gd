## Applies deterministic controller focus movement to the active Godot surface.

class_name ControllerFocusNavigator
extends RefCounted


func move(root: Control, direction: Vector2i) -> Control:
	if root == null or direction == Vector2i.ZERO:
		return null
	var viewport := root.get_viewport()
	var current := viewport.gui_get_focus_owner() if viewport != null else null
	if current == null or not current.is_visible_in_tree():
		return focus_first(root)
	if _adjust_value(current, direction):
		return current
	var side := _side_for(direction)
	var neighbor := current.find_valid_focus_neighbor(side) if side >= 0 else null
	if neighbor == null or neighbor == current or not root.is_ancestor_of(neighbor) or not _is_focusable(neighbor):
		neighbor = _geometric_neighbor(root, current, direction)
	if neighbor != null:
		neighbor.grab_focus()
		_reveal_in_scroll(neighbor)
	return neighbor


func move_geometric(root: Control, direction: Vector2i) -> Control:
	if root == null or direction == Vector2i.ZERO:
		return null
	var viewport := root.get_viewport()
	var current := viewport.gui_get_focus_owner() if viewport != null else null
	if current == null or not root.is_ancestor_of(current):
		return focus_first(root)
	var neighbor := _geometric_neighbor(root, current, direction, 10.0)
	if neighbor != null:
		neighbor.grab_focus()
		_reveal_in_scroll(neighbor)
	return neighbor


func focus_next(root: Control, backwards: bool = false) -> Control:
	if root == null:
		return null
	var viewport := root.get_viewport()
	var current := viewport.gui_get_focus_owner() if viewport != null else null
	if current == null or not root.is_ancestor_of(current):
		return focus_first(root)
	var focus_group := String(current.get_meta("focus_group", ""))
	var candidates := _focusable_controls(root, focus_group)
	if candidates.is_empty():
		return null
	var current_index := candidates.find(current)
	if current_index < 0:
		return focus_first(root)
	var offset := -1 if backwards else 1
	var next: Control = candidates[wrapi(current_index + offset, 0, candidates.size())]
	next.grab_focus()
	_reveal_in_scroll(next)
	return next


func focus_first(root: Control) -> Control:
	var candidates := _focusable_controls(root, "")
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left: Control, right: Control) -> bool:
		var left_disabled := left is BaseButton and (left as BaseButton).disabled
		var right_disabled := right is BaseButton and (right as BaseButton).disabled
		if left_disabled != right_disabled:
			return not left_disabled
		var left_position := left.get_global_rect().position
		var right_position := right.get_global_rect().position
		return left_position.y < right_position.y or is_equal_approx(left_position.y, right_position.y) and left_position.x < right_position.x
	)
	var first := candidates[0]
	first.grab_focus()
	_reveal_in_scroll(first)
	return first


func activate_focused(root: Control) -> bool:
	var viewport := root.get_viewport() if root != null else null
	var focused := viewport.gui_get_focus_owner() if viewport != null else null
	if focused == null or not focused.is_visible_in_tree():
		focused = focus_first(root)
	if focused is BaseButton and not (focused as BaseButton).disabled:
		(focused as BaseButton).pressed.emit()
		return true
	return false


func inspection_text(root: Control) -> String:
	var viewport := root.get_viewport() if root != null else null
	var focused := viewport.gui_get_focus_owner() if viewport != null else null
	if focused == null:
		return ""
	return focused.tooltip_text if not focused.tooltip_text.is_empty() else focused.accessibility_description


func scroll_active(root: Control, direction: Vector2i, step: int = 48) -> bool:
	if root == null:
		return false
	var viewport := root.get_viewport()
	var focused := viewport.gui_get_focus_owner() if viewport != null else null
	var scroll := _scroll_ancestor(focused)
	if scroll == null:
		for candidate: Node in root.find_children("*", "ScrollContainer", true, false):
			if (candidate as ScrollContainer).is_visible_in_tree():
				scroll = candidate as ScrollContainer
				break
	if scroll == null:
		return false
	if direction.y != 0:
		scroll.scroll_vertical += direction.y * step
	else:
		scroll.scroll_horizontal += direction.x * step
	return true


func _geometric_neighbor(root: Control, current: Control, direction: Vector2i, perpendicular_weight: float = 2.0) -> Control:
	var focus_group := String(current.get_meta("focus_group", ""))
	var current_center := current.get_global_rect().get_center()
	var best: Control
	var best_score := INF
	for candidate: Control in _focusable_controls(root, focus_group):
		if candidate == current:
			continue
		var offset := candidate.get_global_rect().get_center() - current_center
		var primary := offset.dot(Vector2(direction))
		if primary <= 0.5:
			continue
		var perpendicular := absf(offset.cross(Vector2(direction)))
		var score := primary + perpendicular * perpendicular_weight
		if score < best_score:
			best = candidate
			best_score = score
	return best


func _focusable_controls(root: Node, focus_group: String) -> Array[Control]:
	var result: Array[Control] = []
	for child: Node in root.find_children("*", "Control", true, false):
		var control := child as Control
		if _is_focusable(control) and (focus_group.is_empty() or String(control.get_meta("focus_group", "")) == focus_group):
			result.append(control)
	return result


func _is_focusable(control: Control) -> bool:
	return control != null and control.is_inside_tree() and control.is_visible_in_tree() and control.focus_mode == Control.FOCUS_ALL


func _adjust_value(control: Control, direction: Vector2i) -> bool:
	if not control is Range or direction.x == 0:
		return false
	var range := control as Range
	range.value = clampf(range.value + range.step * direction.x, range.min_value, range.max_value)
	return true


func _reveal_in_scroll(control: Control) -> void:
	var scroll := _scroll_ancestor(control)
	if scroll != null:
		scroll.ensure_control_visible(control)


func _scroll_ancestor(control: Control) -> ScrollContainer:
	var ancestor := control as Node
	while ancestor != null:
		if ancestor is ScrollContainer:
			return ancestor as ScrollContainer
		ancestor = ancestor.get_parent()
	return null


func _side_for(direction: Vector2i) -> int:
	if direction == Vector2i.UP: return SIDE_TOP
	if direction == Vector2i.DOWN: return SIDE_BOTTOM
	if direction == Vector2i.LEFT: return SIDE_LEFT
	if direction == Vector2i.RIGHT: return SIDE_RIGHT
	return -1
