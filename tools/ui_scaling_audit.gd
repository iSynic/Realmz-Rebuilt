## Checks rendered control reachability while the isolated gallery changes scale.
extends RefCounted

const OUTPUT_ROOT := "res://artifacts/ui-scaling-audit/gallery"
const SETTINGS: Array[Array] = [
	[Vector2i(1280, 720), "auto", 1.0, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(800, 600), "auto", 1.0, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(1920, 1080), "auto", 1.0, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(2560, 1440), "auto", 1.0, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(3840, 2160), "auto", 1.0, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(800, 600), "auto", 1.5, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(1280, 720), "auto", 1.5, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(2560, 1440), "300", 1.5, PresentationSettings.DISPLAY_RESPONSIVE],
	[Vector2i(2560, 1440), "auto", 1.5, PresentationSettings.DISPLAY_INTEGER_WINDOW],
	[Vector2i(3440, 1440), "auto", 1.5, PresentationSettings.DISPLAY_FILL_WINDOW],
]


static func state_key(label: String) -> String:
	if not label.ends_with("-1280x720"):
		return ""
	return label.trim_prefix("canonical-").trim_prefix("wide-").trim_suffix("-1280x720")


static func inspect(root: Control) -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	var viewport := root.get_viewport()
	var bounds := viewport.get_visible_rect().grow(1.0)
	for node: Node in root.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or control.get_viewport() != viewport:
			continue
		if not (control is BaseButton or control is Label or control is RichTextLabel or control is LineEdit or control is TabBar):
			continue
		var rect := control.get_global_rect()
		if not rect.has_area():
			continue
		var horizontal := rect.position.x < bounds.position.x or rect.end.x > bounds.end.x
		var vertical := rect.position.y < bounds.position.y or rect.end.y > bounds.end.y
		var ancestor := control.get_parent()
		var exit_action := control is Button and (control as Button).text in ["Done", "Back", "Cancel", "Continue", "Leave", "Back to Treasure", "Back to encounter", "Confirm spell selection"]
		while ancestor != null and ancestor != root:
			if ancestor is ScrollContainer:
				var scroll := ancestor as ScrollContainer
				if scroll.horizontal_scroll_mode in [ScrollContainer.SCROLL_MODE_AUTO, ScrollContainer.SCROLL_MODE_SHOW_ALWAYS]:
					horizontal = false
				if not exit_action and scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
					vertical = false
				elif exit_action and scroll.name == &"ScreenBodyScroll" and _workspace_exit_visible(scroll, bounds):
					vertical = false
			ancestor = ancestor.get_parent()
		if horizontal or vertical:
			failures.append({"control": str(root.get_path_to(control)), "horizontal": horizontal, "vertical": vertical, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y]})
	return failures


static func _workspace_exit_visible(scroll: ScrollContainer, bounds: Rect2) -> bool:
	# An outer workspace may scroll its duplicate Done or staged Cancel while
	# keeping the route's scene-authored Back/Done action continuously available.
	var frame := scroll.find_parent("WorkspaceFrame")
	if frame == null:
		return false
	for node: Node in frame.find_children("*", "Button", true, false):
		var button := node as Button
		if not button.is_visible_in_tree() or button.text not in ["Back", "Done", "Back to shop"]:
			continue
		var rect := button.get_global_rect()
		if not bounds.encloses(rect):
			continue
		var ancestor := button.get_parent()
		var clipped := false
		while ancestor != frame:
			if ancestor is Control and (ancestor as Control).clip_contents and not (ancestor as Control).get_global_rect().encloses(rect):
				clipped = true
			ancestor = ancestor.get_parent()
		if not clipped:
			return true
	return false
