## Binds detached campaign and save preview data to the saved-adventure browser.
class_name SavedAdventureBrowser
extends Control

signal campaign_selected(campaign_id: String)
signal save_selected(slot_id: String, backup: bool)
signal load_requested(slot_id: String, backup: bool)
signal legacy_load_requested(slot_id: String, backup: bool, replacement_slot: String)
signal refresh_requested
signal back_requested
signal update_requested(slot_id: String, backup: bool)

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
@onready var _update_button: Button = %UpdateSaveButton
@onready var _load_button: Button = %LoadButton

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


func _ready() -> void:
	_campaign_picker.item_selected.connect(_on_campaign_selected)
	_back.pressed.connect(func() -> void: back_requested.emit())
	_refresh_button.pressed.connect(func() -> void: refresh_requested.emit())
	_update_button.pressed.connect(_request_update)
	_load_button.pressed.connect(_request_load)
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
	_load_note.visible = preview != null and preview.can_load and not _progress_message.is_empty()
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
	_backups_toggle.text = "Hide backups  ▴" if _show_backups else "Show backups  ▾"
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
	%ReplaceConfirmation.hide()
	_render_saves()
	_render_selected_preview()
	save_selected.emit(preview.slot_id, preview.source == SaveSlotPreview.BACKUP)


func _render_selected_preview() -> void:
	var preview := _find_preview(_selected_key)
	if preview == null:
		_show_no_selection()
		return
	_selected_title.text = "Slot %s  ·  %s" % [preview.slot_id, preview.source_label()]
	_saved_time.text = Time.get_datetime_string_from_unix_time(preview.modified_unix) if preview.modified_unix > 0 else ""
	_saved_time.visible = not _saved_time.text.is_empty()
	_identity_status.text = preview.status_label()
	_identity_status.visible = preview.status != SaveSlotPreview.VALID
	_error.text = preview.error_message
	_error.visible = not preview.can_load and not preview.error_message.is_empty()
	var valid := preview.status == SaveSlotPreview.VALID
	_party.text = ", ".join(preview.character_names) if not preview.character_names.is_empty() else "No party members"
	_party.visible = valid
	_location.text = "Day %d  ·  %02d:%02d\n%s · %d, %d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute, preview.map_id, preview.coordinate.x, preview.coordinate.y]
	_location.visible = valid
	_map_preview.texture = null
	if valid and not preview.map_preview_jpeg.is_empty():
		var image := Image.new()
		if image.load_jpg_from_buffer(preview.map_preview_jpeg) == OK:
			_map_preview.texture = ImageTexture.create_from_image(image)
	_map_preview.visible = _map_preview.texture != null
	_map_preview_note.visible = not _map_preview.visible
	_map_preview_note.text = "Map preview unavailable." if valid else "A preview is not available for this save."
	_load_note.visible = not _progress_message.is_empty()
	_load_note.text = "You can load now; the adventure opens when ready." if not _progress_message.is_empty() else ""
	_progress.text = _progress_message
	_progress.visible = not _progress_message.is_empty()
	_refresh_selection_actions()


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
	_update_button.visible = preview != null and preview.can_update
	_update_button.disabled = preview == null or not preview.can_update
	_update_button.tooltip_text = "Create a verified copy and keep the original save and backup." if _update_button.visible else ""


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


func _request_update() -> void:
	var preview := _find_preview(_selected_key)
	if preview != null and preview.can_update:
		update_requested.emit(preview.slot_id, preview.source == SaveSlotPreview.BACKUP)


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
	var label := "Slot %s" % preview.slot_id
	if preview.source == SaveSlotPreview.BACKUP:
		label += "  ·  Backup"
	if preview.status == SaveSlotPreview.VALID:
		label += "  ·  Day %d  %02d:%02d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute]
	else:
		label += "  ·  %s" % preview.status_label()
	return label


func _preview_tooltip(preview: SaveSlotPreview) -> String:
	var details := "Slot %s · %s" % [preview.slot_id, preview.source_label()]
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
	var workspace_padding := (12.0 if compact else 20.0) * scale
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
	_save_list.custom_minimum_size.x = (240.0 if compact else 350.0) * scale
	_save_rows.add_theme_constant_override("separation", roundi(6.0 * scale))
	_map_preview.custom_minimum_size = Vector2(220.0 if compact else 240.0, 150.0 if compact else 160.0) * scale
	UiSizing.font_size(_title, &"font_size", 30 if not compact else 26)
	UiSizing.font_size(_campaign_label, &"font_size", 16)
	UiSizing.font_size(_campaign_picker, &"font_size", 18)
	UiSizing.font_size(_selected_title, &"font_size", 26)
	UiSizing.font_size(_saved_time, &"font_size", 17)
	UiSizing.font_size(_party, &"font_size", 19)
	UiSizing.font_size(_location, &"font_size", 18)
	UiSizing.font_size(_identity_status, &"font_size", 17)
	UiSizing.font_size(_progress, &"font_size", 17)
	UiSizing.font_size(_load_note, &"font_size", 16)
	UiSizing.font_size(_error, &"font_size", 15)
	UiSizing.font_size(_map_preview_note, &"font_size", 15)
	UiSizing.font_size(_back, &"font_size", 18)
	UiSizing.font_size(_backups_toggle, &"font_size", 16)
	UiSizing.font_size(_refresh_button, &"font_size", 18)
	UiSizing.font_size(_update_button, &"font_size", 18)
	UiSizing.font_size(_load_button, &"font_size", 18)
	UiSizing.minimum_size(_back, Vector2(110.0, 42.0))
	UiSizing.minimum_size(_refresh_button, Vector2(0.0, 42.0))
	UiSizing.minimum_size(_update_button, Vector2(0.0, 42.0))
	UiSizing.minimum_size(_load_button, Vector2(0.0, 42.0))
	UiSizing.minimum_size(_save_template, Vector2(0.0, 42.0 if not compact else 36.0))


@onready var _content: VBoxContainer = %WorkspaceContent
@onready var _heading: HBoxContainer = %Heading
@onready var _campaign_label: Label = %CampaignLabel
@onready var _main_columns: HBoxContainer = %MainColumns
@onready var _save_list: VBoxContainer = %SaveList
