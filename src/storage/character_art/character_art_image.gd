## Decodes imported images and prepares an explicit native-size artwork preview.
class_name CharacterArtImage
extends RefCounted

const MAX_SOURCE_BYTES := 16 * 1024 * 1024
const MAX_SOURCE_EDGE := 2048

var image: Image
var source_bytes := PackedByteArray()
var source_extension: String
var last_error := ""


func open(path: String) -> bool:
	image = null
	source_bytes.clear()
	last_error = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_SOURCE_BYTES:
		last_error = "Choose a PNG, JPEG, or WebP image under 16 MiB."
		return false
	source_bytes = file.get_buffer(file.get_length())
	source_extension = path.get_extension().to_lower()
	var candidate := Image.new()
	var error := ERR_FILE_UNRECOGNIZED
	match source_extension:
		"png": error = candidate.load_png_from_buffer(source_bytes)
		"jpg", "jpeg": error = candidate.load_jpg_from_buffer(source_bytes)
		"webp": error = candidate.load_webp_from_buffer(source_bytes)
	if error != OK or candidate.is_empty() or candidate.get_width() > MAX_SOURCE_EDGE or candidate.get_height() > MAX_SOURCE_EDGE:
		last_error = "The image could not be decoded, or exceeds 2048 pixels on either side."
		return false
	candidate.convert(Image.FORMAT_RGBA8)
	image = candidate
	return true


func prepare(kind: String, mode: String, filter: String, crop: Rect2i) -> Image:
	last_error = ""
	if image == null or kind not in ["portrait", "combat-icon"] or mode not in ["fit", "crop", "resize"] or filter not in ["nearest", "lanczos"]:
		last_error = "Choose an image and valid artwork settings."
		return null
	var edge := 44 if kind == "portrait" else 32
	var interpolation := Image.INTERPOLATE_NEAREST if filter == "nearest" else Image.INTERPOLATE_LANCZOS
	var result := image.duplicate() as Image
	if mode == "crop":
		if crop.size.x <= 0 or crop.size.x != crop.size.y or not Rect2i(Vector2i.ZERO, image.get_size()).encloses(crop):
			last_error = "The square crop must stay inside the original image."
			return null
		result = image.get_region(crop)
	if mode != "fit":
		result.resize(edge, edge, interpolation)
		return result
	var scale := minf(float(edge) / float(result.get_width()), float(edge) / float(result.get_height()))
	var width := clampi(roundi(result.get_width() * scale), 1, edge)
	var height := clampi(roundi(result.get_height() * scale), 1, edge)
	result.resize(width, height, interpolation)
	var padded := Image.create(edge, edge, false, Image.FORMAT_RGBA8)
	padded.fill(Color.TRANSPARENT)
	padded.blit_rect(result, Rect2i(Vector2i.ZERO, result.get_size()), Vector2i((edge - width) / 2, (edge - height) / 2))
	return padded
