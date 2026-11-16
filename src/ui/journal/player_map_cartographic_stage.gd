## Owns player map cartographic stage presentation behavior for its scene-authored screen.

class_name PlayerMapCartographicStage
extends MarginContainer


func _init() -> void:
	name = "PlayerMapCartographicStage"
	UiSizing.minimum_size(self, Vector2(384, 0))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	UiSizing.constant(self, &"margin_left", 6)
	UiSizing.constant(self, &"margin_top", 4)
	UiSizing.constant(self, &"margin_right", 6)
	UiSizing.constant(self, &"margin_bottom", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED: queue_redraw()


## The stage is a recessed well in the current interface theme, not a slate tile.
func _draw() -> void:
	var colors := UiThemeService.current().colors
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, colors[&"surface"], true)
	draw_rect(outer.grow(-1.0), Color(colors[&"border"], 0.7), false, 1.0)
