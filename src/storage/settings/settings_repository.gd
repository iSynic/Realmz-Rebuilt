class_name SettingsRepository
extends RefCounted

var settings_path: String
var last_error: String = ""


func _init(path: String = "user://settings.json") -> void:
	settings_path = path


func load_settings() -> PresentationSettings:
	last_error = ""
	if not FileAccess.file_exists(settings_path):
		return PresentationSettings.new()
	var text := FileAccess.get_file_as_string(settings_path)
	var parsed: Variant = JSON.parse_string(text)
	var settings := PresentationSettings.from_data(parsed)
	if settings == null:
		last_error = "Presentation settings are malformed; defaults were restored."
		return PresentationSettings.new()
	return settings


func save_settings(settings: PresentationSettings) -> bool:
	last_error = ""
	if settings == null:
		last_error = "Presentation settings are missing."
		return false
	var directory := settings_path.get_base_dir()
	if not directory.is_empty() and DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) != OK:
		last_error = "Could not create the presentation settings directory."
		return false
	var temporary_path := settings_path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_error = "Could not open the temporary presentation settings file."
		return false
	file.store_string(CanonicalJson.encode(settings.to_data()))
	file.flush()
	file.close()
	var readback := PresentationSettings.from_data(JSON.parse_string(FileAccess.get_file_as_string(temporary_path)))
	if readback == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		last_error = "Presentation settings failed readback validation."
		return false
	if FileAccess.file_exists(settings_path) and DirAccess.remove_absolute(ProjectSettings.globalize_path(settings_path)) != OK:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
		last_error = "Could not replace the previous presentation settings."
		return false
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(settings_path)) != OK:
		last_error = "Could not commit presentation settings."
		return false
	return true
