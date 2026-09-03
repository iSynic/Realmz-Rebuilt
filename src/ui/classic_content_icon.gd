## Presents Classic content icon through the Godot interface.

class_name ClassicContentIcon
extends CenterContainer

const MUTED := Color("748087")


func configure(resource_type: String, resource_id: int, media: ClassicMediaCatalog, side: float = 52.0, semantic_label: String = "", unavailable_label: String = "Item image unavailable") -> void:
	custom_minimum_size = Vector2(side, side)
	var asset: MediaAsset = media.asset_by_resource(resource_type, resource_id) if media != null and resource_id != 0 else null
	var texture: Texture2D = media.image_texture(asset) if media != null and asset != null else null
	var image := %ContentImage as TextureRect
	var fallback := %ContentImageUnavailable as Label
	image.custom_minimum_size = Vector2(side, side)
	image.texture = texture
	image.tooltip_text = semantic_label
	image.visible = texture != null
	fallback.visible = texture == null
	fallback.tooltip_text = unavailable_label
