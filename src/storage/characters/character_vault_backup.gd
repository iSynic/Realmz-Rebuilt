## Makes a complete verified vault backup and restores selections after repair failure.
class_name CharacterVaultBackup
extends RefCounted

var path := ""
var last_error := ""
var complete := false


func snapshot(root: String) -> Dictionary:
	var result: Dictionary = {}
	var pending: Array[String] = [""]
	while not pending.is_empty():
		var relative: String = pending.pop_back()
		var directory := DirAccess.open(root.path_join(relative))
		if directory == null:
			last_error = "Could not read the complete Character Files folder."
			return {}
		for entry: String in directory.get_directories() + directory.get_files():
			var item := relative.path_join(entry)
			if directory.is_link(entry):
				last_error = "Character Files contains a linked file or folder; repair stopped before changing characters."
				return {}
			if directory.dir_exists(entry):
				pending.append(item)
				result[item + "/"] = "directory"
			else:
				var hash := FileAccess.get_sha256(root.path_join(item))
				if hash.is_empty():
					last_error = "Could not verify every Character File."
					return {}
				result[item] = hash
			if result.size() > 100000:
				last_error = "The Character Files folder exceeds the repair file limit."
				return {}
	return result


func create(root: String, expected: Dictionary) -> bool:
	complete = false
	if not matches(root, expected):
		return false
	var backup_root := root.get_base_dir().path_join("character-backups")
	if FileAccess.file_exists(backup_root):
		return _fail("The backup folder location is occupied by a file. No characters were changed.")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "")
	path = backup_root.path_join("repair-" + stamp)
	var suffix := 1
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		path = backup_root.path_join("repair-%s-%d" % [stamp, suffix])
		suffix += 1
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.path_join("characters"))) != OK:
		return _fail("Could not create the complete vault backup. No characters were changed.")
	for relative: String in expected:
		var destination := path.path_join("characters").path_join(relative)
		if relative.ends_with("/"):
			if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination)) != OK:
				return _fail("Could not copy every vault folder. No characters were changed.")
		else:
			if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination.get_base_dir())) != OK or DirAccess.copy_absolute(ProjectSettings.globalize_path(root.path_join(relative)), ProjectSettings.globalize_path(destination)) != OK:
				return _fail("Could not copy the complete vault. No characters were changed.")
	if not matches(path.path_join("characters"), expected) or not matches(root, expected):
		return false
	complete = true
	return true


func matches(root: String, expected: Dictionary) -> bool:
	last_error = ""
	var actual := snapshot(root)
	if not last_error.is_empty():
		return false
	return true if actual == expected else _fail("Character Files changed during preparation. Review the repair again; no further characters were changed.")


func restore_indices(root: String, identities: Array[String], original: Dictionary) -> bool:
	var restored := true
	for identity: String in identities:
		for filename: String in ["current.json", "current.json.bak"]:
			var relative := identity.path_join(filename)
			var target := root.path_join(relative)
			if original.has(relative):
				if FileAccess.get_sha256(target) == original[relative]:
					continue
				var temporary := target + ".repair-rollback-%d.tmp" % Time.get_ticks_usec()
				if FileAccess.file_exists(temporary) or DirAccess.copy_absolute(ProjectSettings.globalize_path(path.path_join("characters").path_join(relative)), ProjectSettings.globalize_path(temporary)) != OK:
					restored = false
					continue
				if FileAccess.get_sha256(temporary) != original[relative] or DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(target)) != OK:
					restored = false
			elif FileAccess.file_exists(target) and DirAccess.remove_absolute(ProjectSettings.globalize_path(target)) != OK:
				restored = false
	return restored


func _fail(message: String) -> bool:
	last_error = message
	return false
