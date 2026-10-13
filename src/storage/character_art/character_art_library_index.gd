## Keeps mutable picker membership separate from immutable, portable image payloads.
class_name CharacterArtLibraryIndex
extends RefCounted

const MAX_BYTES := 4 * 1024 * 1024
const MAX_GROUPS := 256
const MAX_IMAGES := 8192

var last_error := ""
var _path: String
var _groups: Dictionary = {}


func _init(path: String) -> void:
	_path = path


func load_entries(legacy: Array[Dictionary]) -> bool:
	last_error = ""
	if not FileAccess.file_exists(_path):
		var names: Dictionary = {}
		for entry: Dictionary in legacy:
			var group := str(entry.group).strip_edges()
			group = names.get(group.to_lower(), group)
			names[group.to_lower()] = group
			if not _groups.has(group):
				_groups[group] = {}
			_groups[group][entry.id] = entry.label
		return true
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return _fail("The artwork library index could not be read.")
	var data: Variant = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or data.size() != 2 or data.get("version") != 1 or not _valid_groups(data.get("groups")):
		return _fail("The artwork library index is invalid. Existing images have been preserved.")
	_groups = data.groups.duplicate(true)
	return true


func group_names() -> PackedStringArray:
	return PackedStringArray(_groups.keys())


func entries() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for group: String in _groups:
		for id: String in _groups[group]:
			result.append({"id": id, "group": group, "label": _groups[group][id], "kind": "portrait" if CharacterArtIdentity.is_valid(id, "portrait") else "combat-icon"})
	return result


func add_group(name: String) -> bool:
	var next := _groups.duplicate(true)
	if next.has(name):
		return _fail("An artwork race with that name already exists.")
	next[name] = {}
	return _commit(next)


func rename_group(name: String, replacement: String) -> bool:
	if not _groups.has(name):
		return _fail("That artwork race is no longer available.")
	var next := _groups.duplicate(true)
	var images: Dictionary = next[name]
	next.erase(name)
	if next.has(replacement):
		return _fail("An artwork race with that name already exists.")
	next[replacement] = images
	return _commit(next)


func remove_group(name: String) -> bool:
	if not _groups.has(name):
		return _fail("That artwork race is no longer available.")
	var next := _groups.duplicate(true)
	next.erase(name)
	return _commit(next)


func add_entries(entries_to_add: Array[Dictionary]) -> bool:
	var next := _groups.duplicate(true)
	for entry: Dictionary in entries_to_add:
		if not next.has(entry.group):
			next[entry.group] = {}
		# Reimport restores removed membership without replacing a player's renamed label.
		if not next[entry.group].has(entry.id):
			next[entry.group][entry.id] = entry.label
	return _commit(next)


func rename_image(group: String, id: String, label: String) -> bool:
	if not _groups.has(group) or not _groups[group].has(id):
		return _fail("That imported image is no longer in this artwork race.")
	var next := _groups.duplicate(true)
	next[group][id] = label
	return _commit(next)


func remove_images(group: String, ids: PackedStringArray) -> bool:
	if ids.is_empty() or not _groups.has(group):
		return _fail("Select imported images to remove.")
	var next := _groups.duplicate(true)
	for id: String in ids:
		if not next[group].has(id):
			return _fail("Only imported images in the selected artwork race can be removed.")
		next[group].erase(id)
	return _commit(next)


func _commit(groups: Dictionary) -> bool:
	last_error = ""
	if groups == _groups and FileAccess.file_exists(_path):
		return true
	if not _valid_groups(groups):
		return _fail("Artwork names must contain 1–128 characters; the library supports 256 races and 8,192 images.")
	var bytes := JSON.stringify({"version": 1, "groups": groups}, "", true, true).to_utf8_buffer()
	var path := ProjectSettings.globalize_path(_path)
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return _fail("Could not create the artwork library directory.")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("Could not write the artwork library index.")
	file.store_buffer(bytes)
	file.flush()
	file.close()
	if FileAccess.get_file_as_bytes(temporary) != bytes:
		return _fail("Artwork library readback failed; no library choices changed.")
	var had_previous := FileAccess.file_exists(path)
	if had_previous and DirAccess.copy_absolute(path, path + ".bak") != OK:
		return _fail("Could not preserve the previous artwork library index.")
	if DirAccess.rename_absolute(temporary, path) != OK:
		return _fail("Could not install the artwork library index; no library choices changed.")
	_groups = groups
	return true


static func valid_name(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty() and value == value.strip_edges() and value.length() <= 128 and not "\n" in value and not "\r" in value


static func _valid_groups(value: Variant) -> bool:
	if not value is Dictionary or value.size() > MAX_GROUPS:
		return false
	var names: Dictionary = {}
	var count := 0
	for group: Variant in value:
		if not valid_name(group) or names.has(group.to_lower()) or not value[group] is Dictionary:
			return false
		names[group.to_lower()] = true
		for id: Variant in value[group]:
			if not id is String or (not CharacterArtIdentity.is_valid(id, "portrait") and not CharacterArtIdentity.is_valid(id, "combat-icon")) or not valid_name(value[group][id]):
				return false
			count += 1
	return count <= MAX_IMAGES


func _fail(message: String) -> bool:
	last_error = message
	return false
