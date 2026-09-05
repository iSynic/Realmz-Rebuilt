## Presents scenario picture events in the shell's scene-authored picture stage.
class_name GameShellPicturePresenter
extends RefCounted

var last_media_diagnostic: Dictionary = {}
var _picture_stage: Control
var _picture: TextureRect
var _picture_caption: Label


func _init(shell: Control) -> void:
	_picture_stage = shell.get_node("%PictureStage") as Control
	_picture = shell.get_node("%Picture") as TextureRect
	_picture_caption = shell.get_node("%PictureCaption") as Label


func present(events: Array[DomainEvent], media: ClassicMediaCatalog) -> void:
	if media == null:
		return
	for event: DomainEvent in events:
		if event.kind != &"picture_requested":
			continue
		_present_picture(int(event.payload.get("pictureId", 0)), media)


func _present_picture(picture_id: int, media: ClassicMediaCatalog) -> void:
	var asset := media.asset_by_resource("PICT", picture_id)
	if asset == null:
		last_media_diagnostic = media.resolution_diagnostic("PICT", picture_id, "classic-picture")
		_picture.texture = null
		_picture.tooltip_text = "Scenario picture unavailable"
		_picture_caption.text = ""
		_picture_stage.visible = true
		return
	var image := _decode_image(asset, media.read_bytes(asset))
	last_media_diagnostic = media.resolution_diagnostic("PICT", picture_id, "classic-picture", "decoded" if image != null else "decode-failed")
	_picture.texture = ImageTexture.create_from_image(image) if image != null else null
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.tooltip_text = "Scenario picture" if image != null else "Scenario picture unavailable"
	_picture_caption.text = ""
	_picture_stage.visible = true


static func _decode_image(asset: MediaAsset, bytes: PackedByteArray) -> Image:
	if bytes.is_empty():
		return null
	var image := Image.new()
	var extension := asset.path.get_extension().to_lower()
	var error := ERR_UNAVAILABLE
	if asset.mime_type.to_lower() == "image/png" or extension == "png":
		error = image.load_png_from_buffer(bytes)
	elif asset.mime_type.to_lower() in ["image/jpeg", "image/jpg"] or extension in ["jpg", "jpeg"]:
		error = image.load_jpg_from_buffer(bytes)
	elif asset.mime_type.to_lower() == "image/webp" or extension == "webp":
		error = image.load_webp_from_buffer(bytes)
	return image if error == OK else null
