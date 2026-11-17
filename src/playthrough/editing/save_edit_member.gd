## One party member in a save editor draft: their own character draft and where they came
## from. Whether they are dropped, and kept in Character Files, follows the draft's listed
## party changes.

class_name SaveEditMember
extends RefCounted

## A member of the saved party.
const SAVED: StringName = &"saved"
## A character who joins from Character Files in this draft.
const ADDED: StringName = &"added"

var character_id: String
var origin: StringName
var draft: CharacterEditDraft
## The Character Files revision an added member came from, or "".
var source_revision := ""
var dropped := false
var keep_in_files := false


func _init(member_origin: StringName, character_draft: CharacterEditDraft, revision: String = "") -> void:
	origin = member_origin
	draft = character_draft
	character_id = character_draft.base.id
	source_revision = revision


func state() -> CharacterState:
	return draft.state
