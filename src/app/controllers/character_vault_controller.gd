class_name CharacterVaultController
extends RefCounted

const CharacterVaultRepositoryScript := preload("res://src/infrastructure/characters/character_vault_repository.gd")

var _repository: CharacterVaultRepository


func _init(repository: CharacterVaultRepository = null) -> void:
	_repository = repository if repository != null else CharacterVaultRepositoryScript.new()


func import_intent(character_id: String, revision_hash: String) -> PlayerIntent:
	var record := _repository.load_revision(character_id, revision_hash)
	if record == null:
		return null
	return PlayerIntent.import_vault_character(record.character_id, record.revision_hash, record.state, record.source_campaign_id, record.source_package_hash)


func publish(character: CharacterState, rules_version: String, source_campaign_id: String, source_package_hash: String, publication_source: String) -> bool:
	if character == null:
		return false
	var record := CharacterVaultRecord.new(character.id, rules_version, source_campaign_id, source_package_hash, character)
	record.publication_metadata = {"name": character.name, "level": character.level, "source": publication_source}
	return _repository.publish_revision(record)


func revisions(active_content: RealmzContent, fallback_content: RealmzContent = null) -> Array[CharacterVaultRevisionView]:
	var result: Array[CharacterVaultRevisionView] = []
	var display_content := active_content if active_content != null else fallback_content
	for character_id: String in _repository.list_character_ids():
		var current_hash := _repository.current_revision_hash(character_id)
		var character_archived := current_hash.is_empty()
		for record: CharacterVaultRecord in _repository.list_revisions(character_id):
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
	return _repository.archive_character(character_id)


func restore(character_id: String, revision_hash: String) -> bool:
	return _repository.restore_revision(character_id, revision_hash)


func last_error() -> String:
	return _repository.last_error
