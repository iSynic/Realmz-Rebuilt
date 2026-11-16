## Confirms archiving or permanently deleting a character while keeping compositor input and vault focus usable.
class_name VaultArchiveConfirmation
extends ConfirmationDialog

signal change_confirmed(operation: StringName, character_id: String)

var _operation: StringName = &""
var _character_id := ""
var _opener: WeakRef


func _ready() -> void:
	confirmed.connect(_confirm_change)
	canceled.connect(_clear)
	visibility_changed.connect(_update_input_shield)
	get_parent().get_viewport().size_changed.connect(_update_input_shield)
	get_parent().visibility_changed.connect(func() -> void:
		if not get_parent().is_visible_in_tree(): hide())
	(%ArchiveInputShield as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			(%ArchiveInputShield as Control).accept_event()
			hide())


func present(operation: StringName, character_id: String, character_name: String, revision_count: int, opener: Control) -> void:
	_operation = operation
	_character_id = character_id
	_opener = weakref(opener)
	var deleting := operation == &"delete"
	title = "Delete character permanently" if deleting else "Archive character"
	ok_button_text = "Delete permanently" if deleting else "Archive"
	get_ok_button().theme_type_variation = &"DangerFillAction" if deleting else &"PrimaryAction"
	get_cancel_button().theme_type_variation = &"FieldAction"
	var revisions := "their only revision" if revision_count == 1 else "all %d of their revisions" % revision_count
	if deleting:
		dialog_text = "Delete %s and %s from Character Files? This can't be undone. Saved adventures are not changed." % [character_name, revisions]
	else:
		dialog_text = "Archive %s? They'll be hidden from party setup. Saved adventures are unchanged, and every revision can be restored later." % character_name
	var available := (get_parent().get_viewport().get_visible_rect().size - Vector2(32, 32)).max(Vector2.ONE)
	# Wrapped controls grow the height to the message, so the dialog never carries empty space.
	popup_centered(Vector2i(int(minf(500.0, available.x)), 1))
	get_cancel_button().grab_focus()


## True while the open prompt still applies: its character exists in the expected state.
func still_applies(entries: Array[VaultEntry]) -> bool:
	for entry: VaultEntry in entries:
		if entry.character_id == _character_id:
			return entry.archived == (_operation == &"delete")
	return false


func _confirm_change() -> void:
	var operation := _operation
	var character_id := _character_id
	_clear()
	# The opener now belongs to the next character; the vault focuses the refreshed selection.
	_opener = null
	if not character_id.is_empty(): change_confirmed.emit(operation, character_id)


func _clear() -> void:
	_operation = &""
	_character_id = ""


func _update_input_shield() -> void:
	# Native exclusivity prevents the outer compositor from forwarding input.
	var shield := %ArchiveInputShield as Control
	shield.visible = visible
	shield.global_position = Vector2.ZERO
	shield.size = get_parent().get_viewport().get_visible_rect().size
	if not visible: _restore_focus.call_deferred()


func _restore_focus() -> void:
	var opener := _opener.get_ref() as Control if _opener != null else null
	if get_parent().is_visible_in_tree() and opener != null and not opener.is_queued_for_deletion() and opener.is_visible_in_tree():
		opener.grab_focus()
	_opener = null
