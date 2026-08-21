class_name ClassicIntroAnimation
extends TextureRect

const MANIFEST_PATH := "res://src/presentation/assets/ui/intro/intro-animation.json"


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_load_animation()


func _load_animation() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var frame_records: Array = (parsed as Dictionary).get("frames", []) as Array
	if frame_records.is_empty() or frame_records.size() > 256:
		return
	var animation := AnimatedTexture.new()
	animation.frames = frame_records.size()
	animation.one_shot = false
	for index: int in frame_records.size():
		var record := frame_records[index] as Dictionary
		var frame_texture := load(String(record.get("path", ""))) as Texture2D
		if frame_texture == null:
			return
		animation.set_frame_texture(index, frame_texture)
		animation.set_frame_duration(index, maxf(float(record.get("duration_ms", 80)) / 1000.0, 0.01))
	animation.pause = false
	animation.speed_scale = 1.0
	texture = animation
