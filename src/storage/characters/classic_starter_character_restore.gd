## Adds current compatible starter copies without rewriting existing Character Files.
class_name ClassicStarterCharacterRestore
extends RefCounted

var restored_names: Array[String] = []
var present_names: Array[String] = []
var last_error := ""
var backup := CharacterVaultBackup.new()
var _repository: CharacterVaultRepository
var _application: RealmzContent


func _init(repository: CharacterVaultRepository, application: RealmzContent) -> void:
	_repository = repository
	_application = application


func execute() -> bool:
	restored_names.clear()
	present_names.clear()
	last_error = ""
	backup = CharacterVaultBackup.new()
	if _application == null:
		return _fail("The built-in character library is not ready. No characters were changed.")
	var catalog := ClassicStarterCharacterCatalog.new()
	var templates := catalog.load_records(ClassicStarterCharacterCatalog.PATH, _application.package_hash, _application)
	if templates.is_empty():
		return _fail(catalog.last_error)
	var current := _repository.list_current_records()
	var missing: Array[CharacterVaultRecord] = []
	for template: CharacterVaultRecord in templates:
		if current.any(func(record: CharacterVaultRecord) -> bool: return _matches_starter(record, template)):
			present_names.append(template.state.name)
		else:
			missing.append(template)
	if missing.is_empty():
		return true
	var root := _repository.directory_path()
	if FileAccess.file_exists(root):
		return _fail("The Character Files folder location is occupied by a file. No characters were changed.")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root)):
		var original := backup.snapshot(root)
		if not backup.last_error.is_empty() or not backup.create(root, original):
			return _fail(backup.last_error)
	for template: CharacterVaultRecord in missing:
		var record := _fresh_copy(template)
		if record == null or not _repository.publish_new_character(record):
			return _fail("Restoration stopped after adding %d starters. %s Existing characters are preserved; retry to add the remaining starters." % [restored_names.size(), _repository.last_error])
		var verified := _repository.load_revision(record.character_id, record.revision_hash)
		if verified == null or CanonicalJson.encode(verified.to_data()) != CanonicalJson.encode(record.to_data()) or _repository.current_revision_hash(record.character_id) != record.revision_hash:
			return _fail("A restored starter could not be verified. Existing characters are preserved; retry to add any missing starters.")
		restored_names.append(template.state.name)
	return true


func details() -> String:
	var result := "Restored %d starter characters. Existing characters were preserved." % restored_names.size() if last_error.is_empty() else last_error
	if not restored_names.is_empty():
		result += "\n\nAdded: " + ", ".join(restored_names)
	if not present_names.is_empty():
		result += "\n\nAlready available: " + ", ".join(present_names)
	result += "\n\nThese are fresh copies of the original starters, not conversions of older characters. Saves and the current party were not changed."
	if backup.complete:
		result += "\n\nComplete vault backup:\n" + ProjectSettings.globalize_path(backup.path)
	return result


func _fresh_copy(template: CharacterVaultRecord) -> CharacterVaultRecord:
	var root := _repository.directory_path()
	var identity := template.character_id
	var suffix := 1
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(root.path_join(identity))) or FileAccess.file_exists(root.path_join(identity)):
		identity = "%s.restored.%d" % [template.character_id, suffix]
		suffix += 1
	var state := CharacterStateCodec.copy_with_identity(template.state, identity)
	if state == null:
		return null
	var record := CharacterVaultRecord.new(identity, template.rules_version, template.source_campaign_id, template.source_package_hash, state, template.source_revision)
	record.source_rules = template.source_rules
	record.publication_metadata = template.publication_metadata.duplicate(true)
	record.publication_metadata["starterId"] = template.character_id
	return record


func _matches_starter(record: CharacterVaultRecord, template: CharacterVaultRecord) -> bool:
	if record.character_id != template.character_id and record.publication_metadata.get("starterId", "") != template.character_id:
		return false
	return record.source_revision == template.source_revision and record.publication_metadata.get("source", "") == template.publication_metadata.get("source", "") and record.rules_version == template.rules_version and record.source_rules != null and record.source_rules.to_data() == template.source_rules.to_data()


func _fail(message: String) -> bool:
	last_error = message
	return false
