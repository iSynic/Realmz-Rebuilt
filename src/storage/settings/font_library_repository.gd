## Stores validated player fonts as immutable, content-addressed files.
class_name FontLibraryRepository
extends RefCounted

const MAX_FONT_BYTES: int = 16 * 1024 * 1024
const MAX_INDEX_BYTES: int = 4 * 1024 * 1024
const MAX_FONTS: int = 1024
const FONT_EXTENSIONS := ["ttf", "otf"]
const INDEX_VERSION: int = 1

var root: String
var last_error: String = ""
var _data: Dictionary = {"formatVersion": INDEX_VERSION, "fonts": {}}
var _read_only: bool = false


func _init(root_path: String = "user://fonts") -> void:
	root = ProjectSettings.globalize_path(root_path)
	var index_path := root.path_join("index.json")
	if not FileAccess.file_exists(index_path):
		return
	var loaded := _read_index(index_path)
	if loaded.is_empty():
		_read_only = true
		last_error = "The font library index is damaged. Its files have been preserved."
		return
	_data = loaded


func list_fonts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in _data.fonts:
		var record: Dictionary = _data.fonts[id]
		var filename := _filename(id, record.extension)
		result.append({
			"id": id,
			"name": _display_name(record.family, record.style),
			"filename": filename,
			"path": root.path_join("blobs").path_join(filename),
		})
	return result


func import_font(source_path: String) -> Dictionary:
	last_error = ""
	if _read_only:
		return _failure("The font library index is damaged and is read-only.")
	var extension := source_path.get_extension().to_lower()
	if not extension in FONT_EXTENSIONS:
		return _failure("Choose a .ttf or .otf font file.")
	var captured := _capture_font(source_path)
	if not captured.ok:
		return _failure(captured.error)
	return _store_font(extension, captured)


func _capture_font(source_path: String) -> Dictionary:
	var absolute_source := ProjectSettings.globalize_path(source_path)
	var source := FileAccess.open(absolute_source, FileAccess.READ)
	if source == null:
		return {"ok": false, "error": "Could not read the selected font file."}
	var source_size := source.get_length()
	if source_size <= 0 or source_size > MAX_FONT_BYTES:
		source.close()
		return {"ok": false, "error": "Font files must be between 1 byte and 16 MiB."}
	var bytes := source.get_buffer(source_size)
	var read_error := source.get_error()
	source.close()
	if read_error != OK or bytes.size() != source_size:
		return {"ok": false, "error": "Could not read the complete font file."}

	var probe := FontFile.new()
	probe.data = bytes
	var family := probe.get_font_name().strip_edges()
	var style := probe.get_font_style_name().strip_edges()
	if family.is_empty() or probe.get_supported_chars().is_empty():
		return {"ok": false, "error": "The selected file is not a readable font with a family name and glyphs."}
	if family.length() > 256 or style.length() > 256:
		return {"ok": false, "error": "The font contains oversized family or style metadata."}
	return {"ok": true, "error": "", "id": _sha256(bytes), "family": family, "style": style, "bytes": bytes}


func _store_font(extension: String, captured: Dictionary) -> Dictionary:
	var id: String = captured.id
	if _data.fonts.has(id):
		var current: Dictionary = _data.fonts[id]
		if font_path(id).is_empty():
			return _failure("The indexed immutable font file is missing or failed its hash check.")
		return {"ok": true, "error": "", "id": id, "name": _display_name(current.family, current.style), "duplicate": true}
	if _data.fonts.size() >= MAX_FONTS:
		return _failure("The font library has reached its 1,024-font limit.")
	var blob_error := _store_blob(id, extension, captured.bytes)
	if not blob_error.is_empty():
		return _failure(blob_error)
	var candidate := _data.duplicate(true)
	candidate.fonts[id] = {"extension": extension, "family": captured.family, "style": captured.style}
	if not _commit(candidate):
		return _failure(last_error)
	return {"ok": true, "error": "", "id": id, "name": _display_name(captured.family, captured.style), "duplicate": false}


func _store_blob(id: String, extension: String, bytes: PackedByteArray) -> String:
	var blob_directory := root.path_join("blobs")
	if DirAccess.make_dir_recursive_absolute(blob_directory) != OK:
		return "Could not create font library storage."
	var filename := _filename(id, extension)
	var blob_path := blob_directory.path_join(filename)
	if FileAccess.file_exists(blob_path):
		if _file_sha256(blob_path) != id:
			return "An existing immutable font blob failed its hash check."
	else:
		var temporary_blob := blob_path + ".tmp"
		var output := FileAccess.open(temporary_blob, FileAccess.WRITE)
		if output == null:
			return "Could not open temporary font storage."
		output.store_buffer(bytes)
		output.flush()
		var write_error := output.get_error()
		output.close()
		if write_error != OK or _file_sha256(temporary_blob) != id:
			DirAccess.remove_absolute(temporary_blob)
			return "The stored font failed its temporary-file readback check."
		if DirAccess.rename_absolute(temporary_blob, blob_path) != OK:
			DirAccess.remove_absolute(temporary_blob)
			return "Could not commit the immutable font file."
	return ""


func font_path(id: String) -> String:
	if not _data.fonts.has(id) or not _valid_hash(id):
		return ""
	var record: Dictionary = _data.fonts[id]
	var path := root.path_join("blobs").path_join(_filename(id, record.extension))
	return path if _file_sha256(path) == id else ""


func _commit(candidate: Dictionary) -> bool:
	if _read_only:
		last_error = "The font library index is damaged and is read-only."
		return false
	if not _valid_document(candidate):
		last_error = "The font library produced an invalid index."
		return false
	var text := CanonicalJson.encode(candidate)
	if text.to_utf8_buffer().size() > MAX_INDEX_BYTES:
		last_error = "The font library index has reached its size limit."
		return false
	if DirAccess.make_dir_recursive_absolute(root) != OK:
		last_error = "Could not create font library storage."
		return false
	var path := root.path_join("index.json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the temporary font index."
		return false
	file.store_string(text)
	file.flush()
	var write_error := file.get_error()
	file.close()
	var readback := _read_index(temporary)
	if write_error != OK or readback.is_empty() or CanonicalJson.encode(readback) != text:
		last_error = "The font index failed readback validation."
	elif FileAccess.file_exists(path) and DirAccess.copy_absolute(path, path + ".bak") != OK:
		last_error = "Could not preserve the previous font index."
	elif DirAccess.rename_absolute(temporary, path) != OK:
		last_error = "Could not atomically replace the font index."
	if not last_error.is_empty():
		DirAccess.remove_absolute(temporary)
		return false
	_data = readback
	return true


func _read_index(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	if file.get_length() > MAX_INDEX_BYTES:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not _valid_document(parser.data):
		return {}
	return parser.data


static func _valid_document(value: Variant) -> bool:
	if not value is Dictionary or value.size() != 2 or value.get("formatVersion") != INDEX_VERSION or not value.get("fonts") is Dictionary:
		return false
	var fonts: Dictionary = value.fonts
	if fonts.size() > MAX_FONTS:
		return false
	for id: Variant in fonts:
		var record: Variant = fonts[id]
		if not _valid_hash(id) or not record is Dictionary or record.size() != 3:
			return false
		if not record.has("extension") or not record.extension in FONT_EXTENSIONS:
			return false
		for field: String in ["family", "style"]:
			if not record.has(field) or not record[field] is String or record[field].length() > 256:
				return false
		if record.family.strip_edges().is_empty():
			return false
	return true


static func _valid_hash(value: Variant) -> bool:
	if not value is String or value.length() != 64:
		return false
	for character: String in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


static func _file_sha256(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() <= 0 or file.get_length() > MAX_FONT_BYTES:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		var chunk := file.get_buffer(64 * 1024)
		if chunk.is_empty():
			file.close()
			return ""
		context.update(chunk)
	file.close()
	return context.finish().hex_encode()


static func _filename(id: String, extension: String) -> String:
	return "%s.%s" % [id, extension]


static func _display_name(family: String, style: String) -> String:
	return family if style.is_empty() else "%s %s" % [family, style]


func _failure(message: String) -> Dictionary:
	last_error = message
	return {"ok": false, "error": message, "id": "", "name": "", "duplicate": false}
