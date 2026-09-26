## Confirms removal of an imported campaign without owning library storage.
class_name CampaignRemovalDialog
extends ConfirmationDialog

signal removal_confirmed(campaign_id: String)

var _campaign_id := ""


func _ready() -> void:
	confirmed.connect(func() -> void: removal_confirmed.emit(_campaign_id))
	visibility_changed.connect(_update_input_shield)
	get_parent().get_viewport().size_changed.connect(_update_input_shield)
	(%RemovalInputShield as Control).gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			(%RemovalInputShield as Control).accept_event()
			hide())


func _update_input_shield() -> void:
	# Exclusivity blocks the outer compositor, so the scene shield owns outside clicks.
	var shield := %RemovalInputShield as Control
	shield.visible = visible
	shield.global_position = Vector2.ZERO
	shield.size = get_parent().get_viewport().get_visible_rect().size


func present(campaign_id: String, display_name: String) -> void:
	_campaign_id = campaign_id
	dialog_text = "Remove %s and all its versions from Imported Scenarios?\n\nSaved adventures and their packages will be kept.\nAn already open adventure is unaffected.\nImport the scenario again to restore it to the list." % display_name
	popup_centered(Vector2i(440, 220))
