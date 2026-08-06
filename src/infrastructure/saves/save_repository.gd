class_name SaveRepository
extends RefCounted

var _root_path: String
var last_error: String = ""


func _init(root_path: String = "user://saves") -> void:
	_root_path = root_path.trim_suffix("/")


func save(campaign_id: String, slot_id: String, envelope: SaveEnvelope) -> bool:
	last_error = ""
	if envelope == null or envelope.campaign_id != campaign_id:
		return _fail("Save envelope does not match the requested campaign.")
	if not _safe_component(campaign_id) or not _safe_component(slot_id):
		return _fail("Campaign and slot IDs must be portable path components.")
	var campaign_path := "%s/%s" % [_root_path, campaign_id]
	var create_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(campaign_path))
	if create_error != OK:
		return _fail("Could not create the campaign save directory (error %d)." % create_error)
	var slot_path := "%s/%s.r2save" % [campaign_path, slot_id]
	var temp_path := slot_path + ".tmp"
	var backup_path := slot_path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not open the temporary save file.")
	file.store_string(JSON.stringify(envelope.to_data()))
	file.flush()
	file.close()
	var verified := _read_envelope(temp_path)
	if verified == null or verified.campaign_id != envelope.campaign_id or verified.package_hash != envelope.package_hash:
		_delete_file(temp_path)
		return _fail("Temporary save verification failed.")
	if FileAccess.file_exists(backup_path) and not _delete_file(backup_path):
		_delete_file(temp_path)
		return _fail("Could not rotate the previous save backup.")
	var absolute_slot := ProjectSettings.globalize_path(slot_path)
	var absolute_backup := ProjectSettings.globalize_path(backup_path)
	var absolute_temp := ProjectSettings.globalize_path(temp_path)
	if FileAccess.file_exists(slot_path):
		var backup_error := DirAccess.rename_absolute(absolute_slot, absolute_backup)
		if backup_error != OK:
			_delete_file(temp_path)
			return _fail("Could not move the current save to its backup (error %d)." % backup_error)
	var replace_error := DirAccess.rename_absolute(absolute_temp, absolute_slot)
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(absolute_backup, absolute_slot)
		_delete_file(temp_path)
		return _fail("Could not atomically install the verified save (error %d)." % replace_error)
	return true


func load(campaign_id: String, slot_id: String, expected_package_hash: String) -> SaveEnvelope:
	last_error = ""
	if not _safe_component(campaign_id) or not _safe_component(slot_id):
		_fail("Campaign and slot IDs must be portable path components.")
		return null
	var envelope := _read_envelope("%s/%s/%s.r2save" % [_root_path, campaign_id, slot_id])
	if envelope == null:
		_fail("Save file is missing, corrupt, or uses an unsupported schema.")
		return null
	if envelope.campaign_id != campaign_id or envelope.package_hash != expected_package_hash:
		_fail("Save package identity does not match the installed campaign.")
		return null
	return envelope


func _read_envelope(path: String) -> SaveEnvelope:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	file.close()
	if parse_error != OK:
		return null
	return SaveEnvelope.from_data(parser.data)


func _delete_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _safe_component(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		var valid := (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code == 45 or code == 95
		if not valid:
			return false
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false
