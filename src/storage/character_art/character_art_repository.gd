## Owns the player's managed artwork without changing compiled scenario content.
class_name CharacterArtRepository
extends RefCounted

var _root: String
var last_error := ""


func _init(root: String = "user://character-art") -> void:
	_root = root.trim_suffix("/")


func media() -> CharacterArtBundle:
	var result := CharacterArtBundle.new()
	var directory := DirAccess.open(_root)
	if directory == null:
		return result
	for filename: String in directory.get_files():
		if not filename.ends_with(".json"):
			continue
		var entry := _read_entry(_root.path_join(filename))
		if entry == null:
			continue
		for asset: MediaAsset in entry.assets():
			if filename != _entry_path(asset.id).get_file():
				continue
			var metadata := entry.entries()[0]
			result.add(asset.id, metadata.group, metadata.label, metadata.kind, entry.read_bytes(asset))
	return result


func selected(characters: Array[CharacterState]) -> CharacterArtBundle:
	last_error = ""
	var result := CharacterArtBundle.new()
	var selected_ids: Dictionary = {}
	for character: CharacterState in characters:
		for id: String in [character.portrait_id, character.combat_icon_id]:
			if CharacterArtIdentity.is_imported(id):
				selected_ids[id] = true
	for id: String in selected_ids:
		var entry := _read_entry(_entry_path(id))
		if entry == null or entry.asset_by_id(id) == null:
			last_error = "Selected character artwork is missing or invalid: %s" % id
			return null
		var metadata := entry.entries()[0]
		result.add(id, metadata.group, metadata.label, metadata.kind, entry.read_bytes(entry.asset_by_id(id)))
	return result if result.matches_characters(characters) else null


func import_image(source: CharacterArtImage, group: String, label: String, kind: String, mode: String, filter: String, crop: Rect2i) -> String:
	last_error = ""
	if source == null:
		return ""
	var prepared := source.prepare(kind, mode, filter, crop)
	if prepared == null:
		last_error = source.last_error
		return ""
	var bytes := prepared.save_png_to_buffer()
	var id := CharacterArtIdentity.make(kind, _hash(bytes))
	var bundle := CharacterArtBundle.new()
	if not bundle.add(id, group.strip_edges(), label.strip_edges(), kind, bytes):
		last_error = "Provide a race/group name and artwork name of at most 128 characters."
		return ""
	if not _ensure_directory():
		return ""
	var original_path := _root.path_join("originals").path_join(_hash(source.source_bytes) + "." + source.source_extension)
	if not FileAccess.file_exists(original_path) and not _write_verified_bytes(original_path, source.source_bytes):
		return ""
	return id if install(bundle) else ""


func install(bundle: CharacterArtBundle) -> bool:
	last_error = ""
	if bundle == null:
		return false
	if bundle.assets().is_empty():
		return true
	if not _ensure_directory():
		return false
	for record: Dictionary in bundle.to_data():
		var id: String = record.id
		var path := _entry_path(id)
		if FileAccess.file_exists(path):
			var existing := _read_entry(path)
			if existing == null or existing.asset_by_id(id) == null:
				last_error = "An existing artwork library record failed validation."
				return false
			continue
		var bytes := JSON.stringify([record], "", true, true).to_utf8_buffer()
		if not _write_verified_bytes(path, bytes):
			return false
		if _read_entry(path) == null:
			last_error = "Artwork library readback failed."
			return false
	return true


func _entry_path(id: String) -> String:
	if not CharacterArtIdentity.is_valid(id, "portrait") and not CharacterArtIdentity.is_valid(id, "combat-icon"):
		return ""
	return _root.path_join(id.trim_prefix(CharacterArtIdentity.PREFIX).replace(":", "-") + ".json")


func _read_entry(path: String) -> CharacterArtBundle:
	var file := FileAccess.open(path, FileAccess.READ) if not path.is_empty() else null
	if file == null or file.get_length() > CharacterArtBundle.MAX_IMAGE_BYTES * 2 + 2048:
		return null
	var result := CharacterArtBundle.from_data(JSON.parse_string(file.get_as_text()))
	return result if result != null and result.assets().size() == 1 else null


func _ensure_directory() -> bool:
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_root.path_join("originals"))) == OK:
		return true
	last_error = "Could not create the character artwork library."
	return false


func _write_verified_bytes(path: String, bytes: PackedByteArray) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "Could not write imported artwork."
		return false
	file.store_buffer(bytes)
	file.flush()
	file.close()
	if FileAccess.get_file_as_bytes(temporary) != bytes or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path)) != OK:
		last_error = "Imported artwork could not be verified and installed."
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary))
		return false
	return true


static func _hash(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
