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


func list_character_ids() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(_root_path)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and _safe_component(entry):
			result.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort_custom(func(left: String, right: String) -> bool: return left.naturalnocasecmp_to(right) < 0)
	return result


func current_revision_hash(character_id: String) -> String:
	return _read_current_hash(character_id) if _safe_component(character_id) else ""


func list_revisions(character_id: String, include_archived: bool = true) -> Array[CharacterVaultRecord]:
	last_error = ""
	var result: Array[CharacterVaultRecord] = []
	if not _safe_component(character_id):
		_fail("Character ID is not a portable path component.")
		return result
	_append_revision_records("%s/%s" % [_root_path, character_id], character_id, result)
	if include_archived:
		_append_revision_records("%s/%s/archive" % [_root_path, character_id], character_id, result)
	var unique: Dictionary = {}
	var deduplicated: Array[CharacterVaultRecord] = []
	for record: CharacterVaultRecord in result:
		if unique.has(record.revision_hash):
			continue
		unique[record.revision_hash] = true
		deduplicated.append(record)
	deduplicated.sort_custom(func(left: CharacterVaultRecord, right: CharacterVaultRecord) -> bool: return left.revision_hash < right.revision_hash)
	return deduplicated


func revision_is_archived(character_id: String, revision_hash: String) -> bool:
	if not _safe_component(character_id) or not _safe_component(revision_hash):
		return false
	return FileAccess.file_exists("%s/%s/archive/%s%s" % [_root_path, character_id, revision_hash, RECORD_EXTENSION])


func load_revision(character_id: String, revision_hash: String) -> CharacterVaultRecord:
	last_error = ""
	if not _safe_component(character_id) or not _safe_component(revision_hash):
		_fail("Character and revision IDs must be portable path components.")
		return null
	var path := "%s/%s/%s%s" % [_root_path, character_id, revision_hash, RECORD_EXTENSION]
	var record := _read_record(path)
	if record == null or record.character_id != character_id or record.revision_hash != revision_hash:
		return null
	return record


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


func seed_if_empty(records: Array[CharacterVaultRecord]) -> bool:
	last_error = ""
	if records.is_empty():
		return _fail("Starter-character seeding requires at least one record.")
	var root_directory := DirAccess.open(_root_path)
	if root_directory != null:
		root_directory.list_dir_begin()
		var existing_entry := root_directory.get_next()
		root_directory.list_dir_end()
		if not existing_entry.is_empty():
			return true
		root_directory = null
	var stage_path := _root_path + ".starter-seed"
	if not _remove_tree(stage_path):
		return _fail("Could not clear an interrupted starter-character staging directory.")
	var stage_repository := CharacterVaultRepository.new(stage_path)
	for source_record: CharacterVaultRecord in records:
		var staged_record := CharacterVaultRecord.from_data(source_record.to_data()) if source_record != null else null
		if staged_record == null or not stage_repository.publish_revision(staged_record) or staged_record.revision_hash != source_record.revision_hash:
			_remove_tree(stage_path)
			return _fail("Starter-character staging failed: %s" % stage_repository.last_error)
	var staged_records := stage_repository.list_current_records()
	if staged_records.size() != records.size():
		_remove_tree(stage_path)
		return _fail("Starter-character staging did not produce the complete catalog.")
	for record: CharacterVaultRecord in records:
		var staged := stage_repository.load_revision(record.character_id, record.revision_hash)
		if staged == null or CanonicalJson.encode(staged.to_data()) != CanonicalJson.encode(record.to_data()):
			_remove_tree(stage_path)
			return _fail("Starter-character staging readback failed.")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_root_path)) and DirAccess.remove_absolute(ProjectSettings.globalize_path(_root_path)) != OK:
		_remove_tree(stage_path)
		return _fail("Could not replace the empty character-vault directory.")
	var rename_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(stage_path), ProjectSettings.globalize_path(_root_path))
	if rename_error != OK:
		_remove_tree(stage_path)
		return _fail("Could not install the starter-character vault (error %d)." % rename_error)
	return true


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
	var moved := false
	if not FileAccess.file_exists(destination):
		var move_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination))
		if move_error != OK:
			return _fail("Could not archive the character revision (error %d)." % move_error)
		moved = true
	else:
		var archived := _read_record(destination)
		if archived == null or archived.character_id != character_id or archived.revision_hash != current_hash:
			return _fail("The archived character revision does not match the current revision identity.")
	if not _delete_file("%s/%s/current.json" % [_root_path, character_id]):
		if moved:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(destination), ProjectSettings.globalize_path(source))
		return _fail("Could not clear the current character revision index.")
	return true


func restore_revision(character_id: String, revision_hash: String) -> bool:
	last_error = ""
	if not _safe_component(character_id) or not _safe_component(revision_hash):
		return _fail("Character and revision IDs must be portable path components.")
	if not _read_current_hash(character_id).is_empty():
		return _fail("Archive recovery is available only when the character has no current revision.")
	var active_path := "%s/%s/%s%s" % [_root_path, character_id, revision_hash, RECORD_EXTENSION]
	var archive_path := "%s/%s/archive/%s%s" % [_root_path, character_id, revision_hash, RECORD_EXTENSION]
	var moved := false
	if not FileAccess.file_exists(active_path):
		if not FileAccess.file_exists(archive_path):
			return _fail("The archived character revision is unavailable.")
		var move_error := DirAccess.rename_absolute(ProjectSettings.globalize_path(archive_path), ProjectSettings.globalize_path(active_path))
		if move_error != OK:
			return _fail("Could not restore the archived character revision (error %d)." % move_error)
		moved = true
	var restored := load_revision(character_id, revision_hash)
	if restored == null or not _write_current_hash(character_id, revision_hash):
		if moved:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(active_path), ProjectSettings.globalize_path(archive_path))
		return _fail("The restored character revision could not be validated and indexed.")
	return true


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
	for binding: FastSpellBindingState in record.state.fast_spells():
		if binding.is_empty():
			continue
		var bound_spell := content.spell_by_id(binding.spell_id)
		if bound_spell == null:
			result.reasons.append("Fast Spell '%s' is not defined by this campaign." % binding.spell_id)
		elif not record.state.known_spells().has(binding.spell_id):
			result.reasons.append("Fast Spell '%s' is no longer known by this character." % binding.spell_id)
		elif binding.power < 1 or binding.power > 7 or bound_spell.cost < 0 and binding.power != 1:
			result.reasons.append("Fast Spell '%s' uses an invalid power." % binding.spell_id)
	if content.has_character_appearance_catalog():
		var portrait := content.appearance_by_id(record.state.portrait_id) if not record.state.portrait_id.is_empty() else null
		if not record.state.portrait_id.is_empty() and (portrait == null or portrait.kind != CharacterAppearanceDefinition.PORTRAIT):
			result.reasons.append("Portrait '%s' is not defined by this campaign package." % record.state.portrait_id)
		var combat_icon := content.appearance_by_id(record.state.combat_icon_id) if not record.state.combat_icon_id.is_empty() else null
		if not record.state.combat_icon_id.is_empty() and (combat_icon == null or combat_icon.kind != CharacterAppearanceDefinition.COMBAT_ICON):
			result.reasons.append("Combat icon '%s' is not defined by this campaign package." % record.state.combat_icon_id)
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


func _append_revision_records(directory_path: String, character_id: String, records: Array[CharacterVaultRecord]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir() and entry.ends_with(RECORD_EXTENSION):
			var record := _read_record("%s/%s" % [directory_path, entry])
			var expected_hash := entry.trim_suffix(RECORD_EXTENSION)
			if record != null and record.character_id == character_id and record.revision_hash == expected_hash:
				records.append(record)
		entry = directory.get_next()
	directory.list_dir_end()


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


func _remove_tree(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return true
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child := "%s/%s" % [path, entry]
		if directory.current_is_dir():
			if not _remove_tree(child):
				directory.list_dir_end()
				return false
		elif DirAccess.remove_absolute(ProjectSettings.globalize_path(child)) != OK:
			directory.list_dir_end()
			return false
		entry = directory.get_next()
	directory.list_dir_end()
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
