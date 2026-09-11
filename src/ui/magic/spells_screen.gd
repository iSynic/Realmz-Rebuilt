## Owns the stable, editor-visible controls and content regions of the Spells screen.
class_name SpellsScreen
extends ScreenFrame

const WORKSPACE_PATH := "WorkspaceColumn/BodyClip/ScreenBodyScroll/ScreenBody/SpellsWorkspace"


func workspace() -> SpellsWorkspace:
	return get_node(WORKSPACE_PATH) as SpellsWorkspace


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if mouse_event.button_index != MOUSE_BUTTON_LEFT or mouse_event.pressed:
		return
	var candidate := _rail_button_at(mouse_event.position)
	if candidate == null or candidate.disabled or candidate.button_pressed:
		return
	# The spell rail overlaps the live map stage in expanded layouts. GUI input
	# normally reaches the higher workspace, but native retail composition can
	# let the stage consume the release. Defer a fallback until ordinary GUI
	# dispatch has had the opportunity to toggle the authored button.
	_resolve_rail_release.call_deferred(candidate)


func _rail_button_at(viewport_position: Vector2) -> Button:
	for prefix: String in ["SpellLevel", "SpellPower"]:
		for number: int in range(1, 8):
			var button := find_child("%s%d" % [prefix, number], true, false) as Button
			if button != null and button.is_visible_in_tree() and button.get_global_rect().has_point(viewport_position):
				return button
	return null


func _resolve_rail_release(button: Button) -> void:
	if is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled and not button.button_pressed:
		button.pressed.emit()
