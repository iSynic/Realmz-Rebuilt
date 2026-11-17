## Permanently removes archived Character Files folders and retires their identities, so a
## deleted character's ID never returns as a different character in saves or the party.
class_name CharacterVaultDeletion
extends RefCounted

const STAGING_PREFIX := ".deleting-"
const RETIRED_IDS_FILE := "retired-character-ids.json"
const RECORD_EXTENSION := ".r2char"
const REPAIR_FIRST := "Run Repair Character Files before deleting it."


## Deletes one archived character after checking that every file in its folder is a readable
## revision (hidden OS metadata such as .DS_Store aside). Returns "" or the reason it was kept.
static func delete(root_path: String, character_id: String, revisions: Array[CharacterVaultRecord]) -> String:
	var character_path := root_path.path_join(character_id)
	if not DirAccess.dir_exists_absolute(_global(character_path)):
		return "The character is not in Character Files."
	var readable: Dictionary = {}
	for record: CharacterVaultRecord in revisions:
		readable[record.revision_hash + RECORD_EXTENSION] = true
	var unreadable := 0
	for folder: String in [character_path, character_path.path_join("archive")]:
		var listing := _listing(folder)
		for file_name: String in listing["files"]:
			if file_name == "current.json":
				return "This character still has a current revision index. " + REPAIR_FIRST
			if not file_name.begins_with(".") and not _is_known_file(folder, file_name, readable):
				unreadable += 1
		for directory_name: String in listing["directories"]:
			if folder != character_path or directory_name != "archive":
				unreadable += 1
	if readable.is_empty():
		# Repair never migrates older formats, so this keeps the character without sending the player there.
		return "None of this character's revisions can be read in this version, so Character Files kept them. Nothing was deleted."
	if unreadable > 0:
		return "%d of this character's files can't be read, so Character Files kept them. Nothing was deleted." % unreadable
	sweep(root_path)
	# Retire first: if the rename below fails, the ID merely stays reserved and a retry still works.
	var retire_error := _retire(root_path, character_id)
	if not retire_error.is_empty():
		return retire_error
	var staging_path := root_path.path_join("%s%s-%d" % [STAGING_PREFIX, character_id, Time.get_ticks_usec()])
	var rename_error := DirAccess.rename_absolute(_global(character_path), _global(staging_path))
	if rename_error != OK:
		return "Could not delete the character (error %d)." % rename_error
	# The rename is the deletion; a cleanup interrupted here is swept on the next start.
	remove_tree(staging_path)
	return ""


## A readable revision, or a rotation backup the vault itself left beside one: the previous
## current index naming a readable revision, or an earlier copy of a readable record.
static func _is_known_file(folder: String, file_name: String, readable: Dictionary) -> bool:
	if readable.has(file_name):
		return true
	if file_name == "current.json.bak":
		var index: Variant = _parse(FileAccess.get_file_as_string(folder.path_join(file_name)))
		if not index is Dictionary:
			return false
		var fields: Dictionary = index
		return readable.has(str(fields.get("revisionHash", "")) + RECORD_EXTENSION)
	return file_name.ends_with(RECORD_EXTENSION + ".bak") and readable.has(file_name.trim_suffix(".bak"))


## Why new identities can't be allocated safely, or "" when the deleted-character list is readable.
static func ledger_error(root_path: String) -> String:
	var path := root_path.path_join(RETIRED_IDS_FILE)
	if FileAccess.file_exists(path) and _read_ids(path) == null:
		return "Character Files can't read its list of deleted characters (%s). Restore it from a backup before creating characters." % RETIRED_IDS_FILE
	return ""


## Identities that belonged to deleted characters, from the ledger and its rotation backup;
## allocation never hands them out again.
static func retired_ids(root_path: String) -> Array[String]:
	var result: Array[String] = []
	var path := root_path.path_join(RETIRED_IDS_FILE)
	for candidate: String in [path, path + ".bak", path + ".bak.rotation"]:
		var ids: Variant = _read_ids(candidate)
		if ids is Array:
			for character_id: String in ids:
				if character_id not in result:
					result.append(character_id)
	return result


## Finishes deletions whose cleanup was interrupted. Staging names are dot-prefixed, so the
## listing must include hidden entries on Linux, macOS and Android.
static func sweep(root_path: String) -> void:
	for directory_name: String in _listing(root_path)["directories"]:
		if String(directory_name).begins_with(STAGING_PREFIX):
			remove_tree(root_path.path_join(directory_name))


static func remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(_global(path)):
		return true
	var listing := _listing(path)
	for directory_name: String in listing["directories"]:
		if not remove_tree(path.path_join(directory_name)):
			return false
	for file_name: String in listing["files"]:
		if DirAccess.remove_absolute(_global(path.path_join(file_name))) != OK:
			return false
	return DirAccess.remove_absolute(_global(path)) == OK


## Records a deleted identity through a verified temporary file and backup rotation, so an
## interrupted write can never shorten the ledger. Returns "" or why nothing was deleted.
static func _retire(root_path: String, character_id: String) -> String:
	var path := root_path.path_join(RETIRED_IDS_FILE)
	if not ledger_error(root_path).is_empty():
		return "Character Files can't read its list of deleted characters (%s), so nothing was deleted." % RETIRED_IDS_FILE
	var retired := retired_ids(root_path)
	if character_id in retired:
		return ""
	retired.append(character_id)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not record the deleted character. Nothing was deleted."
	file.store_string(JSON.stringify(retired))
	file.flush()
	file.close()
	var written: Variant = _read_ids(temporary)
	if not (written is Array and character_id in written):
		DirAccess.remove_absolute(_global(temporary))
		return "Could not verify the deleted-character record. Nothing was deleted."
	var rotation_error := BackupRotation.replace(temporary, path, path + ".bak")
	return "" if rotation_error.is_empty() else "Could not record the deleted character. Nothing was deleted. " + rotation_error


## A strict list of identity strings, or null when the file is missing or unreadable.
static func _read_ids(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var value: Variant = _parse(FileAccess.get_file_as_string(path))
	if not value is Array:
		return null
	var result: Array[String] = []
	for item: Variant in value:
		if not item is String:
			return null
		result.append(item)
	return result


## Damaged files are an expected input here, so parsing reports through the result, not the log.
static func _parse(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func _listing(path: String) -> Dictionary:
	# Arrays (not packed arrays) so appending through the dictionary mutates the stored list.
	var result := {"files": [], "directories": []}
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	directory.include_hidden = true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var bucket: Array = result["directories"] if directory.current_is_dir() else result["files"]
		bucket.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


static func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)
