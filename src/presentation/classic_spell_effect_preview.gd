class_name ClassicSpellEffectPreview
extends PanelContainer

const FRAME_DURATION_SECONDS := 0.12

var resource_ids: Array[int] = []
var _frames: Array[Texture2D] = []
var _frame_index := 0
var _preview: TextureRect


func present(media: ClassicMediaCatalog, resource_type: String, exact_resource_ids: Array[int]) -> bool:
	resource_ids = exact_resource_ids.duplicate()
	name = "StartingSpellAnimation"
	theme_type_variation = &"ClassicInset"
	custom_minimum_size = Vector2(128.0, 132.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear()
	_frames.clear()
	_frame_index = 0
	_preview = null
	if media != null:
		for resource_id: int in resource_ids:
			var asset := media.asset_by_resource(resource_type, resource_id)
			var texture := media.image_texture(asset) if asset != null and _has_meaningful_pixels(media, asset) else null
			if texture == null:
				_frames.clear()
				break
			_frames.append(texture)
	if _frames.size() != resource_ids.size() or _frames.is_empty():
		return false
	_preview = TextureRect.new()
	_preview.name = "StartingSpellAnimationFrames"
	_preview.texture = _frames[0]
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_preview)
	var timer := Timer.new()
	timer.wait_time = FRAME_DURATION_SECONDS
	timer.autostart = true
	timer.timeout.connect(_advance_frame)
	add_child(timer)
	return true


func _advance_frame() -> void:
	if _preview == null or _frames.is_empty():
		return
	_frame_index = (_frame_index + 1) % _frames.size()
	_preview.texture = _frames[_frame_index]


func _has_meaningful_pixels(media: ClassicMediaCatalog, asset: MediaAsset) -> bool:
	var bytes := media.read_bytes(asset)
	if bytes.is_empty():
		return false
	var image := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match asset.mime_type:
		"image/png": error = image.load_png_from_buffer(bytes)
		"image/jpeg": error = image.load_jpg_from_buffer(bytes)
		"image/webp": error = image.load_webp_from_buffer(bytes)
	if error != OK:
		return false
	for y: int in image.get_height():
		for x: int in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a > 0.02 and (pixel.r < 0.98 or pixel.g < 0.98 or pixel.b < 0.98):
				return true
	return false


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
