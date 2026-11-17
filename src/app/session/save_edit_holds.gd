## Keeps characters dropped by the save editor as Character Files.
## Every kept character is held (with a pinned copy of the original save) before the edit is written,
## so a failure or crash at any point leaves them recoverable from Saved Adventures.

class_name SaveEditHolds
extends RefCounted

var last_error := ""
var _store: SaveHoldStore
var _vault: CharacterVaultController


func _init(store: SaveHoldStore, vault: CharacterVaultController) -> void:
	_store = store
	_vault = vault


func holds(campaign_id: String) -> Array[SaveHold]:
	return _store.holds(campaign_id)


## Holds `characters` with a pinned copy of `original` before the edit is written.
## Returns the hold; null with no error when nothing is kept, or null with last_error when it can't be held.
func prepare(slot_id: String, original: SaveEnvelope, characters: Array[CharacterState]) -> SaveHold:
	last_error = ""
	if characters.is_empty():
		return null
	var held := _store.hold(slot_id, original, characters)
	if held == null:
		last_error = "%s Nothing was written." % _store.last_error
	return held


## Publishes every character `held` still waits for; true once none waits.
## `content` must be the held save's own package so each file records its exact rules.
func settle(content: RealmzContent, held: SaveHold) -> bool:
	last_error = ""
	if content == null or content.package_hash != held.package_hash:
		last_error = "Select a save from the same scenario version as Slot %s's held save, then retry." % held.slot_id
		return false
	for character_id: String in held.character_ids.duplicate():
		if not _settle_one(content, held, character_id):
			return false
	return true


## Gives up one waiting character; the pinned copy goes once nothing waits on it.
func let_go(held: SaveHold, character_id: String) -> bool:
	last_error = ""
	if _store.release(held, character_id):
		return true
	last_error = _store.last_error
	return false


func _settle_one(content: RealmzContent, held: SaveHold, character_id: String) -> bool:
	var character := held.character(character_id)
	if character == null:
		last_error = "%s's held copy can't be read." % held.name_of(character_id)
		return false
	var title := content.campaign.title if content.campaign != null and not content.campaign.title.is_empty() else content.campaign_id
	var label := "%s · from %s Slot %s" % [character.name, title, held.slot_id]
	# The publication source names this hold and character, so a file published earlier under the
	# reservation (whose release then failed) is recognised exactly, never by its display label.
	var source := "save-editor/%s/%s" % [held.hold_id, character_id]
	var identity := _reserved_identity(held, character_id)
	var found := _files_scan(content, source, identity.character_id if identity != null else "")
	# Published earlier (its release or even its reported publish failed): release it now, never twice.
	var published: bool = found.published
	var reserved_taken: bool = found.reserved_taken
	if published:
		return _release(held, character_id)
	if identity == null or reserved_taken:
		identity = _vault.next_character_file_identity()
		if identity == null or not _store.reserve_file(held, character_id, "%s|%d" % [identity.character_id, identity.seed]):
			last_error = "%s couldn't be kept in Character Files: %s" % [character.name, _vault.last_error() if identity == null else _store.last_error]
			return false
	if _vault.publish_party_character(character, content, source, label, identity).is_empty():
		last_error = "%s couldn't be kept in Character Files: %s" % [character.name, _vault.last_error()]
		# A refused identity (one retired by a deletion, say) is given up, so the next Retry reserves another.
		_store.reserve_file(held, character_id, "")
		return false
	return _release(held, character_id)


func _release(held: SaveHold, character_id: String) -> bool:
	if _store.release(held, character_id):
		return true
	last_error = _store.last_error
	return false


func _reserved_identity(held: SaveHold, character_id: String) -> CharacterFileIdentity:
	var reserved := held.file_id(character_id)
	if reserved.get_slice_count("|") != 2:
		return null
	return CharacterFileIdentity.new(reserved.get_slice("|", 0), reserved.get_slice("|", 1).to_int())


## Whether a Character File already carries `source`, and whether `reserved_id` is taken by any file.
func _files_scan(content: RealmzContent, source: String, reserved_id: String) -> Dictionary:
	var published := false
	var reserved_taken := false
	for revision: CharacterVaultRevisionView in _vault.revisions(content):
		published = published or revision.publication_source == source
		reserved_taken = reserved_taken or (not reserved_id.is_empty() and revision.character_id == reserved_id)
	return {"published": published, "reserved_taken": reserved_taken}
