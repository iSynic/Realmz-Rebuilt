## Binds detached campaign and save preview data to the saved-adventure browser.
class_name SavedAdventureBrowser
extends Control

signal campaign_selected(campaign_id: String)
signal save_selected(slot_id: String, backup: bool)
signal load_requested(slot_id: String, backup: bool)
signal legacy_load_requested(slot_id: String, backup: bool, replacement_slot: String)
signal refresh_requested
signal back_requested
signal edit_requested(slot_id: String)
## The saves were listed again, so whether Edit save… is available must be checked again.
signal edit_check_needed
## Retry or give up a Character File that a save edit is still waiting on.
signal hold_retry_requested(hold_id: String)
signal hold_let_go_requested(hold_id: String, character_id: String)

@onready var _workspace: PanelContainer = %Workspace
@onready var _title: Label = %PageTitle
@onready var _back: Button = %BackButton
@onready var _campaign_picker: OptionButton = %CampaignPicker
@onready var _save_rows: VBoxContainer = %SaveRows
@onready var _save_template: Button = %SaveRowTemplate
@onready var _backups_toggle: Button = %BackupsToggle
@onready var _selected_title: Label = %SelectedSaveTitle
@onready var _saved_time: Label = %SavedTime
@onready var _party: Label = %SavedParty
@onready var _location: Label = %SavedLocation
@onready var _identity_status: Label = %IdentityStatus
@onready var _progress: Label = %LoadingProgress
@onready var _load_note: Label = %LoadNote
@onready var _error: Label = %SaveError
@onready var _map_preview: TextureRect = %MapPreview
@onready var _map_preview_note: Label = %MapPreviewNote
@onready var _refresh_button: Button = %RefreshButton
@onready var _load_button: Button = %LoadButton
@onready var _edit_button: Button = %EditButton
@onready var _edit_note: Label = %EditNote

var _campaigns: Array[CampaignPackageView] = []
var _previews: Array[SaveSlotPreview] = []
var _selected_campaign_id := ""
var _selected_key := ""
var _show_backups := false
var _progress_message := ""
var _layout_profile: UiLayoutProfile
var _selection_group := ButtonGroup.new()
var _row_buttons: Dictionary = {}
var _base_workspace_style: StyleBox
## Why Edit save… is unavailable for the selected save, or "" once it can open.
var _edit_reason := "Select a save to edit."
var _hold: Dictionary = {}
var _hidden_holds: Dictionary = {}


func _ready() -> void:
	_campaign_picker.item_selected.connect(_on_campaign_selected)
	_back.pressed.connect(func() -> void: back_requested.emit())
	_refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	_load_button.pressed.connect(_request_load)
	_edit_button.pressed.connect(_request_edit)
	visibility_changed.connect(_on_visibility_changed)
	%HoldRetry.pressed.connect(func() -> void: hold_retry_requested.emit(String(_hold.get("holdId", ""))))
	%HoldHide.pressed.connect(_hide_hold)
	%HoldLetGo.pressed.connect(_confirm_let_go)
	%HoldKeep.pressed.connect(func() -> void:
		%HoldConfirm.hide()
		%HoldLetGo.grab_focus()
	)
	%HoldConfirmLetGo.pressed.connect(func() -> void:
		%HoldConfirm.hide()
		hold_let_go_requested.emit(String(_hold.get("holdId", "")), String(_hold.get("characterId", "")))
	)
	_backups_toggle.pressed.connect(_toggle_backups)
	%ReplaceCancel.pressed.connect(func() -> void: %ReplaceConfirmation.hide())
	%ReplaceLoad.pressed.connect(_confirm_replacement)
	for slot: String in SaveSlotPreview.SCENARIO_SLOTS: %ReplaceSlot.add_item("Slot " + slot)
	_save_template.visible = false
	if UiSizing.profile_for(self) != null:
		_layout_profile = UiSizing.profile_for(self)
	if _layout_profile != null:
		UiSizing.apply(self, _layout_profile)
	_fit_layout()
	_render_campaigns()
	_render_saves()
	_show_no_selection()


func set_campaigns(rows: Array[CampaignPackageView], selected_campaign_id: String) -> void:
	_campaigns = rows.duplicate()
	_selected_campaign_id = selected_campaign_id
	_render_campaigns()


func set_previews(previews: Array[SaveSlotPreview], selected_key: String) -> void:
	_previews = previews.duplicate()
	_selected_key = selected_key if _find_preview(selected_key) != null else ""
	_edit_reason = "Select a save to edit." if _selected_key.is_empty() else "Checking this save…"
	if not _selected_key.is_empty():
		edit_check_needed.emit()
	if _selected_key.ends_with(":backup"):
		_show_backups = true
	_render_saves()
	_render_selected_preview()


func set_progress(message: String) -> void:
	_progress_message = message.strip_edges()
	_progress.text = _progress_message
	_progress.visible = not _progress_message.is_empty()
	_load_note.text = "You can load now; the adventure opens when ready."
	var preview := _find_preview(_selected_key)
	# The reassurance matters only while the scenario still prepares; once ready it repeats the status.
	_load_note.visible = preview != null and preview.can_load and not _progress_message.is_empty() and not _progress_message.begins_with("Ready")
	_refresh_selection_actions()


func set_layout_profile(profile: UiLayoutProfile) -> void:
	_layout_profile = profile
	if is_node_ready():
		UiSizing.apply(self, profile)
		_fit_layout()


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	_layout_profile = profile
	_fit_layout()


func handle_back() -> bool:
	if %ReplaceConfirmation.visible:
		%ReplaceConfirmation.hide()
		_load_button.grab_focus()
		return true
	if _campaign_picker.get_popup().visible:
		_campaign_picker.get_popup().hide()
		return true
	back_requested.emit()
	return true


func _render_campaigns() -> void:
	_campaign_picker.clear()
	_campaign_picker.add_item("Choose a scenario")
	_campaign_picker.set_item_metadata(0, "")
	var selected_index := 0
	for campaign: CampaignPackageView in _campaigns:
		var title := campaign.display_name if not campaign.display_name.is_empty() else campaign.campaign_id
		_campaign_picker.add_item(title)
		var index := _campaign_picker.item_count - 1
		_campaign_picker.set_item_metadata(index, campaign.campaign_id)
		if campaign.campaign_id == _selected_campaign_id:
			selected_index = index
	_campaign_picker.select(selected_index)
	_campaign_picker.disabled = _campaigns.is_empty()
	_campaign_picker.tooltip_text = "Choose which campaign's saved adventures to browse." if not _campaigns.is_empty() else "No installed campaigns are available."


func _on_campaign_selected(index: int) -> void:
	if index <= 0 or index >= _campaign_picker.item_count:
		return
	var campaign_id := String(_campaign_picker.get_item_metadata(index))
	if campaign_id == _selected_campaign_id:
		return
	_selected_campaign_id = campaign_id
	%ReplaceConfirmation.hide()
	campaign_selected.emit(campaign_id)


func _render_saves() -> void:
	_row_buttons.clear()
	for child: Node in _save_rows.get_children():
		if child == _save_template:
			continue
		_save_rows.remove_child(child)
		child.queue_free()
	var ordered := _previews.duplicate()
	ordered.sort_custom(_preview_before)
	var backups := _previews.filter(func(preview: SaveSlotPreview) -> bool: return preview.source == SaveSlotPreview.BACKUP)
	_backups_toggle.visible = not backups.is_empty()
	_backups_toggle.text = "Hide backups" if _show_backups else "Show backups"
	_backups_toggle.set_pressed_no_signal(_show_backups)
	for preview: SaveSlotPreview in ordered:
		if preview.source == SaveSlotPreview.BACKUP and not _show_backups:
			continue
		var row := _save_template.duplicate() as Button
		row.name = "Save_%s_%s" % [preview.slot_id.validate_node_name(), String(preview.source).validate_node_name()]
		row.unique_name_in_owner = false
		row.visible = true
		row.button_group = _selection_group
		row.set_pressed_no_signal(_key(preview) == _selected_key)
		row.text = _preview_row_text(preview)
		row.tooltip_text = _preview_tooltip(preview)
		row.pressed.connect(_select_preview.bind(_key(preview)))
		_save_rows.add_child(row)
		_row_buttons[_key(preview)] = row
	_refresh_selection_actions()


func _select_preview(key: String) -> void:
	var preview := _find_preview(key)
	if preview == null or key == _selected_key:
		return
	_selected_key = key
	_edit_reason = "Checking this save…"
	%ReplaceConfirmation.hide()
	_render_saves()
	_render_selected_preview()
	save_selected.emit(preview.slot_id, preview.source == SaveSlotPreview.BACKUP)


func _render_selected_preview() -> void:
	var preview := _find_preview(_selected_key)
	if preview == null:
		_show_no_selection()
		return
	_selected_title.text = "%s  ·  %s" % [SaveSlotPreview.title_for(preview.slot_id), preview.source_label()]
	_saved_time.text = "Saved %s" % saved_when(preview.modified_unix) if preview.modified_unix > 0 else ""
	_saved_time.visible = not _saved_time.text.is_empty()
	_identity_status.text = preview.status_label()
	_identity_status.visible = preview.status != SaveSlotPreview.VALID
	_error.text = preview.error_message
	_error.visible = not preview.can_load and not preview.error_message.is_empty()
	var valid := preview.status == SaveSlotPreview.VALID
	_party.text = ", ".join(preview.character_names) if not preview.character_names.is_empty() else "No party members"
	_party.visible = valid
	_location.text = "Day %d  ·  %02d:%02d  ·  at %d, %d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute, preview.coordinate.x, preview.coordinate.y]
	_location.visible = valid
	_map_preview.texture = null
	if valid:
		_map_preview.texture = MapPreviewImage.texture(preview.map_preview_jpeg)
	_map_preview.visible = _map_preview.texture != null
	_map_preview_note.visible = not _map_preview.visible
	_map_preview_note.text = "Map preview unavailable." if valid else "A preview is not available for this save."
	_load_note.visible = not _progress_message.is_empty() and not _progress_message.begins_with("Ready")
	_load_note.text = "You can load now; the adventure opens when ready." if _load_note.visible else ""
	_progress.text = _progress_message
	_progress.visible = not _progress_message.is_empty()
	_refresh_selection_actions()


## "Oct 17, 2026, 5:48 AM" in local time.
static func saved_when(unix: int) -> String:
	var local := Time.get_datetime_dict_from_unix_time(unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var hour := int(local.hour)
	return "%s %d, %d, %d:%02d %s" % [months[int(local.month) - 1], local.day, local.year, (hour + 11) % 12 + 1, local.minute, "AM" if hour < 12 else "PM"]


func _show_no_selection() -> void:
	_selected_title.text = "Select a saved adventure"
	_saved_time.text = ""
	_saved_time.hide()
	_party.text = ""
	_party.hide()
	_location.text = ""
	_location.hide()
	_identity_status.text = ""
	_identity_status.hide()
	_progress.text = _progress_message
	_progress.visible = not _progress_message.is_empty()
	_error.text = ""
	_error.hide()
	_map_preview.texture = null
	_map_preview.hide()
	_map_preview_note.text = "Choose a save to see its map preview."
	_map_preview_note.show()
	_load_note.text = ""
	_load_note.hide()
	_refresh_selection_actions()


func _refresh_selection_actions() -> void:
	var preview := _find_preview(_selected_key)
	_load_button.disabled = preview == null or not preview.can_load
	_load_button.tooltip_text = "Select a validated save to load." if preview == null else preview.error_message if not preview.can_load else "Load this saved adventure."
	var reason := _edit_reason
	if preview != null and preview.source == SaveSlotPreview.BACKUP:
		reason = "Load this backup and save it to a slot to edit it."
	_edit_button.disabled = not reason.is_empty()
	_edit_button.tooltip_text = reason if not reason.is_empty() else "Change this save's difficulty, monsters, party and allies. When you save, the current file becomes the slot's backup."
	_edit_note.text = reason if preview != null else ""
	_edit_note.visible = not _edit_note.text.is_empty()


## Whether the selected primary save can open in the save editor; `reason` explains when not.
func set_edit_state(reason: String) -> void:
	_edit_reason = reason
	_refresh_selection_actions()


## `hold`: {holdId, slot, characterId, names} for the first waiting Character File, or {}.
func set_hold(hold: Dictionary) -> void:
	_hold = hold
	%HoldConfirm.hide()
	var shown := not hold.is_empty() and not _hidden_holds.has(String(hold.holdId))
	%HoldNotice.visible = shown
	if shown:
		var others := int(hold.get("otherHolds", 0))
		var many := int(hold.get("waiting", 1)) > 1
		var still_in_slot := bool(hold.get("stillInSlot", false))
		if still_in_slot:
			%HoldText.text = "Slot %s still has %s, so the edit that dropped %s wasn't saved and no Character File is needed. Let %s go to remove the held copy." % [hold.slot, hold.names, "them" if many else hold.firstName, "them" if many else hold.firstName]
		else:
			%HoldText.text = "%s left Slot %s but %s in Character Files yet. A copy of the save from before the edit is held until %s." % [hold.names, hold.slot, "aren't" if many else "isn't", "their files exist" if many else "the file exists"]
		%HoldRetry.visible = not still_in_slot
		if others > 0:
			%HoldText.text += " %d more held save%s follow%s once this one is settled." % [others, "" if others == 1 else "s", "s" if others == 1 else ""]
		%HoldLetGo.text = "Let %s go…" % hold.firstName


## Hide lasts for this visit to Saved Adventures; the notice returns the next time it opens.
func _on_visibility_changed() -> void:
	if visible:
		_hidden_holds.clear()


func _hide_hold() -> void:
	_hidden_holds[String(_hold.get("holdId", ""))] = true
	%HoldNotice.hide()
	_load_button.grab_focus()


func _confirm_let_go() -> void:
	var last := int(_hold.get("waiting", 1)) <= 1
	%HoldConfirmText.text = "Let %s go? %s won't be kept in Character Files%s" % [_hold.firstName, _hold.firstName, ", and the held save is deleted." if last else ". The held save stays for the others still waiting."]
	%HoldConfirm.show()
	%HoldKeep.grab_focus()


func _request_edit() -> void:
	var preview := _find_preview(_selected_key)
	if preview != null and preview.source == SaveSlotPreview.PRIMARY and _edit_reason.is_empty():
		edit_requested.emit(preview.slot_id)


func _request_load() -> void:
	var preview := _find_preview(_selected_key)
	if preview != null and preview.can_load:
		if preview.slot_id in ["quick", "quick-2"] and not _has_empty_slot():
			%ReplaceConfirmation.show()
			%ReplaceSlot.grab_focus()
			return
		load_requested.emit(preview.slot_id, preview.source == SaveSlotPreview.BACKUP)


func _has_empty_slot() -> bool:
	for slot: String in SaveSlotPreview.SCENARIO_SLOTS:
		if _find_preview(slot + ":primary") == null and _find_preview(slot + ":backup") == null: return true
	return false


func _confirm_replacement() -> void:
	var preview := _find_preview(_selected_key)
	if preview == null or not preview.can_load or not preview.slot_id in ["quick", "quick-2"]: return
	var slot := SaveSlotPreview.SCENARIO_SLOTS.substr(%ReplaceSlot.selected, 1)
	%ReplaceConfirmation.hide()
	legacy_load_requested.emit(preview.slot_id, preview.source == SaveSlotPreview.BACKUP, slot)


func _toggle_backups() -> void:
	_show_backups = not _show_backups
	_render_saves()


func _find_preview(key: String) -> SaveSlotPreview:
	if key.is_empty():
		return null
	for preview: SaveSlotPreview in _previews:
		if _key(preview) == key:
			return preview
	return null


func _preview_row_text(preview: SaveSlotPreview) -> String:
	# Long pinned slot names are shortened (the tooltip has them whole), and the day and time never
	# split across lines.
	var label := SaveSlotPreview.title_for(preview.slot_id)
	if preview.source == SaveSlotPreview.BACKUP:
		label += "  ·  Backup"
	if preview.status == SaveSlotPreview.VALID:
		label += "  ·  Day\u00a0%d\u00a0\u00a0%02d:%02d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute]
	else:
		label += "  ·  %s" % preview.status_label()
	return label


func _preview_tooltip(preview: SaveSlotPreview) -> String:
	var details := "%s · %s" % [SaveSlotPreview.title_for(preview.slot_id), preview.source_label()]
	if preview.can_load:
		details += "\n%s · Day %d %02d:%02d" % [preview.map_id, preview.realmz_day, preview.realmz_hour, preview.realmz_minute]
	elif not preview.error_message.is_empty():
		details += "\n%s" % preview.error_message
	return details


func _preview_before(left: SaveSlotPreview, right: SaveSlotPreview) -> bool:
	var left_index := SaveSlotPreview.SCENARIO_SLOTS.find(left.slot_id)
	var right_index := SaveSlotPreview.SCENARIO_SLOTS.find(right.slot_id)
	if left_index < 0: left_index = SaveSlotPreview.SCENARIO_SLOTS.length()
	if right_index < 0: right_index = SaveSlotPreview.SCENARIO_SLOTS.length()
	if left_index != right_index: return left_index < right_index
	if left.slot_id != right.slot_id: return left.slot_id.naturalnocasecmp_to(right.slot_id) < 0
	return left.source == SaveSlotPreview.PRIMARY and right.source == SaveSlotPreview.BACKUP


func _key(preview: SaveSlotPreview) -> String:
	return "%s:%s" % [preview.slot_id, String(preview.source)]


func _fit_layout() -> void:
	if not is_node_ready():
		return
	var scale := _layout_profile.ui_scale if _layout_profile != null else 1.0
	var compact := _layout_profile.id == UiLayoutProfile.COMPACT if _layout_profile != null else size.x < 1280.0 or size.y < 720.0
	if _base_workspace_style == null:
		_base_workspace_style = _workspace.get_theme_stylebox("panel").duplicate() as StyleBox
	var workspace_style := _base_workspace_style.duplicate() as StyleBox
	var workspace_padding := (8.0 if compact else 12.0) * scale
	workspace_style.content_margin_left = workspace_padding
	workspace_style.content_margin_top = workspace_padding
	workspace_style.content_margin_right = workspace_padding
	workspace_style.content_margin_bottom = workspace_padding
	_workspace.add_theme_stylebox_override("panel", workspace_style)
	_workspace.offset_left = 20.0 * scale
	_workspace.offset_top = 16.0 * scale
	_workspace.offset_right = -20.0 * scale
	_workspace.offset_bottom = -16.0 * scale
	_content.add_theme_constant_override("separation", roundi((10.0 if compact else 16.0) * scale))
	_heading.add_theme_constant_override("separation", roundi(20.0 * scale))
	_main_columns.add_theme_constant_override("separation", roundi((16.0 if compact else 28.0) * scale))
	_save_list.custom_minimum_size.x = (250.0 if compact else 360.0) * scale
	_save_rows.add_theme_constant_override("separation", roundi(6.0 * scale))
	_map_preview.custom_minimum_size = Vector2(220.0 if compact else 240.0, 150.0 if compact else 160.0) * scale
	UiSizing.font_size(_title, &"font_size", 26 if not compact else 22)
	UiSizing.font_size(_campaign_label, &"font_size", 13)
	UiSizing.font_size(_campaign_picker, &"font_size", 15)
	UiSizing.minimum_size(_campaign_picker, Vector2(240.0 if compact else 320.0, 38.0))
	UiSizing.font_size(_selected_title, &"font_size", 22 if not compact else 19)
	UiSizing.font_size(_saved_time, &"font_size", 13)
	UiSizing.font_size(_party, &"font_size", 17 if not compact else 15)
	UiSizing.font_size(_location, &"font_size", 15)
	UiSizing.font_size(_identity_status, &"font_size", 15)
	UiSizing.font_size(_progress, &"font_size", 15)
	UiSizing.font_size(_load_note, &"font_size", 13)
	UiSizing.font_size(_error, &"font_size", 14)
	UiSizing.font_size(_map_preview_note, &"font_size", 13)
	UiSizing.font_size(_save_template, &"font_size", 15 if not compact else 14)
	for button: Button in [_back, _backups_toggle, _refresh_button, _load_button, _edit_button]:
		UiSizing.font_size(button, &"font_size", 14)
	UiSizing.minimum_size(_back, Vector2(0.0, 36.0))
	UiSizing.minimum_size(_refresh_button, Vector2(110.0, 40.0))
	UiSizing.minimum_size(_edit_button, Vector2(140.0, 40.0))
	UiSizing.minimum_size(_load_button, Vector2(160.0, 40.0))
	UiSizing.minimum_size(_save_template, Vector2(0.0, 42.0 if not compact else 36.0))


@onready var _content: VBoxContainer = %WorkspaceContent
@onready var _heading: HBoxContainer = %Heading
@onready var _campaign_label: Label = %CampaignLabel
@onready var _main_columns: HBoxContainer = %MainColumns
@onready var _save_list: VBoxContainer = %SaveList
