## Owns Save & Load selection, details, confirmations, and typed save actions.
class_name SaveWorkspaceController
extends RefCounted

signal action_requested(action_id: StringName, value: Variant)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")

var _save_previews: Array[SaveSlotPreview] = []
var _selected_save_key: String = ""
var _active_slot_id: String = "A"
var active_slot_id: String:
	get: return _active_slot_id
var active_quick_preview: SaveSlotPreview:
	get: return _preview_for_slot(_active_slot_id, SaveSlotPreview.PRIMARY)
var _pending_save_action: StringName = &""
var _pending_save_slot: String = ""
var _pending_save_backup: bool = false
var _legacy_target_slot: String = ""
var _save_view_has_active_adventure: bool = false
var _save_and_quit_mode: bool = false
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _workspace: SystemWorkspace

func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id

func present(workspace: SystemWorkspace, view: GameView, clear_pending_on_workspace_change: bool) -> void:
	if workspace == null:
		return
	if clear_pending_on_workspace_change and _workspace != workspace:
		_pending_save_action = &""
	_workspace = workspace
	if view == null or not view.session_started:
		return
	_bind_save_workspace(view)

func set_save_previews(previews: Array[SaveSlotPreview], selected_slot_id: String = "", active_slot_id: String = "A") -> void:
	_save_previews = previews.duplicate()
	_active_slot_id = active_slot_id if active_slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(active_slot_id) else "A"
	if not selected_slot_id.is_empty():
		for preview: SaveSlotPreview in _save_previews:
			if preview.slot_id == selected_slot_id and preview.source == SaveSlotPreview.PRIMARY:
				_selected_save_key = _key(preview)
				break
	if _selected_save_key.is_empty() or (not _selected_save_key.begins_with(_active_slot_id + ":") and not _save_previews.any(func(preview: SaveSlotPreview) -> bool: return _key(preview) == _selected_save_key)):
		_selected_save_key = _active_slot_id + ":primary"
	if not selected_slot_id.is_empty():
		_refresh_save_detail()


func set_save_and_quit_mode(enabled: bool) -> void:
	if enabled and not _save_and_quit_mode:
		_selected_save_key = _active_slot_id + ":primary"
	_save_and_quit_mode = enabled


func _bind_save_workspace(view: GameView) -> void:
	_save_view_has_active_adventure = view.session_started and not view.party_setup_available
	var rows := _workspace.save_slot_rows()
	var empty := _workspace.save_browser_empty()
	empty.visible = false
	(_workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/ActiveSlotLabel") as Label).text = ("Slot %s active · Quick Save: %s" if _layout_profile == UiLayoutProfile.COMPACT else "Slot %s active · Quick Save overwrites %s") % [_active_slot_id, _active_slot_id]
	if view.party_setup_available and _selected_preview() == null:
		for existing: SaveSlotPreview in _save_previews:
			if existing.can_load and existing.source == SaveSlotPreview.PRIMARY:
				_selected_save_key = _key(existing)
				break
	var group := ButtonGroup.new()
	for slot_index: int in SaveSlotPreview.SCENARIO_SLOTS.length():
		var slot_id := SaveSlotPreview.SCENARIO_SLOTS.substr(slot_index, 1)
		var primary := _preview_for_slot(slot_id, SaveSlotPreview.PRIMARY)
		var button := rows.get_node("SavePreview_%s_primary" % slot_id) as Button
		button.text = "Slot %s%s  ·  %s" % [slot_id, "  ★" if slot_id == _active_slot_id else "", primary.status_label() if primary != null else "Empty"]
		button.button_group = group
		button.button_pressed = _selected_save_key == slot_id + ":primary"
		SystemSignalBinding.clear_pressed(button)
		button.pressed.connect(_select_save_key.bind(slot_id + ":primary"))
		var backup := _preview_for_slot(slot_id, SaveSlotPreview.BACKUP)
		if backup != null:
			var backup_row := _add_save_preview_row(rows, group, backup, "   ↳ Backup · %s" % backup.status_label())
			rows.move_child(backup_row, button.get_index() + 1)
	for preview: SaveSlotPreview in _save_previews:
		if preview.slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(preview.slot_id):
			continue
		_add_save_preview_row(rows, group, preview, "Earlier save · %s · %s" % [SystemPreferencesLayout.slot_label(preview.slot_id), preview.source_label()])
	_bind_save_footer(view)
	_refresh_save_detail()


func _add_save_preview_row(rows: VBoxContainer, group: ButtonGroup, preview: SaveSlotPreview, label: String) -> Button:
	var button := _workspace.save_slot_row_scene.instantiate() as Button
	button.name = "SavePreview_%s_%s" % [preview.slot_id, String(preview.source)]
	button.text = label
	button.button_group = group
	button.button_pressed = _key(preview) == _selected_save_key
	button.pressed.connect(_select_save_key.bind(_key(preview)))
	rows.add_child(button)
	return button


func _preview_for_slot(slot_id: String, source: StringName) -> SaveSlotPreview:
	for preview: SaveSlotPreview in _save_previews:
		if preview.slot_id == slot_id and preview.source == source:
			return preview
	return null


func _bind_save_footer(view: GameView) -> void:
	var root := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter") as VBoxContainer
	var actions := root.get_node("SaveWorkspaceActions") as Container
	var save_and_quit := actions.get_node("SaveAndQuitSelected") as Button
	var quick_one := actions.get_node("QuickSave1") as Button
	var quick_two := actions.get_node("QuickSave2") as Button
	var save_selected := actions.get_node("SaveSelectedSlot") as Button
	var load_selected := actions.get_node("LoadSelectedSave") as Button
	var update_save := actions.get_node("UpdateSave") as Button
	var refresh := actions.get_node("RefreshSaves") as Button
	var main_menu := actions.get_node("MainMenu") as Button
	var new_row := root.get_node("NewSaveSlotRow") as BoxContainer
	var confirm_row := root.get_node("ConfirmActionRow") as BoxContainer
	_bind_action(confirm_row.get_node("Confirm") as Button, _confirm_save_action)
	_bind_action(confirm_row.get_node("Cancel") as Button, _clear_save_confirmation)
	_update_save_confirmation()
	var ordinary_save := not _save_and_quit_mode and not view.party_setup_available
	save_and_quit.visible = _save_and_quit_mode
	quick_one.visible = ordinary_save
	quick_two.visible = false
	save_selected.visible = ordinary_save
	new_row.visible = false
	_bind_action(save_and_quit, func() -> void: _save_selected_and_quit())
	_bind_action(quick_one, func() -> void: action_requested.emit(&"save", "quick"))
	quick_one.text = "Quick Save · %s" % _active_slot_id
	_bind_action(save_selected, func() -> void: _save_selected_preview())
	_bind_action(load_selected, func() -> void: _load_selected_preview())
	_bind_action(update_save, func() -> void:
		var preview := _selected_preview()
		if preview != null and preview.can_update:
			action_requested.emit(&"update_save", {"slotId": preview.slot_id, "backup": preview.source == SaveSlotPreview.BACKUP})
	)
	_bind_action(refresh, func() -> void: action_requested.emit(&"refresh_saves", null))
	_bind_action(main_menu, func() -> void: action_requested.emit(&"end_adventure", null))
	save_and_quit.tooltip_text = "Save to the selected slot, then quit Realmz Rebuilt."
	main_menu.disabled = view.pending_interaction != null and view.pending_interaction.kind != InteractionRequest.COMBAT
	main_menu.tooltip_text = "Resolve the current interaction first." if main_menu.disabled else "Close this campaign session and return to the Realmz Rebuilt main menu."
	var slot_name := new_row.get_node("NewSaveSlotName") as LineEdit
	var save_new := new_row.get_node("SaveNewSlot") as Button
	SystemSignalBinding.clear_text_changed(slot_name)
	SystemSignalBinding.clear_pressed(save_new)
	slot_name.text = ""
	var update_new_slot := func(value: String) -> void:
		save_new.disabled = value.is_empty() or value.length() > 128 or RegEx.create_from_string("^[A-Za-z0-9_-]+$").search(value) == null
		save_new.tooltip_text = "Use only letters, numbers, hyphens, or underscores." if save_new.disabled else "Create or replace this named save slot."
	slot_name.text_changed.connect(update_new_slot)
	save_new.pressed.connect(func() -> void: action_requested.emit(&"save", slot_name.text))
	update_new_slot.call(slot_name.text)


func _select_save_key(key: String) -> void:
	if _pending_save_action == &"load_legacy_into_slot":
		var slot := key.get_slice(":", 0)
		_legacy_target_slot = slot if slot.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(slot) and key.ends_with(":primary") else ""
	else:
		_clear_save_confirmation()
	_selected_save_key = key
	_refresh_save_detail()


func _refresh_save_detail() -> void:
	if _workspace == null:
		return
	var preview := _selected_preview()
	var slot_id := _selected_save_key.get_slice(":", 0)
	var primary_slot := slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(slot_id) and _selected_save_key.ends_with(":primary")
	var save_selected := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/SaveWorkspaceActions/SaveSelectedSlot") as Button
	save_selected.disabled = not primary_slot
	save_selected.text = "Save to %s" % slot_id if primary_slot else "Save to Slot"
	var load_selected := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/SaveWorkspaceActions/LoadSelectedSave") as Button
	var update_save := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/SaveWorkspaceActions/UpdateSave") as Button
	load_selected.disabled = preview == null or not preview.can_load
	load_selected.tooltip_text = "Select a validated save record." if preview == null else preview.error_message if not preview.can_load else "Restore this validated %s record." % preview.source_label().to_lower()
	load_selected.text = "Load %s" % slot_id if preview != null and preview.can_load else "Load Slot"
	update_save.visible = preview != null and preview.can_update
	update_save.tooltip_text = "Create a verified copy for the corrected campaign. Earlier event results are kept. The original save and backup remain untouched."
	_update_save_confirmation()
	var record := _workspace.save_detail_record()
	var empty := _workspace.save_detail_empty()
	record.visible = preview != null
	empty.visible = preview == null
	if preview == null:
		(empty.get_node("Text") as Label).text = "Slot %s is empty. Choose Save to %s to create it." % [slot_id, slot_id]
		return
	SystemPreferencesLayout.bind_label(record.get_node("Title") as Label, "%s  •  %s" % [SystemPreferencesLayout.slot_label(preview.slot_id), preview.source_label()], GOLD, 18)
	SystemPreferencesLayout.bind_label(record.get_node("Status") as Label, preview.status_label(), CYAN if preview.can_load else Color("d48a78"), 14)
	var map_image := record.get_node("MapPreview") as TextureRect
	var map_status := record.get_node("MapPreviewStatus") as Label
	map_image.custom_minimum_size = Vector2.ONE * (190.0 if _layout_profile == UiLayoutProfile.COMPACT else 240.0)
	map_image.texture = null
	if preview.can_load and not preview.map_preview_jpeg.is_empty():
		var image := Image.new()
		if image.load_jpg_from_buffer(preview.map_preview_jpeg) == OK:
			map_image.texture = ImageTexture.create_from_image(image)
	map_image.visible = map_image.texture != null
	map_status.visible = preview.can_load and map_image.texture == null
	var error := record.get_node("Error") as Label
	error.visible = preview.status != SaveSlotPreview.VALID
	SystemPreferencesLayout.bind_label(error, "%s\nUpdate Save creates a verified copy; this original remains untouched. Earlier event results are kept." % preview.error_message if preview.can_update else preview.error_message, MUTED, 14)
	var valid := preview.status == SaveSlotPreview.VALID
	for path: String in ["Location", "Party", "Divider", "Package", "Rules", "Saved"]:
		record.get_node(path).visible = valid
	_workspace.set_save_record_order(record, _layout_profile == UiLayoutProfile.COMPACT)
	if not valid:
		return
	var party := ", ".join(preview.character_names) if not preview.character_names.is_empty() else "No party members"
	SystemPreferencesLayout.bind_label(record.get_node("Location") as Label, "Day %d  •  %02d:%02d  •  %s %d,%d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute, preview.map_id, preview.coordinate.x, preview.coordinate.y], CYAN, 15)
	SystemPreferencesLayout.bind_label(record.get_node("Party") as Label, party, Color("e0e2e5"), 15)
	SystemPreferencesLayout.bind_label(record.get_node("Package") as Label, "Package %s" % preview.package_hash.left(12), MUTED, 13)
	SystemPreferencesLayout.bind_label(record.get_node("Rules") as Label, "Rules %s" % preview.rules_version, MUTED, 13)
	var saved := record.get_node("Saved") as Label
	saved.visible = preview.modified_unix > 0
	if saved.visible:
		SystemPreferencesLayout.bind_label(saved, "Saved %s" % Time.get_datetime_string_from_unix_time(preview.modified_unix), MUTED, 13)


func _load_selected_preview() -> void:
	var preview := _selected_preview()
	if preview == null or not preview.can_load:
		return
	if preview.slot_id in ["quick", "quick-2"] and not _has_empty_scenario_slot():
		_legacy_target_slot = ""
		_stage_save_confirmation(&"load_legacy_into_slot", preview.slot_id, preview.source == SaveSlotPreview.BACKUP)
		return
	var action_id: StringName = &"load_backup" if preview.source == SaveSlotPreview.BACKUP else &"load"
	if _save_view_has_active_adventure: _stage_save_confirmation(action_id, preview.slot_id, preview.source == SaveSlotPreview.BACKUP)
	else: action_requested.emit(action_id, preview.slot_id)


func _has_empty_scenario_slot() -> bool:
	for index: int in SaveSlotPreview.SCENARIO_SLOTS.length():
		var slot := SaveSlotPreview.SCENARIO_SLOTS.substr(index, 1)
		if _preview_for_slot(slot, SaveSlotPreview.PRIMARY) == null and _preview_for_slot(slot, SaveSlotPreview.BACKUP) == null:
			return true
	return false


func _save_selected_preview() -> void:
	var slot_id := _selected_save_key.get_slice(":", 0)
	if _selected_save_key.ends_with(":primary") and slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(slot_id):
		if _selected_preview() != null:
			_stage_save_confirmation(&"save", slot_id)
		else:
			action_requested.emit(&"save", slot_id)


func _save_selected_and_quit() -> void:
	var slot_id := _selected_save_key.get_slice(":", 0)
	if slot_id.length() != 1 or not SaveSlotPreview.SCENARIO_SLOTS.contains(slot_id):
		slot_id = _active_slot_id
	if _preview_for_slot(slot_id, SaveSlotPreview.PRIMARY) != null:
		_stage_save_confirmation(&"save_and_quit", slot_id)
	else:
		action_requested.emit(&"save_and_quit", slot_id)


func _stage_save_confirmation(action_id: StringName, slot_id: String, backup: bool = false) -> void:
	_pending_save_action = action_id
	_pending_save_slot = slot_id
	_pending_save_backup = backup
	_update_save_confirmation()
	if action_id in [&"load", &"load_backup"]: _workspace.focus_load_confirmation()


func _confirm_save_action() -> void:
	if _pending_save_action == &"":
		return
	var action_id := _pending_save_action
	var slot_id := _pending_save_slot
	if action_id == &"load_legacy_into_slot":
		if _legacy_target_slot.is_empty():
			return
		var request := {"slotId": slot_id, "backup": _pending_save_backup, "targetSlotId": _legacy_target_slot}
		_clear_save_confirmation()
		action_requested.emit(action_id, request)
		return
	_clear_save_confirmation()
	action_requested.emit(action_id, slot_id)


func _clear_save_confirmation() -> void:
	_pending_save_action = &""
	_pending_save_slot = ""
	_pending_save_backup = false
	_legacy_target_slot = ""
	_update_save_confirmation()
	_refresh_save_detail()


func _update_save_confirmation() -> void:
	if _workspace == null:
		return
	var row := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/ConfirmActionRow") as BoxContainer
	var migrating := _pending_save_action == &"load_legacy_into_slot"
	(row.get_node("Confirm") as Button).disabled = migrating and _legacy_target_slot.is_empty()
	var actions := row.get_parent().get_node("SaveWorkspaceActions")
	for action: String in ["QuickSave1", "SaveAndQuitSelected", "UpdateSave"]:
		(actions.get_node(action) as Button).disabled = migrating
	if migrating:
		(actions.get_node("SaveSelectedSlot") as Button).disabled = true
		(actions.get_node("LoadSelectedSave") as Button).disabled = true
	row.visible = _pending_save_action != &""
	if not row.visible:
		return
	var copy := "Load %s%s and replace the current adventure?" % [SystemPreferencesLayout.slot_label(_pending_save_slot), " backup" if _pending_save_backup else ""] if _pending_save_action in [&"load", &"load_backup"] else "Overwrite %s? The current record becomes its backup." % SystemPreferencesLayout.slot_label(_pending_save_slot)
	if migrating:
		var source := "%s%s" % [SystemPreferencesLayout.slot_label(_pending_save_slot), " backup" if _pending_save_backup else ""]
		copy = "All ten slots are occupied. Select an A–J slot to replace with %s." % source if _legacy_target_slot.is_empty() else "Replace Slot %s with %s and load it? The current slot record becomes its backup; the earlier save is kept." % [_legacy_target_slot, source]
	(row.get_node("ConfirmText") as Label).text = copy


func _selected_preview() -> SaveSlotPreview:
	for preview: SaveSlotPreview in _save_previews:
		if _key(preview) == _selected_save_key:
			return preview
	return null


func _key(preview: SaveSlotPreview) -> String:
	return "%s:%s" % [preview.slot_id, String(preview.source)] if preview != null else ""


func _bind_action(button: Button, action: Callable) -> void:
	SystemSignalBinding.clear_pressed(button)
	button.custom_minimum_size.y = 38.0
	button.pressed.connect(action)
