## Confirms character archival while keeping compositor input and vault focus usable.
class_name VaultArchiveConfirmation
extends ConfirmationDialog

signal archive_requested(character_id: String)

var _character_id := ""
var _opener: WeakRef


func _ready() -> void:
	confirmed.connect(_confirm_archive)
	canceled.connect(func() -> void: _character_id = "")
	visibility_changed.connect(_update_input_shield)
	get_parent().get_viewport().size_changed.connect(_update_input_shield)
	get_parent().visibility_changed.connect(func() -> void:
		if not get_parent().is_visible_in_tree(): hide())
	(%ArchiveInputShield as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			(%ArchiveInputShield as Control).accept_event()
			hide())


func present(character_id: String, character_name: String, opener: Control) -> void:
	_character_id = character_id
	_opener = weakref(opener)
	dialog_text = "Archive %s? Campaign saves are unchanged, and this revision can be restored later." % character_name
	var available := (get_parent().get_viewport().get_visible_rect().size - Vector2(32, 32)).max(Vector2.ONE)
	popup_centered(Vector2i(Vector2(480, 180).min(available)))
	get_cancel_button().grab_focus()


func _confirm_archive() -> void:
	var character_id := _character_id
	_character_id = ""
	if not character_id.is_empty(): archive_requested.emit(character_id)


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
