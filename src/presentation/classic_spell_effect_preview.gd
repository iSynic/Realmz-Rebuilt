class_name ClassicSpellEffectPreview
extends PanelContainer

const MUTED := Color("9aa0a8")
const FRAME_DURATION_SECONDS := 0.12

var resource_ids: Array[int] = []


func present(media: ClassicMediaCatalog, resource_type: String, exact_resource_ids: Array[int]) -> void:
	resource_ids = exact_resource_ids.duplicate()
	name = "StartingSpellAnimation"
	theme_type_variation = &"ClassicInset"
	custom_minimum_size = Vector2(128.0, 132.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clear()
	var textures: Array[Texture2D] = []
	if media != null:
		for resource_id: int in resource_ids:
			var asset := media.asset_by_resource(resource_type, resource_id)
			var texture := media.image_texture(asset) if asset != null else null
			if texture == null:
				textures.clear()
				break
			textures.append(texture)
	if textures.size() != resource_ids.size() or textures.is_empty():
		var unavailable := Label.new()
		unavailable.name = "StartingSpellAnimationUnavailable"
		unavailable.text = "Classic spell animation unavailable"
		unavailable.modulate = MUTED
		unavailable.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		unavailable.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		unavailable.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unavailable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		unavailable.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(unavailable)
		return
	var animation := AnimatedTexture.new()
	animation.frames = textures.size()
	animation.one_shot = false
	for index: int in textures.size():
		animation.set_frame_texture(index, textures[index])
		animation.set_frame_duration(index, FRAME_DURATION_SECONDS)
	animation.pause = false
	var preview := TextureRect.new()
	preview.name = "StartingSpellAnimationFrames"
	preview.texture = animation
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(preview)


func _clear() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
