class_name PlayerMapCartographicStage
extends MarginContainer

const PARCHMENT := Color("c7ad73")
const PARCHMENT_SHADOW := Color("6f5836")
const INK := Color("403522")
const GOLD := Color("b99443")


func _init() -> void:
	name = "PlayerMapCartographicStage"
	custom_minimum_size = Vector2(384, 384)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("margin_left", 28)
	add_theme_constant_override("margin_top", 28)
	add_theme_constant_override("margin_right", 28)
	add_theme_constant_override("margin_bottom", 28)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	var sheet := outer.grow(-10.0)
	draw_rect(outer, Color("17191a"), true)
	draw_rect(sheet, PARCHMENT_SHADOW, true)
	draw_rect(sheet.grow(-3.0), PARCHMENT, true)
	draw_rect(sheet.grow(-3.0), INK, false, 2.0)
	draw_rect(sheet.grow(-8.0), Color(GOLD, 0.72), false, 1.0)
	_draw_corner_flourish(sheet.position + Vector2(12, 12), Vector2.ONE)
	_draw_corner_flourish(Vector2(sheet.end.x - 12, sheet.position.y + 12), Vector2(-1, 1))
	_draw_corner_flourish(Vector2(sheet.position.x + 12, sheet.end.y - 12), Vector2(1, -1))
	_draw_corner_flourish(sheet.end - Vector2(12, 12), -Vector2.ONE)


func _draw_corner_flourish(origin: Vector2, direction: Vector2) -> void:
	draw_line(origin, origin + Vector2(22.0 * direction.x, 0), INK, 2.0)
	draw_line(origin, origin + Vector2(0, 22.0 * direction.y), INK, 2.0)
	draw_circle(origin + Vector2(6.0 * direction.x, 6.0 * direction.y), 2.5, GOLD)
