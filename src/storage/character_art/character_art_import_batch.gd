## Prepares bounded image batches before a single library-membership commit.
class_name CharacterArtImportBatch
extends RefCounted

const MAX_FILES := 256
const MAX_SOURCE_BYTES := 64 * 1024 * 1024
const MAX_SOURCE_PIXELS := 16 * 1024 * 1024
const EXTENSIONS := ["png", "jpg", "jpeg", "webp"]

var kind: String
var items: Array[Dictionary] = []
var last_error := ""
var _source_bytes := 0
var _source_pixels := 0


func _init(art_kind: String) -> void:
	kind = art_kind


static func folder_paths(path: String) -> PackedStringArray:
	var directory := DirAccess.open(path)
	var result := PackedStringArray()
	if directory == null:
		return result
	for filename: String in directory.get_files():
		if filename.get_extension().to_lower() in EXTENSIONS:
			result.append(path.path_join(filename))
	result.sort()
	return result


func append_file(path: String) -> void:
	var item := {"path": path, "label": path.get_file().get_basename().strip_edges().left(128), "source": null, "png": PackedByteArray(), "id": "", "error": "", "mode": "fit", "filter": "nearest", "crop": Rect2i()}
	if item.label.is_empty():
		item.label = "Artwork"
	items.append(item)
	var file := FileAccess.open(path, FileAccess.READ)
	var length := file.get_length() if file != null else -1
	file = null
	if items.size() > MAX_FILES or length < 0 or length > MAX_SOURCE_BYTES - _source_bytes:
		item.error = "This batch exceeds 256 images or 64 MiB of source files. Import smaller batches."
		return
	_source_bytes += length
	var source := CharacterArtImage.new()
	if not source.open(path):
		item.error = source.last_error
		return
	var pixels := source.image.get_width() * source.image.get_height()
	if pixels > MAX_SOURCE_PIXELS - _source_pixels:
		item.error = "This batch exceeds 16 million decoded pixels. Import smaller batches."
		return
	_source_pixels += pixels
	item.source = source
	var side := mini(source.image.get_width(), source.image.get_height())
	item.crop = Rect2i((source.image.get_size() - Vector2i(side, side)) / 2, Vector2i(side, side))
	prepare_item(items.size() - 1, "fit", "nearest", item.crop)


func prepare_item(index: int, mode: String, filter: String, crop: Rect2i) -> Image:
	if index < 0 or index >= items.size():
		return null
	var item := items[index]
	var source := item.source as CharacterArtImage
	if source == null:
		return null
	item.mode = mode
	item.filter = filter
	item.crop = crop
	item.png = PackedByteArray()
	item.id = ""
	var prepared := source.prepare(kind, mode, filter, crop)
	item.error = source.last_error
	if prepared != null:
		item.png = prepared.save_png_to_buffer()
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(item.png)
		item.id = CharacterArtIdentity.make(kind, hash.finish().hex_encode())
	return prepared


func ready_count() -> int:
	var count := 0
	for item: Dictionary in items:
		if not item.id.is_empty() and item.error.is_empty():
			count += 1
	return count
