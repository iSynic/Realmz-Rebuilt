## Opens the save editor from Saved Adventures and keeps its Edit save… availability and
## waiting-Character-File notice current for the selected save.

class_name SaveEditorWorkflow
extends RefCounted

var _saves: SaveHostController
var _vault: CharacterVaultController
var _holds: SaveEditHolds
var _navigator: ScreenNavigator
var _preparation: CampaignPreparationWorkflow
var _media: PresentationMediaController
## The browser selection and prepared revision last checked, so each is checked once.
var _checked := ""
var _holds_campaign := "-"


func _init(saves: SaveHostController, vault: CharacterVaultController, holds: SaveEditHolds, navigator: ScreenNavigator, preparation: CampaignPreparationWorkflow, media: PresentationMediaController) -> void:
	_saves = saves
	_vault = vault
	_holds = holds
	_navigator = navigator
	_preparation = preparation
	_media = media
	var browser := navigator.startup.browser
	browser.edit_requested.connect(open_editor)
	browser.edit_check_needed.connect(func() -> void: _checked = "")
	browser.hold_retry_requested.connect(_retry_hold)
	browser.hold_let_go_requested.connect(_let_go)
	navigator.startup.browser_requested.connect(func(_from_setup: bool) -> void:
		_checked = ""
		_holds_campaign = "-"
	)


## Called every frame: rechecks Edit save… when the selection or its prepared revision changes.
func poll() -> void:
	var startup := _navigator.startup
	if not startup.browser.visible or startup.save_editor_open():
		return
	var selection := _preparation.browser_selection()
	var prepared := _preparation.edit_candidate()
	var key := "%s|%s|%s" % [selection[0], selection[1], prepared.content.package_hash if prepared != null else _preparation.edit_blocker()]
	if selection[0] != _holds_campaign:
		_holds_campaign = selection[0]
		_show_hold()
	if key == _checked:
		return
	_checked = key
	startup.browser.set_edit_state(_edit_reason(prepared, selection[1]))


func open_editor(slot_id: String) -> void:
	var prepared := _preparation.edit_candidate()
	if prepared == null:
		_navigator.startup.browser.set_edit_state(_preparation.edit_blocker())
		return
	var session := SaveEditorSession.new(_saves, _vault, _holds, prepared.content, slot_id)
	if not session.open():
		_navigator.startup.browser.set_edit_state(session.last_error)
		return
	session.closed.connect(_editor_closed)
	_navigator.startup.show_save_editor(session, _media.catalog_for(prepared.media), _navigator.startup.save_editor_compact())


func _edit_reason(prepared: PreparedPackage, selected_key: String) -> String:
	if selected_key.is_empty():
		return "Select a save to edit."
	if selected_key.ends_with(":backup"):
		return "Load this backup and save it to a slot to edit it."
	if prepared == null:
		return _preparation.edit_blocker()
	var probe := SaveEditorSession.new(_saves, _vault, _holds, prepared.content, selected_key.get_slice(":", 0))
	return "" if probe.open() else probe.last_error


func _editor_closed(message: String, _is_error: bool) -> void:
	_navigator.startup.close_save_editor()
	_checked = ""
	_holds_campaign = "-"
	_preparation.refresh_browser()
	if not message.is_empty():
		_navigator.startup.browser.set_progress(message)


func _show_hold() -> void:
	var waiting: Array[SaveHold] = []
	if not _holds_campaign.is_empty():
		waiting = _holds.holds(_holds_campaign)
	if waiting.is_empty():
		_navigator.startup.browser.set_hold({})
		return
	var hold: SaveHold = waiting[0]
	_navigator.startup.browser.set_hold({
		"holdId": hold.hold_id,
		"slot": hold.slot_id,
		"characterId": hold.character_ids[0],
		"firstName": hold.character_names[0],
		"names": " and ".join(hold.character_names),
		"waiting": hold.character_ids.size(),
		# Worked out from the slot, never stored, so it stays true whenever a write was interrupted.
		"stillInSlot": _still_in_slot(hold),
		"otherHolds": waiting.size() - 1,
	})


## True when the slot's latest save still has every held character: the edit never left the slot,
## so Retry would only duplicate them and letting them go is the right step.
func _still_in_slot(hold: SaveHold) -> bool:
	for preview: SaveSlotPreview in _saves.campaign_previews(hold.campaign_id):
		if preview.slot_id == hold.slot_id and preview.source == SaveSlotPreview.PRIMARY:
			return hold.character_names.all(func(name: String) -> bool: return preview.character_names.has(name))
	return false


func _find_hold(hold_id: String) -> SaveHold:
	for hold: SaveHold in _holds.holds(_holds_campaign):
		if hold.hold_id == hold_id:
			return hold
	return null


func _retry_hold(hold_id: String) -> void:
	var hold := _find_hold(hold_id)
	var prepared := _preparation.edit_candidate()
	if hold == null:
		_show_hold()
		return
	if _still_in_slot(hold):
		_navigator.startup.browser.set_progress("Slot %s still has %s, so no Character File is needed. Let them go to remove the held copy." % [hold.slot_id, " and ".join(hold.character_names)])
		return
	if prepared == null or prepared.content.package_hash != hold.package_hash:
		_navigator.startup.browser.set_progress("Select Slot %s's save and wait for it to prepare, then retry." % hold.slot_id)
		return
	var done := _holds.settle(prepared.content, hold)
	_navigator.startup.browser.set_progress("%s is now in Character Files." % " and ".join(hold.character_names) if done else "The Character File still wasn't created • %s" % _holds.last_error)
	_show_hold()


func _let_go(hold_id: String, character_id: String) -> void:
	var hold := _find_hold(hold_id)
	if hold == null:
		_show_hold()
		return
	var name := hold.name_of(character_id)
	_navigator.startup.browser.set_progress("%s was let go." % name if _holds.let_go(hold, character_id) else _holds.last_error)
	_show_hold()
