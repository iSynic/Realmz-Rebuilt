## One open save editor: the edited slot, its draft, member editors and the write-back.
## Presentation sends commands here and reads detached rows from the draft.

class_name SaveEditorSession
extends RefCounted

## Emitted after any accepted change to the save draft or a member's character draft.
signal changed
## Emitted once when the editor closes; `message` is the status to show, if any.
signal closed(message: String, is_error: bool)

var content: RealmzContent
var slot_id: String
var draft: SaveEditDraft
var last_error := ""
## Set after a save whose kept characters still wait for their Character File; the original save is held for them.
## The kept characters still waiting for their Character Files after the last save, or null.
var waiting: SaveHold
var _host: SaveHostController
var _vault: CharacterVaultController
var _holds: SaveEditHolds
var _original: SaveEnvelope
var _entropy := RandomNumberGenerator.new()
var _closed := false
## Set once the edit is written; the session then only retries waiting Character Files.
var _written := false


func _init(host: SaveHostController, vault: CharacterVaultController, holds: SaveEditHolds, scenario: RealmzContent, slot: String) -> void:
	_host = host
	_vault = vault
	_holds = holds
	content = scenario
	slot_id = slot
	_entropy.randomize()


## Reads the slot and opens its draft; false sets `last_error` with the reason editing is unavailable.
func open() -> bool:
	last_error = ""
	var loaded := _host.load(content, slot_id)
	if not loaded is SaveEnvelope:
		last_error = _host.last_error() if not _host.last_error().is_empty() else "This save can't be read."
		return false
	_original = loaded as SaveEnvelope
	last_error = SaveEditEligibility.reason(_original)
	if not last_error.is_empty():
		return false
	draft = SaveEditDraft.new(_original.game_state, content)
	return true


## The adventure as it was saved, for "was" values beside each setting.
func saved_state() -> GameState:
	return _original.game_state if _original != null else null


## Current Character Files revisions the add picker lists; each carries its own eligibility.
func character_file_candidates() -> Array[CharacterVaultRevisionView]:
	var result: Array[CharacterVaultRevisionView] = []
	for view: CharacterVaultRevisionView in _vault.revisions(content):
		if view.is_current and not view.archived:
			result.append(view)
	return result


## Why `text` can't name `character_id` because another member of the edited party has it, or "".
func name_conflict(character_id: String, text: String) -> String:
	for member: SaveEditMember in draft.members():
		if member.character_id != character_id and not member.dropped and member.state().name.to_lower() == text.strip_edges().to_lower():
			return "The party already has a %s." % member.state().name
	return ""


func is_dirty() -> bool:
	return draft != null and not _written and draft.is_dirty()


## A character editor bound to one member's draft, or null for an unknown member.
func member_editor(character_id: String) -> CharacterEditorSession:
	var member := draft.member(character_id)
	if member == null or member.dropped:
		return null
	var editor := CharacterEditorSession.for_member(member.draft, content, draft.next_item_instance_id.bind(character_id))
	editor.changed.connect(_on_member_changed)
	return editor


func set_difficulty(value: int) -> bool:
	return _result(draft.set_difficulty(value))


func set_monster_set(value: int) -> bool:
	return _result(draft.set_monster_set(value))


## Adds a Character File revision to the party under the scenario's admission rules.
func add_character(character_id: String, revision_hash: String) -> bool:
	# Listing against this save's content also scopes the vault's admission to it, not to
	# whichever scenario Saved Adventures prepared last.
	var listed := character_file_candidates().filter(func(view: CharacterVaultRevisionView) -> bool: return view.character_id == character_id and view.revision_hash == revision_hash)
	if listed.is_empty():
		last_error = "That Character File isn't available any more."
		return false
	if not (listed[0] as CharacterVaultRevisionView).eligible:
		last_error = "; ".join((listed[0] as CharacterVaultRevisionView).eligibility_reasons)
		return false
	var intent := _vault.import_intent(character_id, revision_hash)
	if intent == null or not intent.payload is PartyIntentPayloads.VaultImport:
		last_error = _vault.last_error() if not _vault.last_error().is_empty() else "This Character File can't be read."
		return false
	var source := intent.payload as PartyIntentPayloads.VaultImport
	return _result(draft.add_character(source.character_state, source.revision_hash, source.source_definitions, source.source_campaign_id))


func drop_character(character_id: String, keep_in_files: bool) -> bool:
	return _result(draft.drop_character(character_id, keep_in_files))


func set_keep_in_files(character_id: String, keep: bool) -> bool:
	return _result(draft.set_keep_in_files(character_id, keep))


func add_ally(definition_id: String) -> bool:
	return _result(draft.add_ally(definition_id, _entropy.randi()))


func dismiss_ally(ally_id: String) -> bool:
	return _result(draft.dismiss_ally(ally_id))


func undo(index: int) -> bool:
	return _result(draft.undo(index))


func discard() -> void:
	draft.discard()
	last_error = ""
	changed.emit()


## Writes the edited save back to its slot, then keeps dropped characters in Character Files.
## &"saved", &"kept_waiting" (the save is written; `waiting` holds the original for Retry) or &"failed".
func save() -> StringName:
	last_error = ""
	if _written:
		last_error = "This edit is already saved. Close the editor to edit the slot again."
		return &"failed"
	if not draft.refresh():
		last_error = draft.blocking_error
		return &"failed"
	# Kept characters are held before the save is written, so no failure or crash can lose them.
	var held := _holds.prepare(slot_id, _original, draft.kept_characters())
	if not _holds.last_error.is_empty():
		last_error = _holds.last_error
		return &"failed"
	if not _host.publish_edit(content, slot_id, _original, draft.state):
		last_error = _host.last_error()
		_release_unless_gone(held)
		return &"failed"
	_written = true
	if held == null or _holds.settle(content, held):
		return &"saved"
	waiting = held
	last_error = _holds.last_error
	return &"kept_waiting"


## Names of the kept characters still waiting for their Character Files.
func waiting_names() -> Array[String]:
	var names: Array[String] = []
	if waiting != null:
		names.assign(waiting.character_names)
	return names


## Tries the waiting Character Files again; true once none waits.
func retry_kept() -> bool:
	if waiting == null or _holds.settle(content, waiting):
		waiting = null
		last_error = ""
		return true
	last_error = _holds.last_error
	return false


func close(message: String = "", is_error: bool = false) -> void:
	if _closed:
		return
	_closed = true
	closed.emit(message, is_error)


## After a failed write the hold is released only while every kept character is still in the slot;
## if a write went through regardless, they stay held rather than surviving only in a backup.
func _release_unless_gone(held: SaveHold) -> void:
	if held == null:
		return
	var on_disk := _host.load(content, slot_id)
	for character_id: String in held.character_ids:
		if on_disk == null or on_disk.game_state.party.character_by_id(character_id) == null:
			return
	for character_id: String in held.character_ids.duplicate():
		_holds.let_go(held, character_id)


func _on_member_changed() -> void:
	if not draft.refresh():
		last_error = draft.blocking_error
	changed.emit()


func _result(applied: bool) -> bool:
	last_error = "" if applied else draft.last_error
	if applied:
		changed.emit()
	return applied
