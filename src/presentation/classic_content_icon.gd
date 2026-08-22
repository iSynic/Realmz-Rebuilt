class_name ClassicContentIcon
extends CenterContainer

const MUTED := Color("748087")


func configure(resource_type: String, resource_id: int, media: ClassicMediaCatalog, side: float = 52.0, semantic_label: String = "", unavailable_label: String = "Item image unavailable") -> void:
	custom_minimum_size = Vector2(side, side)
	var asset: MediaAsset = media.asset_by_resource(resource_type, resource_id) if media != null and resource_id != 0 else null
	var texture: Texture2D = media.image_texture(asset) if media != null and asset != null else null
	if texture != null:
		var image := TextureRect.new()
		image.name = "ContentImage"
		image.custom_minimum_size = Vector2(side, side)
		image.texture = texture
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		image.tooltip_text = semantic_label
		add_child(image)
		return
	var fallback := Label.new()
	fallback.name = "ContentImageUnavailable"
	fallback.text = "◇"
	fallback.tooltip_text = unavailable_label
	fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fallback.add_theme_color_override("font_color", MUTED)
	add_child(fallback)
