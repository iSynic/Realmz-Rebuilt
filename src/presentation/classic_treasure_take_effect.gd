class_name ClassicTreasureTakeEffect
extends Control

const DURATION_SECONDS := 0.32
const COLORS: Array[Color] = [
	Color("ef4d4d"),
	Color("f0d05b"),
	Color("6fd56f"),
	Color("62d8ff"),
	Color("b97cff"),
]

var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()
var item_texture: Texture2D


func begin(texture: Texture2D) -> Tween:
	item_texture = texture
	custom_minimum_size = Vector2(58.0, 68.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, DURATION_SECONDS)
	return tween


func _draw() -> void:
	var center := size * 0.5
	if item_texture != null:
		var source_size := item_texture.get_size()
		var draw_size := Vector2(minf(source_size.x, 32.0), minf(source_size.y, 32.0))
		draw_texture_rect(item_texture, Rect2(center - draw_size * 0.5, draw_size), false)
	var outer_radius := lerpf(10.0, 29.0, progress)
	var inner_radius := lerpf(24.0, 3.0, progress)
	var color_index := mini(COLORS.size() - 1, floori(progress * COLORS.size()))
	draw_arc(center, outer_radius, 0.0, TAU, 48, COLORS[color_index], 1.5, false)
	draw_arc(center, inner_radius, 0.0, TAU, 48, Color.WHITE, 1.0, false)
