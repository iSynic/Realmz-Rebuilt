class_name PlayerMapCartographicStage
extends MarginContainer

const MAP_SURFACE := Color("aebba5")
const MAP_EDGE := Color("64705f")


func _init() -> void:
	name = "PlayerMapCartographicStage"
	custom_minimum_size = Vector2(384, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("margin_left", 6)
	add_theme_constant_override("margin_top", 4)
	add_theme_constant_override("margin_right", 6)
	add_theme_constant_override("margin_bottom", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, MAP_SURFACE, true)
	draw_rect(outer.grow(-1.0), MAP_EDGE, false, 2.0)
