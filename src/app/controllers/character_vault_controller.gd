class_name CharacterVaultController
extends RefCounted

const CharacterVaultRepositoryScript := preload("res://src/infrastructure/characters/character_vault_repository.gd")
const ClassicStarterCharacterCatalogScript := preload("res://src/infrastructure/characters/classic_starter_character_catalog.gd")
const CLASSIC_STARTER_CATALOG_PATH := "res://src/infrastructure/characters/realmz-classic-starter-characters.json"
const CLASSIC_CHARACTER_LIBRARY_HASH := "6e3f23c9a452f70b25040c729e17533de5ddf0c420ff35484fc52f6e0dd25e68"

var _repository: CharacterVaultRepository
var _validated_records: Dictionary = {}
var _operation_error: String = ""


func _init(repository: CharacterVaultRepository = null) -> void:
	_repository = repository if repository != null else CharacterVaultRepositoryScript.new()


func import_intent(character_id: String, revision_hash: String) -> PlayerIntent:
	var cache_key := _cache_key(character_id, revision_hash)
	var record := _validated_records.get(cache_key) as CharacterVaultRecord
	if record == null:
		record = _repository.load_revision(character_id, revision_hash)
		if record != null:
			_validated_records[cache_key] = record
	if record == null:
		return null
	var detached_state := CharacterState.from_data(record.state.to_data())
	return PlayerIntent.import_vault_character(record.character_id, record.revision_hash, detached_state, record.source_campaign_id, record.source_package_hash) if detached_state != null else null


func publish(character: CharacterState, rules_version: String, source_campaign_id: String, source_package_hash: String, publication_source: String) -> bool:
	if character == null:
		return false
	var record := CharacterVaultRecord.new(character.id, rules_version, source_campaign_id, source_package_hash, character)
	record.publication_metadata = {"name": character.name, "level": character.level, "source": publication_source}
	var published := _repository.publish_revision(record)
	if published:
		_validated_records.clear()
	return published


func seed_if_empty(records: Array[CharacterVaultRecord]) -> bool:
	_operation_error = ""
	var seeded := _repository.seed_if_empty(records)
	if seeded:
		_validated_records.clear()
	return seeded


func seed_classic_starters_if_empty(catalog_path: String = CLASSIC_STARTER_CATALOG_PATH, application_library_hash: String = CLASSIC_CHARACTER_LIBRARY_HASH) -> bool:
	var catalog := ClassicStarterCharacterCatalogScript.new()
	var records := catalog.load_records(catalog_path, application_library_hash)
	if records.is_empty():
		_operation_error = catalog.last_error
		push_warning("Starter characters were not installed: %s" % _operation_error)
		return false
	var seeded := seed_if_empty(records)
	if not seeded:
		push_warning("Starter characters were not installed: %s" % last_error())
	return seeded


func revisions(active_content: RealmzContent, fallback_content: RealmzContent = null) -> Array[CharacterVaultRevisionView]:
	_validated_records.clear()
	var result: Array[CharacterVaultRevisionView] = []
	var display_content := active_content if active_content != null else fallback_content
	for character_id: String in _repository.list_character_ids():
		var current_hash := _repository.current_revision_hash(character_id)
		var character_archived := current_hash.is_empty()
		for record: CharacterVaultRecord in _repository.list_revisions(character_id):
			_validated_records[_cache_key(record.character_id, record.revision_hash)] = record
			var eligibility := _repository.campaign_eligibility(record, active_content) if active_content != null else null
			result.append(CharacterVaultRevisionView.from_record(record, eligibility, record.revision_hash == current_hash, character_archived, display_content))
	result.sort_custom(func(left: CharacterVaultRevisionView, right: CharacterVaultRevisionView) -> bool:
		var character_order := left.character_id.naturalnocasecmp_to(right.character_id)
		if character_order != 0:
			return character_order < 0
		if left.is_current != right.is_current:
			return left.is_current
		return left.revision_hash < right.revision_hash
	)
	return result


func next_character_file_identity() -> CharacterFileIdentity:
	var occupied: Dictionary = {}
	for character_id: String in _repository.list_character_ids():
		occupied[character_id] = true
	var sequence := 1
	while occupied.has("realmz.character.%d" % sequence):
		sequence += 1
	return CharacterFileIdentity.new("realmz.character.%d" % sequence, sequence * 7919 + 1)


func archive(character_id: String) -> bool:
	var archived := _repository.archive_character(character_id)
	if archived:
		_validated_records.clear()
	return archived


func restore(character_id: String, revision_hash: String) -> bool:
	var restored := _repository.restore_revision(character_id, revision_hash)
	if restored:
		_validated_records.clear()
	return restored


func cached_revision_count() -> int:
	return _validated_records.size()


func last_error() -> String:
	return _operation_error if not _operation_error.is_empty() else _repository.last_error


static func _cache_key(character_id: String, revision_hash: String) -> String:
	return "%s:%s" % [character_id, revision_hash]
