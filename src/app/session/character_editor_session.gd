## One open Character Files editor: the draft, its fresh Level Up dice and publication.
## Presentation sends commands here and reads detached rows from `queries`.

class_name CharacterEditorSession
extends RefCounted

## Emitted once when the editor closes; `message` is the status to show, if any.
signal closed(message: String, is_error: bool)
## Emitted after any accepted change to the draft, including undo and discard.
signal changed

var queries: CharacterEditorQueries
var last_error := ""
var _draft: CharacterEditDraft
var _edit: CharacterVaultEdit
## Level Up dice come from host entropy, so Undo and Level Up again rerolls.
var _entropy := RandomNumberGenerator.new()
var _closed := false
## Supplies carried-item identities; a save-editor member needs identities unique across the whole party.
var _next_instance: Callable


## Edits a party member's draft inside the save editor; publication belongs to the save editor.
static func for_member(member_draft: CharacterEditDraft, content: RealmzContent, next_instance: Callable) -> CharacterEditorSession:
	return CharacterEditorSession.new(null, content, member_draft, next_instance)


func _init(edit: CharacterVaultEdit, content: RealmzContent, member_draft: CharacterEditDraft = null, next_instance: Callable = Callable()) -> void:
	_edit = edit
	_next_instance = next_instance
	_entropy.randomize()
	if member_draft != null:
		_draft = member_draft
	else:
		var base := edit.parent_state()
		_draft = CharacterEditDraft.new(base, CharacterEditContext.new(content, base, edit.custom_rules_reason))
	queries = CharacterEditorQueries.new(_draft, content)


func character_id() -> String:
	return _edit.character_id() if _edit != null else _draft.base.id


func is_dirty() -> bool:
	return _draft.is_dirty()


func changes() -> Array[Dictionary]:
	return _draft.changes()


## Applies one editor operation; false leaves the draft unchanged and sets `last_error`.
func apply(operation: Dictionary) -> bool:
	return _result(_draft.apply(operation))


func undo(index: int) -> bool:
	return _result(_draft.undo(index))


func undo_level_up() -> bool:
	return _result(_draft.undo_level_up())


func level_up() -> bool:
	return apply({"kind": &"level_up", "seed": _entropy.randi()})


func add_item(definition_id: String) -> bool:
	var instance_id: String = _next_instance.call() if _next_instance.is_valid() else _draft.next_item_instance_id()
	return apply({"kind": &"add_item", "definition_id": definition_id, "instance_id": instance_id})


func discard() -> void:
	_draft.discard()
	last_error = ""
	changed.emit()


## Publishes the draft: &"saved", &"conflict" (a newer revision exists) or &"failed".
func save() -> StringName:
	last_error = ""
	if _edit == null:
		last_error = "A party member is saved with its adventure."
		return &"failed"
	if _edit.publish(_draft.state):
		return &"saved"
	last_error = _edit.last_error
	return &"conflict" if _edit.conflict else &"failed"


## Leaves the editor. The host refreshes Character Files and shows `message`.
func close(message: String = "", is_error: bool = false) -> void:
	if _closed:
		return
	_closed = true
	closed.emit(message, is_error)


func _result(applied: bool) -> bool:
	last_error = "" if applied else _draft.last_error
	if applied:
		changed.emit()
	return applied
