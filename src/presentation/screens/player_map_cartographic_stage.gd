class_name PlayerMapCartographicStage
extends MarginContainer

const TABLE_CENTER := Color("303a37")
const TABLE_EDGE := Color("111617")
const BORDER := Color("596166")
const GOLD := Color("b99443")


func _init() -> void:
	name = "PlayerMapCartographicStage"
	custom_minimum_size = Vector2(384, 320)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_top", 16)
	add_theme_constant_override("margin_right", 16)
	add_theme_constant_override("margin_bottom", 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	draw_rect(outer, TABLE_EDGE, true)
	var table := outer.grow(-5.0)
	draw_rect(table, TABLE_CENTER, true)
	draw_rect(table, BORDER, false, 2.0)
	draw_rect(table.grow(-5.0), Color(GOLD, 0.48), false, 1.0)
