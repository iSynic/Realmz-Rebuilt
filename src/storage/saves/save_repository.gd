## Persists and validates save repository data at the save boundary.

class_name SaveRepository
extends RefCounted


var _root_path: String
var last_error: String = ""

const CLASSIC_SLOTS := SaveSlotPreview.SCENARIO_SLOTS
const MAX_PARTY_SOURCE_BYTES: int = 512 * 1024 * 1024
const INTERNAL_SOURCE_PREFIX: String = "save://"
const EXTERNAL_SOURCE_PREFIX: String = "external://"


func _init(root_path: String = "user://saves") -> void:
	_root_path = root_path.trim_suffix("/")


func active_slot(campaign_id: String) -> String:
	if not _safe_component(campaign_id):
		return "A"
	var path := "%s/%s/active-slot" % [_root_path, campaign_id]
	for candidate: String in [path, path + ".bak"]:
		if not FileAccess.file_exists(candidate):
			continue
		var file := FileAccess.open(candidate, FileAccess.READ)
		if file == null:
			continue
		var value := file.get_as_text().strip_edges()
		if value.length() == 1 and CLASSIC_SLOTS.contains(value):
			return value
	return "A"


func set_active_slot(campaign_id: String, slot_id: String) -> bool:
	if not _safe_component(campaign_id) or slot_id.length() != 1 or not CLASSIC_SLOTS.contains(slot_id):
		return _fail("The active save slot must be A–J.")
	var folder := "%s/%s" % [_root_path, campaign_id]
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder)) != OK:
		return _fail("Could not create the campaign save directory.")
	var path := folder.path_join("active-slot")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _fail("Could not write the active save slot.")
	file.store_string(slot_id)
	file.flush()
	file.close()
	var backup := path + ".bak"
	var replace_error := _replace_with_backup(temporary, path, backup, false)
	if not replace_error.is_empty():
		return _fail("Could not install the active save slot: %s" % replace_error)
	return true


func save(campaign_id: String, slot_id: String, snapshot: SessionSnapshot, preview_jpeg: PackedByteArray = PackedByteArray()) -> bool:
	last_error = ""
	if snapshot == null or snapshot.campaign_id != campaign_id:
		return _fail("Save envelope does not match the requested campaign.")
	if not preview_jpeg.is_empty() and not SaveEnvelope.valid_map_preview(preview_jpeg):
		return _fail("The map preview must be a 320×320 JPEG under 256 KiB.")
	var envelope := SaveEnvelope.from_snapshot(snapshot, preview_jpeg)
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
	file.store_string(JSON.stringify(envelope.to_data(), "", true, true))
	file.flush()
	file.close()
	var verified := _read_envelope(temp_path)
	if verified == null or verified.campaign_id != envelope.campaign_id or verified.package_hash != envelope.package_hash:
		_delete_file(temp_path)
		return _fail("Temporary save verification failed.")
	var replace_error := _replace_with_backup(temp_path, slot_path, backup_path)
	if not replace_error.is_empty():
		return _fail("Could not atomically install the verified save: %s" % replace_error)
	return true


func _replace_with_backup(temporary: String, primary: String, backup: String, retain_backup: bool = true) -> String:
	var staged_backup := backup + ".rotation"
	if FileAccess.file_exists(staged_backup) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(staged_backup)):
		_delete_file(temporary)
		return "A prior backup rotation is still present; refusing to overwrite it."
	var staged_previous_backup := false
	if FileAccess.file_exists(backup):
		var stage_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(staged_backup))
		if stage_error != OK:
			_delete_file(temporary)
			return "Could not preserve the previous backup (error %d)." % stage_error
		staged_previous_backup = true
	var moved_primary := false
	if FileAccess.file_exists(primary):
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(primary), ProjectSettings.globalize_path(backup))
		if backup_error != OK:
			if staged_previous_backup:
				DirAccess.rename_absolute(ProjectSettings.globalize_path(staged_backup), ProjectSettings.globalize_path(backup))
			_delete_file(temporary)
			return "Could not move the current file to its backup (error %d)." % backup_error
		moved_primary = true
	var install_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(primary))
	if install_error != OK:
		if moved_primary:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup), ProjectSettings.globalize_path(primary))
		if staged_previous_backup:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(staged_backup), ProjectSettings.globalize_path(backup))
		_delete_file(temporary)
		return "Could not install the verified file (error %d)." % install_error
	if not retain_backup:
		_delete_file(backup)
	if staged_previous_backup:
		_delete_file(staged_backup)
	return ""


func load(campaign_id: String, slot_id: String, expected_package_hash: String) -> SaveEnvelope:
	return _load_path(campaign_id, slot_id, expected_package_hash, false)


func load_backup(campaign_id: String, slot_id: String, expected_package_hash: String) -> SaveEnvelope:
	return _load_path(campaign_id, slot_id, expected_package_hash, true)


func first_empty_slot(campaign_id: String) -> String:
	if not _safe_component(campaign_id):
		return ""
	for index: int in CLASSIC_SLOTS.length():
		var slot := CLASSIC_SLOTS.substr(index, 1)
		var path := "%s/%s/%s.r2save" % [_root_path, campaign_id, slot]
		if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".bak") and not DirAccess.dir_exists_absolute(path) and not DirAccess.dir_exists_absolute(path + ".bak"):
			return slot
	return ""


func copy_to_scenario_slot(campaign_id: String, envelope: SaveEnvelope, replacement_slot: String = "") -> String:
	last_error = ""
	if envelope == null or envelope.campaign_id != campaign_id:
		_fail("A validated save for this campaign is required.")
		return ""
	var target := first_empty_slot(campaign_id) if replacement_slot.is_empty() else replacement_slot
	if target.length() != 1 or not CLASSIC_SLOTS.contains(target):
		_fail("No empty scenario slot. Choose an A–J slot in Save & Load and confirm replacement.")
		return ""
	var copied := save_new_copy(campaign_id, target, envelope) if replacement_slot.is_empty() else save(campaign_id, target, envelope, envelope.map_preview_jpeg)
	if not copied:
		return ""
	var readback := self.load(campaign_id, target, envelope.package_hash)
	if readback == null or readback.to_data() != envelope.to_data():
		_fail("Copied save failed readback. Loading was stopped; the earlier save is unchanged.")
		return ""
	return target


func read_for_explicit_update(campaign_id: String, slot_id: String, old_package_hash: String, backup: bool) -> SaveEnvelope:
	return _load_path(campaign_id, slot_id, old_package_hash, backup)


func save_new_copy(campaign_id: String, slot_id: String, envelope: SaveEnvelope) -> bool:
	last_error = ""
	if envelope == null or envelope.campaign_id != campaign_id or not _safe_component(campaign_id) or not _safe_component(slot_id):
		return _fail("The updated save has an invalid campaign or slot identity.")
	var path := "%s/%s/%s.r2save" % [_root_path, campaign_id, slot_id]
	if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
		var existing := _read_envelope(path)
		if existing != null and existing.to_data() == envelope.to_data():
			return true
		return _fail("The updated save slot already contains different data; no save was replaced.")
	if not save(campaign_id, slot_id, envelope, envelope.map_preview_jpeg):
		return false
	var verified := self.load(campaign_id, slot_id, envelope.package_hash)
	if verified == null or verified.to_data() != envelope.to_data():
		_delete_file(path)
		return _fail("Updated save readback failed; no copied save was kept.")
	return true


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
		var source: StringName = SaveSlotPreview.PRIMARY
		var slot_id := ""
		if file_name.ends_with(".r2save.bak"):
			source = SaveSlotPreview.BACKUP
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
		return left.source == SaveSlotPreview.PRIMARY and right.source == SaveSlotPreview.BACKUP
	)
	return previews


func list_party_sources() -> Array[SavePartySource]:
	var sources: Array[SavePartySource] = []
	var root_absolute := ProjectSettings.globalize_path(_root_path)
	if not DirAccess.dir_exists_absolute(root_absolute):
		return sources
	for campaign_id: String in DirAccess.get_directories_at(root_absolute):
		if not _safe_component(campaign_id):
			continue
		var campaign_path := _root_path.path_join(campaign_id)
		var campaign_absolute := ProjectSettings.globalize_path(campaign_path)
		for file_name: String in DirAccess.get_files_at(campaign_absolute):
			var source_kind: StringName = &""
			var slot_id := ""
			if file_name.ends_with(".r2save.bak"):
				source_kind = &"backup"
				slot_id = file_name.trim_suffix(".r2save.bak")
			elif file_name.ends_with(".r2save"):
				source_kind = &"primary"
				slot_id = file_name.trim_suffix(".r2save")
			else:
				continue
			if not _safe_component(slot_id):
				continue
			var selector := INTERNAL_SOURCE_PREFIX + campaign_id + "/" + file_name
			sources.append(_read_party_source_path(campaign_path.path_join(file_name), selector, slot_id, source_kind, campaign_id))
	sources.sort_custom(func(left: SavePartySource, right: SavePartySource) -> bool:
		if left.campaign_id != right.campaign_id:
			return left.campaign_id.naturalnocasecmp_to(right.campaign_id) < 0
		if left.slot_id != right.slot_id:
			return left.slot_id.naturalnocasecmp_to(right.slot_id) < 0
		return left.source_kind == &"primary" and right.source_kind == &"backup"
	)
	return sources


func read_party_source(source: SavePartySource) -> SavePartySource:
	if source == null or source._storage_selector.is_empty():
		return _party_source_error("This save source is unavailable.")
	if source._storage_selector.begins_with(INTERNAL_SOURCE_PREFIX):
		var relative := source._storage_selector.trim_prefix(INTERNAL_SOURCE_PREFIX)
		var parts := relative.split("/", false)
		if parts.size() != 2 or not _safe_component(parts[0]):
			return _party_source_error("This save source selector is invalid.")
		var file_name: String = parts[1]
		var kind: StringName = &""
		var slot_id := ""
		if file_name.ends_with(".r2save.bak"):
			kind = &"backup"
			slot_id = file_name.trim_suffix(".r2save.bak")
		elif file_name.ends_with(".r2save"):
			kind = &"primary"
			slot_id = file_name.trim_suffix(".r2save")
		if not _safe_component(slot_id):
			return _party_source_error("This save source selector is invalid.")
		return _read_party_source_path(_root_path.path_join(parts[0]).path_join(file_name), source._storage_selector, slot_id, kind, parts[0])
	if source._storage_selector.begins_with(EXTERNAL_SOURCE_PREFIX):
		var path := source._storage_selector.trim_prefix(EXTERNAL_SOURCE_PREFIX)
		return _read_party_source_path(path, source._storage_selector, source.slot_id, &"external")
	return _party_source_error("This save source selector is invalid.")


func read_external_party_source(path: String) -> SavePartySource:
	if path.is_empty():
		return _party_source_error("Choose a save file to read.")
	var absolute_path := ProjectSettings.globalize_path(path)
	var file_name := path.get_file()
	var slot_id := file_name.trim_suffix(".r2save.bak").trim_suffix(".r2save")
	var selector := EXTERNAL_SOURCE_PREFIX + absolute_path
	return _read_party_source_path(path, selector, slot_id, &"external")


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
		var corrupt := SaveSlotPreview.new(slot_id, source, SaveSlotPreview.INCOMPATIBLE if not incompatibility.is_empty() else SaveSlotPreview.CORRUPT)
		corrupt.modified_unix = int(FileAccess.get_modified_time(path))
		corrupt.error_message = incompatibility if not incompatibility.is_empty() else "This save is corrupt."
		return corrupt
	var status: StringName = SaveSlotPreview.VALID
	var error_message := ""
	if envelope.campaign_id != expected_campaign_id:
		status = SaveSlotPreview.CAMPAIGN_MISMATCH
		error_message = "This save belongs to campaign '%s'." % envelope.campaign_id
	elif envelope.package_hash != expected_package_hash:
		status = SaveSlotPreview.PACKAGE_MISMATCH
		error_message = "This save was created for a different immutable package revision."
	var preview := SaveSlotPreview.new(slot_id, source, status)
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
	preview.can_load = status == SaveSlotPreview.VALID
	if preview.can_load:
		preview.map_preview_jpeg = envelope.map_preview_jpeg.duplicate()
	return preview


func _read_envelope(path: String) -> SaveEnvelope:
	var data: Variant = _read_document(path)
	return SaveEnvelope.from_data(data) if data != null else null


func _read_party_source_path(path: String, selector: String, slot_id: String, source_kind: StringName, fallback_campaign_id: String = "") -> SavePartySource:
	var source := SavePartySource.new()
	source._storage_selector = selector
	source.slot_id = slot_id
	source.source_kind = source_kind
	source.campaign_id = fallback_campaign_id
	if not FileAccess.file_exists(path):
		source.error = "This save file is missing."
		return source
	source.modified_unix = int(FileAccess.get_modified_time(path))
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		source.error = "This save file could not be read."
		return source
	var byte_count := file.get_length()
	if byte_count <= 0 or byte_count > MAX_PARTY_SOURCE_BYTES:
		file.close()
		source.error = "This save file is empty or exceeds the 512 MiB read limit."
		return source
	var bytes := file.get_buffer(byte_count)
	file.close()
	if bytes.size() != byte_count:
		source.error = "This save file could not be read completely."
		return source
	var hashing := HashingContext.new()
	if hashing.start(HashingContext.HASH_SHA256) != OK or hashing.update(bytes) != OK:
		source.error = "This save file could not be hashed."
		return source
	source.source_file_hash = hashing.finish().hex_encode()
	var parser := JSON.new()
	var parse_error := parser.parse(bytes.get_string_from_utf8())
	if parse_error != OK:
		source.error = "This save is corrupt."
		return source
	var envelope := SaveEnvelope.from_data(parser.data)
	if envelope == null:
		source.error = _incompatible_schema_message_for_data(parser.data)
		if source.error.is_empty():
			source.error = "This save is corrupt or uses an unsupported format."
		return source
	source.envelope = envelope
	source.campaign_id = envelope.campaign_id
	source.package_hash = envelope.package_hash
	source.rules_version = envelope.rules_version
	for character: CharacterState in envelope.game_state.party.characters():
		source.party_names.append(character.name)
	return source


func _party_source_error(message: String) -> SavePartySource:
	var source := SavePartySource.new()
	source.error = message
	return source


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
	return _incompatible_schema_message_for_data(data)


func _incompatible_schema_message_for_data(data: Variant) -> String:
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
