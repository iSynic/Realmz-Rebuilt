class_name ClassicTreasureTakeEffect
extends Control

const FRAME_COUNT := 24
const DURATION_SECONDS := 0.40
const SOURCE_ICON_SIZE := 48.0
const SOURCE_OUTER_SIZE := 28.0

var progress: float = 0.0:
	set(value):
		progress = value
		queue_redraw()
var item_texture: Texture2D
var _frame_colors: Array[Color] = []


func begin(texture: Texture2D, stable_visual_seed: String = "") -> Tween:
	item_texture = texture
	_build_frame_colors(stable_visual_seed)
	custom_minimum_size = Vector2(84.0, 84.0)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 200
	var tween := create_tween()
	tween.tween_property(self, "progress", 1.0, DURATION_SECONDS)
	return tween


func _draw() -> void:
	var center := size * 0.5
	var frame := mini(FRAME_COUNT - 1, floori(progress * float(FRAME_COUNT)))
	if item_texture != null:
		var source_size := item_texture.get_size()
		var draw_size := Vector2(minf(source_size.x, SOURCE_ICON_SIZE), minf(source_size.y, SOURCE_ICON_SIZE))
		draw_texture_rect(item_texture, Rect2(center - draw_size * 0.5, draw_size), false)
	var inset := float(frame + 1)
	var outer_radius := SOURCE_OUTER_SIZE * 0.5 + inset
	var inner_radius := maxf(0.0, SOURCE_ICON_SIZE * 0.5 - inset)
	var frame_color := _frame_colors[frame] if frame < _frame_colors.size() else Color.WHITE
	draw_arc(center, outer_radius, 0.0, TAU, 64, frame_color, 1.0, false)
	if inner_radius > 0.0:
		draw_arc(center, inner_radius, 0.0, TAU, 64, Color.WHITE, 1.0, false)


func _build_frame_colors(stable_visual_seed: String) -> void:
	_frame_colors.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(stable_visual_seed) & 0x7fffffff
	for _frame: int in FRAME_COUNT:
		# Castle assigns fresh 16-bit red, blue, and green components on every
		# QuickDraw iteration. This local generator is cosmetic and cannot consume
		# the serialized session RNG.
		_frame_colors.append(Color(rng.randf(), rng.randf(), rng.randf(), 1.0))


static func frame_radii(frame: int) -> Vector2:
	var inset := float(clampi(frame, 0, FRAME_COUNT - 1) + 1)
	return Vector2(SOURCE_OUTER_SIZE * 0.5 + inset, maxf(0.0, SOURCE_ICON_SIZE * 0.5 - inset))
