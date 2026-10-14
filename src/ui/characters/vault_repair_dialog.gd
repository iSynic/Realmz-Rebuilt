## Reviews explicit Character Files repair and retains visible backup and exit actions.
class_name VaultRepairDialog
extends ConfirmationDialog

signal operation_requested(operation: StringName)

var _review := false
var _has_backup := false
var _committing := false
var _opener: WeakRef


func _ready() -> void:
	dialog_hide_on_ok = false
	confirmed.connect(_confirm)
	canceled.connect(func() -> void:
		if not _committing: operation_requested.emit(&"cancel"))
	visibility_changed.connect(_update_shield)
	get_parent().get_viewport().size_changed.connect(_update_shield)
	get_parent().visibility_changed.connect(func() -> void:
		if not get_parent().is_visible_in_tree() and not _committing: hide())
	(%RepairInputShield as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			(%RepairInputShield as Control).accept_event()
			if not _committing: operation_requested.emit(&"cancel")
			if not _committing: hide())


func begin_review(opener: Control) -> void:
	_opener = weakref(opener)
	present("Checking Character Files and their exact source rules…", false, false, false)
	get_ok_button().disabled = true
	operation_requested.emit(&"review")


func present(details: String, review: bool, can_repair: bool, has_backup: bool) -> void:
	_committing = false
	_review = review
	_has_backup = has_backup
	(%RepairDetail as TextEdit).text = details
	get_ok_button().text = "Back up and repair" if review else "Open backup" if has_backup else "Done"
	get_ok_button().disabled = review and not can_repair
	get_cancel_button().text = "Cancel" if review else "Done"
	get_cancel_button().disabled = false
	var available := (get_parent().get_viewport().get_visible_rect().size - Vector2(32, 32)).max(Vector2.ONE)
	popup_centered(Vector2i(Vector2(640, 420).min(available)))
	get_cancel_button().grab_focus()


func committing() -> bool:
	return _committing


func _confirm() -> void:
	if _review:
		_committing = true
		(%RepairDetail as TextEdit).text = "Backing up the complete vault, then verifying repaired revisions…"
		get_ok_button().disabled = true
		get_cancel_button().disabled = true
		operation_requested.emit(&"repair")
	elif _has_backup:
		operation_requested.emit(&"open_backup")
	else:
		hide()


func _update_shield() -> void:
	var shield := %RepairInputShield as Control
	shield.visible = visible or _committing
	shield.global_position = Vector2.ZERO
	shield.size = get_parent().get_viewport().get_visible_rect().size
	if not visible and _committing:
		show.call_deferred()
	elif not visible:
		_restore_focus.call_deferred()


func _restore_focus() -> void:
	var opener := _opener.get_ref() as Control if _opener != null else null
	if opener != null and opener.is_visible_in_tree() and get_parent().is_visible_in_tree():
		opener.grab_focus()
	_opener = null
