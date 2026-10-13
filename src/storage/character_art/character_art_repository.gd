## Owns the player's managed artwork without changing compiled scenario content.
class_name CharacterArtRepository
extends RefCounted

var _root: String
var last_error := ""
var _library: CharacterArtLibraryIndex
var _stock_groups := PackedStringArray()


func _init(root: String = "user://character-art") -> void:
	_root = root.trim_suffix("/")


func set_stock_groups(names: PackedStringArray) -> void:
	_stock_groups = names.duplicate()


func groups() -> Array[Dictionary]:
	var index := _index()
	var result: Array[Dictionary] = []
	var names := _stock_groups.duplicate()
	if index != null:
		for name: String in index.group_names():
			if _matching_name(names, name).is_empty():
				names.append(name)
	names.sort()
	for name: String in names:
		result.append({"name": name, "builtin": not _matching_name(_stock_groups, name).is_empty()})
	return result


func entries() -> Array[Dictionary]:
	var index := _index()
	var result := index.entries() if index != null else [] as Array[Dictionary]
	for entry: Dictionary in result:
		var stock := _matching_name(_stock_groups, entry.group)
		if not stock.is_empty():
			entry.group = stock
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return (a.group + a.kind + a.label + a.id).naturalnocasecmp_to(b.group + b.kind + b.label + b.id) < 0)
	return result


func appearance_options() -> Array[CharacterAppearanceOptionView]:
	var result: Array[CharacterAppearanceOptionView] = []
	for entry: Dictionary in entries():
		var option := CharacterAppearanceOptionView.new(CharacterAppearanceDefinition.new(entry.id, entry.label, StringName(entry.kind), 0))
		option.art_group = entry.group
		result.append(option)
	return result


func create_group(name: String) -> bool:
	name = name.strip_edges()
	if not _available_name(name):
		return false
	return _index_result(_library.add_group(name))


func rename_group(name: String, replacement: String) -> bool:
	replacement = replacement.strip_edges()
	if not _editable_group(name):
		return false
	if name.nocasecmp_to(replacement) != 0 and not _available_name(replacement):
		return false
	return _index_result(_library.rename_group(_stored_group(name), replacement))


func remove_group(name: String) -> bool:
	return _editable_group(name) and _index_result(_library.remove_group(_stored_group(name)))


func rename_image(group: String, id: String, label: String) -> bool:
	if _index() == null:
		return false
	return _index_result(_library.rename_image(_stored_group(group), id, label.strip_edges()))


func remove_images(group: String, ids: PackedStringArray) -> bool:
	if _index() == null:
		return false
	return _index_result(_library.remove_images(_stored_group(group), ids))


func import_batch(batch: CharacterArtImportBatch, group: String) -> bool:
	last_error = ""
	if batch == null or batch.ready_count() == 0 or _index() == null:
		return false
	var canonical := _stored_group(group)
	if not _library.group_names().has(canonical) and _matching_name(_stock_groups, canonical).is_empty():
		last_error = "Choose an existing artwork race before importing."
		return false
	if not _index_result(_library.add_entries([])) or not _ensure_directory():
		return false
	var bundle := CharacterArtBundle.new()
	for item: Dictionary in batch.items:
		if item.id.is_empty() or not item.error.is_empty():
			continue
		if not bundle.add(item.id, canonical, item.label, batch.kind, item.png):
			last_error = "An import preview failed validation. Nothing was added to the library."
			return false
		var source := item.source as CharacterArtImage
		var original := _root.path_join("originals").path_join(_hash(source.source_bytes) + "." + source.source_extension)
		if not FileAccess.file_exists(original) and not _write_verified_bytes(original, source.source_bytes):
			return false
	if not _store_bundle(bundle):
		return false
	return _index_result(_library.add_entries(bundle.entries()))


func media() -> CharacterArtBundle:
	var result := CharacterArtBundle.new()
	var directory := DirAccess.open(_root)
	if directory == null:
		return result
	for filename: String in directory.get_files():
		if not filename.ends_with(".json") or filename == "library.json":
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
		for current: Dictionary in entries():
			if current.id == id:
				metadata = current
				break
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
	if _index() == null or not _index_result(_library.add_entries([])):
		return false
	var fresh: Array[Dictionary] = []
	for entry: Dictionary in bundle.entries():
		if not FileAccess.file_exists(_entry_path(entry.id)):
			entry.group = _stored_group(entry.group)
			fresh.append(entry)
	if not _store_bundle(bundle):
		return false
	# Existing payloads keep renamed or removed membership when saves/vaults reinstall them.
	return _index_result(_library.add_entries(fresh))


func _store_bundle(bundle: CharacterArtBundle) -> bool:
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


func _index() -> CharacterArtLibraryIndex:
	if _library != null:
		return _library
	var candidate := CharacterArtLibraryIndex.new(_root.path_join("library.json"))
	if not candidate.load_entries(media().entries()):
		last_error = candidate.last_error
		return null
	_library = candidate
	return _library


func _index_result(success: bool) -> bool:
	last_error = _library.last_error
	return success


func _available_name(name: String) -> bool:
	if _index() == null:
		return false
	if not CharacterArtLibraryIndex.valid_name(name):
		last_error = "Enter an artwork race name of 1–128 characters."
		return false
	var names := _stock_groups + _library.group_names()
	if not _matching_name(names, name).is_empty():
		last_error = "An artwork race with that name already exists."
		return false
	return true


func _editable_group(name: String) -> bool:
	if _index() == null:
		return false
	if not _matching_name(_stock_groups, name).is_empty():
		last_error = "Built-in artwork race names cannot be renamed or removed."
		return false
	return true


func _stored_group(name: String) -> String:
	var existing := _matching_name(_library.group_names(), name)
	if not existing.is_empty():
		return existing
	var stock := _matching_name(_stock_groups, name)
	return stock if not stock.is_empty() else name


static func _matching_name(names: PackedStringArray, name: String) -> String:
	for candidate: String in names:
		if candidate.nocasecmp_to(name) == 0:
			return candidate
	return ""


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
