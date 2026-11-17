## The save editor's picker and dialog flows: adding from Character Files or allies, dropping a
## member, discarding, leaving, reviewing and writing. The workspace owns the pages and focus;
## these flows only ask the session for changes and report what happened.

class_name SaveEditorFlows
extends RefCounted

## A change was applied (true) or refused (false; the session's last_error says why).
signal applied(ok: bool)
## The page to show next, such as a member just added.
signal page_chosen(page_id: String)
## Every change was discarded; the workspace returns to Adventure settings.
signal discarded
## The leave dialog's "Review and save…": the workspace opens the review with its change list.
signal review_requested

var _session: SaveEditorSession
var _dialog: EditorDialog
var _picker: SaveEditorPicker
var _picker_mode: StringName = &""
var _dialog_target := ""


func _init(dialog: EditorDialog, picker: SaveEditorPicker) -> void:
	_dialog = dialog
	_picker = picker
	_picker.chosen.connect(_picker_chosen)
	_dialog.chosen.connect(dialog_chosen)


func set_session(session: SaveEditorSession) -> void:
	_session = session
	_picker_mode = &""
	_dialog_target = ""


## &"files" or &"ally" while that picker is open, so closing it can return focus to its opener.
func picker_mode() -> StringName:
	return _picker_mode


## "City of Bywater", or a neutral name when the scenario has no title.
static func campaign_title(session: SaveEditorSession) -> String:
	var campaign := session.content.campaign if session != null else null
	return campaign.title if campaign != null and not campaign.title.is_empty() else "This scenario"


func open_character_files() -> void:
	var rows: Array[Dictionary] = []
	var in_party := {}
	for member: SaveEditMember in _session.draft.members():
		if not member.dropped:
			in_party[member.state().name.to_lower()] = true
	for view: CharacterVaultRevisionView in _session.character_file_candidates():
		var reason := "In this save" if in_party.has(view.name.to_lower()) else "; ".join(view.eligibility_reasons) if not view.eligible else ""
		rows.append({"id": "%s|%s" % [view.character_id, view.revision_hash], "name": view.name, "detail": "Level %d · %s" % [view.level, view.publication_label if not view.publication_label.is_empty() else "Character File"], "reason": reason})
	_picker_mode = &"files"
	_picker.open("Add from Character Files", "A copy joins this save under %s's party rules. The Character File isn't changed." % campaign_title(_session), rows)


func open_allies() -> void:
	var rows: Array[Dictionary] = []
	var difficulty := PartySetupView.difficulty_name(_session.draft.state.difficulty)
	for definition: MonsterDefinition in _session.draft.ally_candidates():
		rows.append({"id": definition.id, "name": definition.name, "detail": "Hit dice %d · Armor %d · %d attack%s · joins at %s difficulty" % [definition.hit_dice, definition.armor, definition.attack_count, "" if definition.attack_count == 1 else "s", difficulty], "reason": ""})
	_picker_mode = &"ally"
	_picker.open("Add ally", "The creature is rolled once now with fresh dice at the current difficulty, as Classic adds an ally.", rows)


## Drops `member_id`. A member added in this draft simply leaves; a saved one asks first.
func request_drop(member_id: String) -> void:
	var member := _session.draft.member(member_id)
	if member == null:
		return
	_dialog_target = member.character_id
	if member.origin == SaveEditMember.ADDED:
		_drop(false)
		return
	var name := member.state().name
	_dialog.open("Drop %s from the party?" % name, "%s leaves this save when you save. You can keep them as a new Character File named \"%s · from %s Slot %s\"." % [name, name, campaign_title(_session), _session.slot_id], [], {
		&"secondary": {"id": &"cancel", "text": "Cancel"},
		&"tertiary": {"id": &"drop_only", "text": "Drop without keeping"},
		&"primary": {"id": &"drop_keep", "text": "Drop and keep in Files"},
	})


func request_discard() -> void:
	_dialog.open("Discard all changes?", "Every change is undone, including Level Ups, whose rolls are lost. The save stays as it was.", [], {
		&"secondary": {"id": &"cancel", "text": "Keep editing"},
		&"tertiary": {"id": &"discard", "text": "Discard changes"},
	})


## Leaves at once when nothing changed; otherwise asks, offering the review when saving is allowed.
func request_leave(change_count: int, can_save: bool) -> void:
	if _session == null:
		return
	if not _session.is_dirty():
		_session.close()
		return
	_dialog.open("Leave without saving?", "This save has %d unsaved change%s. Leaving discards %s, including any Level Up rolls." % [change_count, "" if change_count == 1 else "s", "it" if change_count == 1 else "them"], [], {
		&"secondary": {"id": &"cancel", "text": "Keep editing"},
		&"tertiary": {"id": &"leave", "text": "Discard and leave"},
		&"primary": {"id": &"review", "text": "Review and save…", "disabled": not can_save},
	})


## Lists every change ({label, detail}) and asks before writing the slot.
func request_review(changes: Array[Dictionary]) -> void:
	var rows: Array[Dictionary] = []
	for change: Dictionary in changes:
		rows.append({"label": RowFields.text(change, "label"), "text": RowFields.text(change, "detail")})
	_dialog.open("Save changes to Slot %s?" % _session.slot_id, "The edited adventure replaces the save in Slot %s. The current file becomes that slot's backup." % _session.slot_id, rows, {
		&"secondary": {"id": &"cancel", "text": "Keep editing"},
		&"primary": {"id": &"save", "text": "Save to Slot %s" % _session.slot_id},
	})


## Runs a dialog choice.
func dialog_chosen(action: StringName) -> void:
	match action:
		&"drop_keep": _drop(true)
		&"drop_only": _drop(false)
		&"discard":
			_session.discard()
			discarded.emit()
		&"leave": _session.close()
		&"review": review_requested.emit()
		&"save": _write()
		&"retry":
			if _session.retry_kept():
				_session.close("Slot %s saved." % _session.slot_id)
			else:
				_waiting_dialog("The Character File still wasn't created", _session.last_error)
		&"later": _session.close("Slot %s saved. A Character File is still waiting; retry it from Saved Adventures." % _session.slot_id, true)


func _picker_chosen(id: String) -> void:
	if _picker_mode == &"files":
		var parts := id.split("|")
		if _session.add_character(parts[0], parts[1]):
			var added := _session.draft.members()
			page_chosen.emit(added[added.size() - 1].character_id)
		applied.emit(_session.last_error.is_empty())
	elif _picker_mode == &"ally":
		applied.emit(_session.add_ally(id))
	_picker_mode = &""


func _drop(keep: bool) -> void:
	var dropped := _dialog_target
	if _session.drop_character(dropped, keep):
		page_chosen.emit(dropped if _session.draft.member(dropped) != null else "")
	applied.emit(_session.last_error.is_empty())


func _write() -> void:
	match _session.save():
		&"saved":
			_session.close("Slot %s saved." % _session.slot_id)
		&"kept_waiting":
			_waiting_dialog("Slot %s saved, but a Character File wasn't created" % _session.slot_id, "%s\n%s couldn't be kept in Character Files yet. The original save is held for them until you retry or let them go." % [_session.last_error, ", ".join(_session.waiting_names())])
		_:
			_dialog.open("The save wasn't written", "%s\nNothing changed on disk; your edits are still here." % _session.last_error, [], {
				&"secondary": {"id": &"cancel", "text": "Keep editing"},
			})


func _waiting_dialog(title: String, message: String) -> void:
	_dialog.open(title, message, [], {
		&"secondary": {"id": &"later", "text": "Later"},
		&"primary": {"id": &"retry", "text": "Retry"},
	})
