class_name PlayerMapCartographicStage
extends MarginContainer

const SLATE_TEXTURE_PATH := "res://src/presentation/assets/ui/classic-charcoal-slate-tile.png"
const MAP_EDGE := Color("59666a")

var _slate_texture: Texture2D


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
	_slate_texture = load(SLATE_TEXTURE_PATH) as Texture2D
	resized.connect(queue_redraw)


func _draw() -> void:
	var outer := Rect2(Vector2.ZERO, size)
	if _slate_texture != null:
		draw_texture_rect(_slate_texture, outer, true)
	else:
		draw_rect(outer, Color("151a1c"), true)
	draw_rect(outer.grow(-1.0), MAP_EDGE, false, 2.0)
