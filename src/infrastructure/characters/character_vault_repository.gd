class_name CharacterVaultRepository
extends RefCounted

const RECORD_EXTENSION := ".r2char"

var _root_path: String
var last_error: String = ""


func _init(root_path: String = "user://characters") -> void:
	_root_path = root_path.trim_suffix("/")


func list_current_records() -> Array[CharacterVaultRecord]:
	last_error = ""
	var result: Array[CharacterVaultRecord] = []
	var directory := DirAccess.open(_root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() or entry.begins_with("."):
			entry = directory.get_next()
			continue
		var current_hash := _read_current_hash(entry)
		if not current_hash.is_empty():
			var record := load_revision(entry, current_hash)
			if record != null:
				result.append(record)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort_custom(func(left: CharacterVaultRecord, right: CharacterVaultRecord) -> bool: return left.character_id.naturalnocasecmp_to(right.character_id) < 0)
	return result


func load_revision(character_id: String, revision_hash: String) -> CharacterVaultRecord:
	last_error = ""
	if not _safe_component(character_id) or not _safe_component(revision_hash):
		_fail("Character and revision IDs must be portable path components.")
		return null
	var path := "%s/%s/%s%s" % [_root_path, character_id, revision_hash, RECORD_EXTENSION]
	return _read_record(path)


func publish_revision(record: CharacterVaultRecord) -> bool:
	last_error = ""
	if record == null or record.state == null or not _safe_component(record.character_id) or record.state.id != record.character_id:
		return _fail("A valid character record is required.")
	if record.rules_version.is_empty() or record.source_package_hash.length() != 64:
		return _fail("Character provenance is incomplete.")
	record.revision_hash = _revision_hash(record)
	var directory_path := "%s/%s" % [_root_path, record.character_id]
	var create_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory_path))
	if create_error != OK:
		return _fail("Could not create the character vault directory (error %d)." % create_error)
	var record_path := "%s/%s%s" % [directory_path, record.revision_hash, RECORD_EXTENSION]
	var temp_path := record_path + ".tmp"
	var backup_path := record_path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not open the temporary character revision.")
	file.store_string(CanonicalJson.encode(record.to_data()))
	file.flush()
	file.close()
	var verified := _read_record(temp_path)
	if verified == null or verified.revision_hash != record.revision_hash:
		_delete_file(temp_path)
		return _fail("Character revision verification failed.")
	if FileAccess.file_exists(backup_path):
		_delete_file(backup_path)
	if FileAccess.file_exists(record_path):
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(record_path), ProjectSettings.globalize_path(backup_path))
		if backup_error != OK:
			_delete_file(temp_path)
			return _fail("Could not rotate the character revision backup (error %d)." % backup_error)
	var replace_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(record_path))
	if replace_error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(record_path))
		_delete_file(temp_path)
		return _fail("Could not install the character revision (error %d)." % replace_error)
	return _write_current_hash(record.character_id, record.revision_hash)


func archive_character(character_id: String) -> bool:
	last_error = ""
	if not _safe_component(character_id):
		return _fail("Character ID is not a portable path component.")
	var current_hash := _read_current_hash(character_id)
	if current_hash.is_empty():
		return _fail("The character has no current revision.")
	var archive_path := "%s/%s/archive" % [_root_path, character_id]
	var create_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive_path))
	if create_error != OK:
		return _fail("Could not create the character archive (error %d)." % create_error)
	var source := "%s/%s/%s%s" % [_root_path, character_id, current_hash, RECORD_EXTENSION]
	var destination := "%s/%s%s" % [archive_path, current_hash, RECORD_EXTENSION]
	if not FileAccess.file_exists(source):
		return _fail("The current character revision is missing.")
	var move_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))
	if move_error != OK:
		return _fail("Could not archive the character revision (error %d)." % move_error)
	return _delete_file("%s/%s/current.json" % [_root_path, character_id])


func campaign_eligibility(record: CharacterVaultRecord, content: RealmzContent) -> CharacterVaultEligibility:
	var result := CharacterVaultEligibility.new()
	if record == null or record.state == null or content == null:
		result.reasons.append("Character or campaign content is unavailable.")
		return result
	var race := content.race_by_id(record.state.race_id)
	var caste := content.caste_by_id(record.state.caste_id)
	if race == null:
		result.reasons.append("Race '%s' is not defined by this campaign." % record.state.race_id)
	if caste == null:
		result.reasons.append("Class '%s' is not defined by this campaign." % record.state.caste_id)
	var restrictions := content.campaign_definition().restrictions
	if restrictions.banned_races.has(record.state.race_id):
		result.reasons.append("This campaign does not allow race '%s'." % record.state.race_id)
	if restrictions.banned_castes.has(record.state.caste_id):
		result.reasons.append("This campaign does not allow class '%s'." % record.state.caste_id)
	if restrictions.maximum_level > 0 and record.state.level > restrictions.maximum_level:
		result.reasons.append("Character level %d exceeds this campaign's maximum level %d." % [record.state.level, restrictions.maximum_level])
	if race != null and not race.eligible_caste_ids.is_empty() and not race.eligible_caste_ids.has(record.state.caste_id):
		result.reasons.append("Race '%s' cannot use class '%s'." % [race.name, caste.name if caste != null else record.state.caste_id])
	if caste != null and not caste.eligible_race_ids.is_empty() and not caste.eligible_race_ids.has(record.state.race_id):
		result.reasons.append("Class '%s' is not available to race '%s'." % [caste.name, race.name if race != null else record.state.race_id])
	for item: ItemInstance in record.state.inventory():
		if content.item_by_id(item.definition_id) == null:
			result.reasons.append("Item '%s' is not defined by this campaign." % item.definition_id)
	for spell_id: String in record.state.known_spells():
		if content.spell_by_id(spell_id) == null:
			result.reasons.append("Spell '%s' is not defined by this campaign." % spell_id)
	if record.state.level < 1:
		result.reasons.append("Character level is below the Classic minimum.")
	result.eligible = result.reasons.is_empty()
	return result


func _write_current_hash(character_id: String, revision_hash: String) -> bool:
	var index_path := "%s/%s/current.json" % [_root_path, character_id]
	var temp_path := index_path + ".tmp"
	var backup_path := index_path + ".bak"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return _fail("Could not write the current character revision index.")
	file.store_string(CanonicalJson.encode({"characterId": character_id, "revisionHash": revision_hash}))
	file.flush()
	file.close()
	if FileAccess.file_exists(backup_path):
		_delete_file(backup_path)
	if FileAccess.file_exists(index_path):
		var backup_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(index_path), ProjectSettings.globalize_path(backup_path))
		if backup_error != OK:
			_delete_file(temp_path)
			return _fail("Could not rotate the current character revision backup (error %d)." % backup_error)
	var error := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(index_path))
	if error != OK:
		if FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(ProjectSettings.globalize_path(backup_path), ProjectSettings.globalize_path(index_path))
		_delete_file(temp_path)
		return _fail("Could not install the current character revision index (error %d)." % error)
	return true


func _read_current_hash(character_id: String) -> String:
	var path := "%s/%s/current.json" % [_root_path, character_id]
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or parsed.get("characterId", "") != character_id or not parsed.get("revisionHash", "") is String:
		return ""
	return String(parsed["revisionHash"])


func _read_record(path: String) -> CharacterVaultRecord:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return CharacterVaultRecord.from_data(parsed)


func _revision_hash(record: CharacterVaultRecord) -> String:
	var data := record.to_data()
	data["revisionHash"] = ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(CanonicalJson.encode(data).to_utf8_buffer())
	return context.finish().hex_encode()


func _delete_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK


func _safe_component(value: String) -> bool:
	if value.is_empty() or value.length() > 128 or value in [".", ".."] or value.begins_with(".") or value.ends_with("."):
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 46, 95]):
			return false
	return true


func _fail(message: String) -> bool:
	last_error = message
	return false
