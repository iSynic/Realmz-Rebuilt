## Installs verified storage files while retaining one backup and recovering interrupted rotations.

class_name BackupRotation
extends RefCounted

const _INCOMPLETE_ROLLBACK := " The previous file is preserved beside it and is recovered by the next write."


## Moves `temporary` into `primary`, keeping the previous primary as `backup`.
## Returns an empty string on success, otherwise a storage-safe error message.
static func replace(temporary: String, primary: String, backup: String, retain_backup: bool = true) -> String:
	var staged_backup := backup + ".rotation"
	var recovery_error := recover(primary, backup)
	if not recovery_error.is_empty():
		_delete(temporary)
		return recovery_error
	var staged_previous_backup := false
	if FileAccess.file_exists(backup):
		var stage_error := _rename(backup, staged_backup)
		if stage_error != OK:
			_delete(temporary)
			return "Could not preserve the previous backup (error %d)." % stage_error
		staged_previous_backup = true
	var moved_primary := false
	if FileAccess.file_exists(primary):
		var backup_error := _rename(primary, backup)
		if backup_error != OK:
			var restored := not staged_previous_backup or _rename(staged_backup, backup) == OK
			_delete(temporary)
			return "Could not move the current file to its backup (error %d).%s" % [backup_error, "" if restored else _INCOMPLETE_ROLLBACK]
		moved_primary = true
	var install_error := _rename(temporary, primary)
	if install_error != OK:
		var restored := not moved_primary or _rename(backup, primary) == OK
		if restored and staged_previous_backup:
			restored = _rename(staged_backup, backup) == OK
		_delete(temporary)
		return "Could not install the verified file (error %d).%s" % [install_error, "" if restored else _INCOMPLETE_ROLLBACK]
	if not retain_backup:
		_delete(backup)
	if staged_previous_backup:
		_delete(staged_backup)
	return ""


## Settles a rotation interrupted between renames. Each interruption point
## leaves a distinct primary/backup/staged layout, so recovery is unambiguous.
static func recover(primary: String, backup: String) -> String:
	var staged_backup := backup + ".rotation"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(staged_backup)):
		return "A prior backup rotation is a directory; refusing to overwrite it."
	if not FileAccess.file_exists(staged_backup):
		return ""
	if FileAccess.file_exists(primary) and FileAccess.file_exists(backup):
		# The replacement was installed; the staged file is the superseded backup.
		return "" if _delete(staged_backup) else "Could not remove a superseded backup rotation."
	if FileAccess.file_exists(backup) and _rename(backup, primary) != OK:
		return "Could not restore an interrupted file from its backup."
	if _rename(staged_backup, backup) != OK:
		return "Could not restore the previous backup from an interrupted rotation."
	return ""


static func _rename(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))


static func _delete(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK
