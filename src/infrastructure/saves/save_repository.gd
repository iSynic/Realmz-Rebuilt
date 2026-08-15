class_name SaveRepository
extends RefCounted

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")

var _root_path: String
var last_error: String = ""


func _init(root_path: String = "user://saves") -> void:
	_root_path = root_path.trim_suffix("/")


func save(campaign_id: String, slot_id: String, snapshot: SessionSnapshot) -> bool:
	last_error = ""
	if snapshot == null or snapshot.campaign_id != campaign_id:
		return _fail("Save envelope does not match the requested campaign.")
	var envelope := SaveEnvelope.from_snapshot(snapshot)
	if envelope == null:
		return _fail("The session snapshot could not be encoded.")
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
	return _load_path(campaign_id, slot_id, expected_package_hash, false)


func load_backup(campaign_id: String, slot_id: String, expected_package_hash: String) -> SaveEnvelope:
	return _load_path(campaign_id, slot_id, expected_package_hash, true)


func list_previews(campaign_id: String, expected_package_hash: String) -> Array:
	last_error = ""
	var previews: Array = []
	if not _safe_component(campaign_id):
		_fail("Campaign ID must be a portable path component.")
		return previews
	var campaign_path := "%s/%s" % [_root_path, campaign_id]
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(campaign_path)):
		return previews
	for file_name: String in DirAccess.get_files_at(campaign_path):
		var source: StringName = SaveSlotPreviewScript.PRIMARY
		var slot_id := ""
		if file_name.ends_with(".r2save.bak"):
			source = SaveSlotPreviewScript.BACKUP
			slot_id = file_name.trim_suffix(".r2save.bak")
		elif file_name.ends_with(".r2save"):
			slot_id = file_name.trim_suffix(".r2save")
		else:
			continue
		if not _safe_component(slot_id):
			continue
		previews.append(_preview_for_path(campaign_path.path_join(file_name), slot_id, source, campaign_id, expected_package_hash))
	previews.sort_custom(func(left: RefCounted, right: RefCounted) -> bool:
		if left.slot_id != right.slot_id:
			return left.slot_id.naturalnocasecmp_to(right.slot_id) < 0
		return left.source == SaveSlotPreviewScript.PRIMARY and right.source == SaveSlotPreviewScript.BACKUP
	)
	return previews


func _load_path(campaign_id: String, slot_id: String, expected_package_hash: String, backup: bool) -> SaveEnvelope:
	last_error = ""
	if not _safe_component(campaign_id) or not _safe_component(slot_id):
		_fail("Campaign and slot IDs must be portable path components.")
		return null
	var suffix := ".r2save.bak" if backup else ".r2save"
	var path := "%s/%s/%s%s" % [_root_path, campaign_id, slot_id, suffix]
	var envelope := _read_envelope(path)
	if envelope == null:
		var incompatibility := _incompatible_schema_message(path)
		_fail(incompatibility if not incompatibility.is_empty() else ("Save backup is missing or corrupt." if backup else "Save file is missing or corrupt."))
		return null
	if envelope.campaign_id != campaign_id or envelope.package_hash != expected_package_hash:
		_fail("Save package identity does not match the installed campaign.")
		return null
	return envelope


func _preview_for_path(path: String, slot_id: String, source: StringName, expected_campaign_id: String, expected_package_hash: String) -> RefCounted:
	var envelope := _read_envelope(path)
	if envelope == null:
		var incompatibility := _incompatible_schema_message(path)
		var corrupt := SaveSlotPreviewScript.new(slot_id, source, SaveSlotPreviewScript.INCOMPATIBLE if not incompatibility.is_empty() else SaveSlotPreviewScript.CORRUPT)
		corrupt.modified_unix = int(FileAccess.get_modified_time(path))
		corrupt.error_message = incompatibility if not incompatibility.is_empty() else "This save is corrupt."
		return corrupt
	var status: StringName = SaveSlotPreviewScript.VALID
	var error_message := ""
	if envelope.campaign_id != expected_campaign_id:
		status = SaveSlotPreviewScript.CAMPAIGN_MISMATCH
		error_message = "This save belongs to campaign '%s'." % envelope.campaign_id
	elif envelope.package_hash != expected_package_hash:
		status = SaveSlotPreviewScript.PACKAGE_MISMATCH
		error_message = "This save was created for a different immutable package revision."
	var preview := SaveSlotPreviewScript.new(slot_id, source, status)
	preview.campaign_id = envelope.campaign_id
	preview.package_hash = envelope.package_hash
	preview.rules_version = envelope.rules_version
	preview.view_revision = envelope.view_revision
	preview.modified_unix = int(FileAccess.get_modified_time(path))
	preview.realmz_day = envelope.game_state.clock.day()
	preview.realmz_hour = envelope.game_state.clock.hour()
	preview.realmz_minute = envelope.game_state.clock.minute()
	preview.map_id = envelope.game_state.party.map_id
	preview.coordinate = envelope.game_state.party.coordinate
	for character: CharacterState in envelope.game_state.party.characters():
		preview.character_names.append(character.name)
	preview.error_message = error_message
	preview.can_load = status == SaveSlotPreviewScript.VALID
	return preview


func _read_envelope(path: String) -> SaveEnvelope:
	var data: Variant = _read_document(path)
	return SaveEnvelope.from_data(data) if data != null else null


func _read_document(path: String) -> Variant:
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
	return parser.data


func _incompatible_schema_message(path: String) -> String:
	var data: Variant = _read_document(path)
	if not data is Dictionary or data.get("format") != SaveEnvelope.FORMAT:
		return ""
	var version: Variant = data.get("formatVersion")
	if version is float and is_equal_approx(version, round(version)):
		version = int(version)
	if not version is int or version == SaveEnvelope.FORMAT_VERSION:
		return ""
	return "Save format v%d is incompatible with Realmz Rebuilt save v%d." % [version, SaveEnvelope.FORMAT_VERSION]


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
