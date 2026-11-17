## One open edit of a Character File: its parent revision and readback-verified publication.

class_name CharacterVaultEdit
extends RefCounted

## The character's scenario-specific rule source, when its rules can't be edited here.
var custom_rules_reason: String
var last_error := ""
## True when the last failed publication found a newer current revision.
var conflict := false
var _repository: CharacterVaultRepository
var _parent: CharacterVaultRecord


func _init(repository: CharacterVaultRepository, parent: CharacterVaultRecord, custom_reason: String) -> void:
	_repository = repository
	_parent = parent
	custom_rules_reason = custom_reason


func character_id() -> String:
	return _parent.character_id


func parent_hash() -> String:
	return _parent.revision_hash


## A detached copy of the parent revision's character.
func parent_state() -> CharacterState:
	return CharacterStateCodec.copy(_parent.state)


## Publishes `character` as the next revision while the parent is still current.
## Provenance, source rules and artwork carry over; the publication names the editor and parent.
func publish(character: CharacterState) -> bool:
	last_error = ""
	conflict = _repository.current_revision_hash(_parent.character_id) != _parent.revision_hash
	if conflict:
		last_error = "This character was changed elsewhere after you started editing."
		return false
	var state := CharacterStateCodec.copy(character)
	if state == null or state.id != _parent.character_id:
		last_error = "The edited character is invalid."
		return false
	var record := CharacterVaultRecord.new(_parent.character_id, _parent.rules_version, _parent.source_campaign_id, _parent.source_package_hash, state, _parent.source_revision)
	record.revision_hash = _parent.revision_hash
	record.source_rules = _parent.source_rules
	record.character_art = _parent.character_art
	record.publication_metadata = _parent.publication_metadata.duplicate(true)
	record.publication_metadata.merge({"name": state.name, "level": state.level, "edit": {"source": "character-editor", "parentRevision": _parent.revision_hash}}, true)
	if record.publication_metadata.has("label"):
		record.publication_metadata["label"] = state.name
	if not _repository.publish_revision(record):
		last_error = _repository.last_error
		conflict = _repository.current_revision_hash(_parent.character_id) != _parent.revision_hash
		return false
	_parent = record
	return true
