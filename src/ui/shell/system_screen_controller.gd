## Binds save operations and host preferences to the authored System workspace.
class_name SystemScreenController
extends RefCounted


class ControllerAccess:
	extends RefCounted
	var _owner: Variant
	func _init(owner: Variant) -> void: _owner = owner
	func receive_binding(action_id: StringName, descriptor: Dictionary) -> void:
		if _owner._controller_draft == null or action_id != _owner._controller_capture_action: return
		var physical_key := "%s:%d:%d" % [descriptor["kind"], int(descriptor["code"]), int(descriptor["direction"])]
		_owner._controller_draft.bindings = _owner._controller_draft.bindings.filter(func(binding: Dictionary) -> bool:
			return StringName(binding["action"]) != action_id and "%s:%d:%d" % [binding["kind"], int(binding["code"]), int(binding["direction"])] != physical_key
		)
		_owner._controller_draft.bindings.append(descriptor.duplicate(true))
		_owner._controller_capture_action = &""
		_owner._controller_draft_dirty = true
		_owner.refresh_controller_editor()
	func cancel_binding_capture() -> void:
		_owner._controller_capture_action = &""
		_owner.refresh_controller_editor()
	func set_live_input(value: String) -> void:
		_owner._controller_live_text = value
		if _owner._workspace == null: return
		var label := _owner._workspace.get_node_or_null("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControllerSettings/Content/TuningColumn/LiveInput") as Label
		if label != null: label.text = "Live input • %s" % value
	func bind_binding_list(bindings: VBoxContainer, conflicts: Array[Dictionary], reachable: bool, status: Label) -> void:
		var rows := bindings.get_node("BindingRows") as VBoxContainer
		for child: Node in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		for action_id: StringName in ControllerPreferences.ACTIONS:
			var button := Button.new()
			button.name = "ControllerBinding_%s" % String(action_id).trim_prefix("realmz_controller_")
			button.text = "%s  •  %s" % [_controller_action_label(action_id), _binding_summary(action_id)]
			button.tooltip_text = "Select, then press the desired controller input. East cancels capture."
			button.pressed.connect(func() -> void:
				_owner._controller_capture_action = action_id
				(bindings.get_node("BindingStatus") as Label).text = "Listening for %s… press East to cancel." % _controller_action_label(action_id)
				_owner.controller_binding_capture_requested.emit(action_id)
			)
			rows.add_child(button)
		if _owner._controller_capture_action.is_empty():
			status.text = "Rebind every missing required action before Apply." if not reachable else "%d binding conflict(s) must be resolved." % conflicts.size() if not conflicts.is_empty() else "Draft bindings are ready to apply."

	func _binding_summary(action_id: StringName) -> String:
		var values: Array[String] = []
		for binding: Dictionary in _owner._controller_draft.bindings:
			if StringName(binding["action"]) == action_id:
				values.append("button %d" % int(binding["code"]) if binding["kind"] == ControllerPreferences.BINDING_BUTTON else "axis %d %s" % [int(binding["code"]), "+" if int(binding["direction"]) > 0 else "-"])
		return ", ".join(values) if not values.is_empty() else "UNBOUND"

	static func _controller_action_label(action_id: StringName) -> String:
		return String(action_id).trim_prefix("realmz_controller_").replace("_", " ").capitalize()

const WORKSPACE_SCENE_PATH := "res://src/ui/shell/system_workspace.tscn"

signal action_requested(action_id: StringName, value: Variant)
signal setting_changed(setting_id: StringName, value: Variant)
signal controller_binding_capture_requested(action_id: StringName)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")
const CONTROL_HELP: Array[Dictionary] = [
	{"title": "Explore", "keys": "Arrows, WASD, or numpad", "detail": "Move one step; hold a direction or the map stage to keep traveling."},
	{"title": "Field commands", "keys": "F Search  •  C Camp  •  R Rest  •  H Heal", "detail": "The visible command deck provides the same actions and their current availability."},
	{"title": "Fast Spells", "keys": "1–0 select  •  Ctrl/Cmd + 1–0 cast", "detail": "In battle, hold Alt for the Fast Spell dock; Alt + 1–0 casts an assigned slot."},
	{"title": "Battle", "keys": "MoveTo costs  •  T target  •  Space confirm/skip", "detail": "Movement also uses arrows, WASD, or numpad; mouse targeting remains available."},
	{"title": "Workspaces", "keys": "Alt + 1–9  •  Escape Back/Cancel", "detail": "Every reversible workspace also keeps its visible Back, Done, or Cancel action."},
]

var _save_previews: Array[SaveSlotPreview] = []
var _selected_save_key: String = ""
var _active_slot_id: String = "A"
var _pending_save_action: StringName = &""
var _pending_save_slot: String = ""
var _pending_save_backup: bool = false
var _save_view_session_started: bool = false
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _save_and_quit_mode: bool = false
var _selected_workspace_mode: StringName = &"Display"
var _workspace: SystemWorkspace
var _controller_draft: ControllerPreferences
var _committed_controller_draft: ControllerPreferences
var _controller_draft_dirty: bool = false
var _controller_capture_action: StringName = &""
var _controller_live_text: String = ""
var controller: ControllerAccess:
	get: return ControllerAccess.new(self)


func navigate_section(section_name: StringName = &"", delta: int = 0) -> bool:
	if _workspace == null:
		return false
	if section_name == &"Save & Load" or section_name == &"SaveAndLoad":
		show_saves()
		return true
	var categories: Array[StringName] = [&"Display", &"Audio", &"Accessibility", &"Controls", &"Diagnostics"]
	if section_name.is_empty():
		var current := categories.find(_selected_workspace_mode)
		current = wrapi(current + delta, 0, categories.size())
		show_category(categories[current])
		return true
	if section_name == &"Audio & Pacing":
		show_category(&"Audio")
		return true
	if categories.has(section_name):
		show_category(section_name)
		return true
	return false


func show_category(category: StringName) -> void:
	if _workspace == null:
		return
	if category == &"Audio & Pacing":
		category = &"Audio"
	_workspace.call("show_category", category)
	_selected_workspace_mode = category


func show_saves() -> void:
	if _workspace == null:
		return
	_workspace.call("show_saves")
	_selected_workspace_mode = &"Save & Load"


func has_dirty_controller_draft() -> bool:
	return _controller_draft_dirty


func discard_controller_draft() -> void:
	if _committed_controller_draft == null:
		return
	_controller_draft = _committed_controller_draft.duplicate_value()
	_controller_draft_dirty = false
	_controller_capture_action = &""
	refresh_controller_editor()


func apply_controller_draft() -> bool:
	if _controller_draft == null or _controller_capture_action != &"":
		return false
	if not _controller_draft.required_navigation_is_reachable() or not _controller_draft.conflicts().is_empty():
		return false
	_controller_draft_dirty = false
	_committed_controller_draft = _controller_draft.duplicate_value()
	setting_changed.emit(&"controller_preferences", _controller_draft.duplicate_value())
	return true


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


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


func present(target: Control, view: GameView, settings: PresentationSettings) -> void:
	if target == null or view == null or settings == null:
		return
	var screen := target as SystemScreen
	if screen != null:
		screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
		var next_workspace := screen.workspace()
		if next_workspace != _workspace:
			_pending_save_action = &""
		_workspace = next_workspace
	else:
		var parent := target as VBoxContainer
		_clear(parent)
		_workspace = (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as SystemWorkspace
		parent.add_child(_workspace)
		_workspace.prepare(_layout_profile == UiLayoutProfile.COMPACT)
	if _workspace.has_signal("category_selected") and not _workspace.has_meta("system_category_observer"):
		_workspace.connect("category_selected", func(category: StringName) -> void: _selected_workspace_mode = category)
		_workspace.set_meta("system_category_observer", true)
	if _workspace.has_signal("setting_changed") and not _workspace.has_meta("system_setting_observer"):
		_workspace.connect("setting_changed", func(setting_id: StringName, value: Variant) -> void: setting_changed.emit(setting_id, value))
		_workspace.set_meta("system_setting_observer", true)
	if _workspace.has_signal("action_requested") and not _workspace.has_meta("system_action_observer"):
		_workspace.connect("action_requested", func(action_id: StringName, value: Variant) -> void: action_requested.emit(action_id, value))
		_workspace.set_meta("system_action_observer", true)
	_bind_header(view)
	_bind_save_workspace(view)
	_bind_display(settings)
	_workspace.call("bind_audio", settings)
	_workspace.call("bind_pacing", settings)
	_workspace.call("bind_accessibility", settings)
	_bind_controls(settings)
	_bind_diagnostics(settings)
	if _selected_workspace_mode == &"Save & Load":
		_workspace.call("show_saves")
	else:
		_workspace.call("show_category", _selected_workspace_mode)


func _bind_header(view: GameView) -> void:
	var campaign := view.campaign_summary.title if view.campaign_summary != null else view.campaign_id
	_bind_label(_workspace.campaign_context(), "%s  •  %s" % [campaign, view.rules_version], CYAN, 13)


func _bind_save_workspace(view: GameView) -> void:
	_save_view_session_started = view.session_started
	var rows := _workspace.save_slot_rows()
	var empty := _workspace.save_browser_empty()
	empty.visible = false
	(_workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/ActiveSlotLabel") as Label).text = "Slot %s active · Quick Save overwrites %s" % [_active_slot_id, _active_slot_id]
	if view.party_setup_available and _selected_preview() == null:
		for existing: SaveSlotPreview in _save_previews:
			if existing.can_load and existing.source == SaveSlotPreview.PRIMARY:
				_selected_save_key = _key(existing)
				break
	var group := ButtonGroup.new()
	for slot_index: int in SaveSlotPreview.SCENARIO_SLOTS.length():
		var slot_id := SaveSlotPreview.SCENARIO_SLOTS.substr(slot_index, 1)
		var primary := _preview_for_slot(slot_id, SaveSlotPreview.PRIMARY)
		var button := _workspace.save_slot_row_scene.instantiate() as Button
		button.name = "SavePreview_%s_primary" % slot_id
		button.text = "Slot %s%s  ·  %s" % [slot_id, "  ★" if slot_id == _active_slot_id else "", primary.status_label() if primary != null else "Empty"]
		button.button_group = group
		button.button_pressed = _selected_save_key == slot_id + ":primary"
		button.pressed.connect(_select_save_key.bind(slot_id + ":primary"))
		rows.add_child(button)
		var backup := _preview_for_slot(slot_id, SaveSlotPreview.BACKUP)
		if backup != null:
			_add_save_preview_row(rows, group, backup, "   ↳ Backup · %s" % backup.status_label())
	for preview: SaveSlotPreview in _save_previews:
		if preview.slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(preview.slot_id):
			continue
		_add_save_preview_row(rows, group, preview, "Earlier save · %s · %s" % [slot_label(preview.slot_id), preview.source_label()])
	_bind_save_footer(view)
	_refresh_save_detail()


func _add_save_preview_row(rows: VBoxContainer, group: ButtonGroup, preview: SaveSlotPreview, label: String) -> void:
	var button := _workspace.save_slot_row_scene.instantiate() as Button
	button.name = "SavePreview_%s_%s" % [preview.slot_id, String(preview.source)]
	button.text = label
	button.button_group = group
	button.button_pressed = _key(preview) == _selected_save_key
	button.pressed.connect(_select_save.bind(preview))
	rows.add_child(button)


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


func _select_save(preview: SaveSlotPreview) -> void:
	_clear_save_confirmation()
	_selected_save_key = _key(preview)
	_refresh_save_detail()


func _select_save_key(key: String) -> void:
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
	update_save.tooltip_text = "Create and verify a corrected Half Truth copy. The original save and backup remain untouched."
	var record := _workspace.save_detail_record()
	var empty := _workspace.save_detail_empty()
	record.visible = preview != null
	empty.visible = preview == null
	if preview == null:
		(empty.get_node("Text") as Label).text = "Slot %s is empty. Choose Save to %s to create it." % [slot_id, slot_id]
		return
	_bind_label(record.get_node("Title") as Label, "%s  •  %s" % [slot_label(preview.slot_id), preview.source_label()], GOLD, 18)
	_bind_label(record.get_node("Status") as Label, preview.status_label(), CYAN if preview.can_load else Color("d48a78"), 14)
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
	_bind_label(error, "%s\nUpdate Save creates a separate verified copy; this original remains untouched." % preview.error_message if preview.can_update else preview.error_message, MUTED, 14)
	var valid := preview.status == SaveSlotPreview.VALID
	for path: String in ["Location", "Party", "Divider", "Package", "Rules", "Saved"]:
		record.get_node(path).visible = valid
	if not valid:
		return
	var party := ", ".join(preview.character_names) if not preview.character_names.is_empty() else "No party members"
	_bind_label(record.get_node("Location") as Label, "Day %d  •  %02d:%02d  •  %s %d,%d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute, preview.map_id, preview.coordinate.x, preview.coordinate.y], CYAN, 15)
	_bind_label(record.get_node("Party") as Label, party, Color("e0e2e5"), 15)
	_bind_label(record.get_node("Package") as Label, "Package %s" % preview.package_hash.left(12), MUTED, 13)
	_bind_label(record.get_node("Rules") as Label, "Rules %s" % preview.rules_version, MUTED, 13)
	var saved := record.get_node("Saved") as Label
	saved.visible = preview.modified_unix > 0
	if saved.visible:
		_bind_label(saved, "Saved %s" % Time.get_datetime_string_from_unix_time(preview.modified_unix), MUTED, 13)


func _load_selected_preview() -> void:
	var preview := _selected_preview()
	if preview == null or not preview.can_load:
		return
	var action_id: StringName = &"load_backup" if preview.source == SaveSlotPreview.BACKUP else &"load"
	if _save_view_session_started:
		_stage_save_confirmation(action_id, preview.slot_id, preview.source == SaveSlotPreview.BACKUP)
	else:
		action_requested.emit(action_id, preview.slot_id)


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


func _confirm_save_action() -> void:
	if _pending_save_action == &"":
		return
	var action_id := _pending_save_action
	var slot_id := _pending_save_slot
	_clear_save_confirmation()
	action_requested.emit(action_id, slot_id)


func _clear_save_confirmation() -> void:
	_pending_save_action = &""
	_pending_save_slot = ""
	_pending_save_backup = false
	_update_save_confirmation()


func _update_save_confirmation() -> void:
	if _workspace == null:
		return
	var row := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/ConfirmActionRow") as BoxContainer
	row.visible = _pending_save_action != &""
	if not row.visible:
		return
	var copy := "Load %s%s and replace the current adventure?" % [slot_label(_pending_save_slot), " backup" if _pending_save_backup else ""] if _pending_save_action in [&"load", &"load_backup"] else "Overwrite %s? The current record becomes its backup." % slot_label(_pending_save_slot)
	(row.get_node("ConfirmText") as Label).text = copy


func _selected_preview() -> SaveSlotPreview:
	for preview: SaveSlotPreview in _save_previews:
		if _key(preview) == _selected_save_key:
			return preview
	return null


func _key(preview: SaveSlotPreview) -> String:
	return "%s:%s" % [preview.slot_id, String(preview.source)] if preview != null else ""


static func slot_label(slot_id: String) -> String:
	if slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(slot_id):
		return "Slot %s" % slot_id
	match slot_id:
		"quick": return "Quick Save 1"
		"quick-2": return "Quick Save 2"
		_: return slot_id


func _bind_display(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Display/DisplaySettingsScroll/DisplaySettingsPanel/Content")
	_bind_option(root.get_node("DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/DisplayScalingRow/DisplayScalingPicker") as OptionButton, [
		{"label": "Responsive (current)", "id": PresentationSettings.DISPLAY_RESPONSIVE},
		{"label": "Integer: whole window", "id": PresentationSettings.DISPLAY_INTEGER_WINDOW},
		{"label": "Integer: world canvas", "id": PresentationSettings.DISPLAY_INTEGER_CANVAS},
		{"label": "Fill window", "id": PresentationSettings.DISPLAY_FILL_WINDOW},
	], settings.display_scaling_mode, &"display_scaling_mode")
	var zoom_picker := root.get_node("DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/WorldZoomRow/WorldZoomPicker") as OptionButton
	_bind_option(zoom_picker, [
		{"label": "1× · 32-pixel tiles", "id": "1"},
		{"label": "2× · 64-pixel tiles", "id": "2"},
		{"label": "3× · 96-pixel tiles", "id": "3"},
		{"label": "4× · 128-pixel tiles", "id": "4"},
	], str(settings.world_zoom), &"world_zoom")
	zoom_picker.disabled = settings.display_scaling_mode != PresentationSettings.DISPLAY_INTEGER_CANVAS
	_bind_option(root.get_node("DisplayTopRow/DisplaySettingsColumn/VisualEffectsGroup/Content/PixelSmoothingRow/PixelSmoothingPicker") as OptionButton, [
		{"label": "Off · crisp pixels", "id": PresentationSettings.SMOOTHING_OFF},
		{"label": "World canvas only", "id": PresentationSettings.SMOOTHING_WORLD},
		{"label": "Whole window", "id": PresentationSettings.SMOOTHING_WINDOW},
	], settings.pixel_art_smoothing, &"pixel_art_smoothing")
	_bind_toggle(root.get_node("DisplayTopRow/DisplaySettingsColumn/VisualEffectsGroup/Content/CrtEnabled") as CheckButton, settings.crt_enabled, &"crt_enabled")
	_bind_option(root.get_node("DisplayTopRow/DisplaySettingsColumn/VisualEffectsGroup/Content/CrtShaderRow/CrtShaderPicker") as OptionButton, [
		{"label": "CRT-Pi", "id": PresentationSettings.CRT_PI},
		{"label": "CRT-Lottes", "id": PresentationSettings.CRT_LOTTES},
	], settings.crt_shader, &"crt_shader")
	_bind_option(root.get_node("DisplayTopRow/DisplaySettingsColumn/VisualEffectsGroup/Content/CrtAreaRow/CrtAreaPicker") as OptionButton, [
		{"label": "World canvas", "id": PresentationSettings.CRT_WORLD},
		{"label": "Whole window", "id": PresentationSettings.CRT_WINDOW},
	], settings.crt_area, &"crt_area")
	_bind_option(root.get_node("DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/InterfaceScaleRow/InterfaceScalePicker") as OptionButton, [
		{"label": "Fit to window", "id": PresentationSettings.UI_SCALE_AUTO},
		{"label": "Interface density: 100%", "id": PresentationSettings.UI_SCALE_100},
		{"label": "Interface density: 125%", "id": PresentationSettings.UI_SCALE_125},
		{"label": "Interface density: 150%", "id": PresentationSettings.UI_SCALE_150},
	], settings.ui_scale_mode, &"ui_scale_mode")
	_bind_option(root.get_node("DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/WindowModeRow/WindowModePicker") as OptionButton, [
		{"label": "Windowed", "id": PresentationSettings.WINDOWED},
		{"label": "Borderless fullscreen", "id": PresentationSettings.BORDERLESS_FULLSCREEN},
	], settings.window_mode, &"window_mode")
	_bind_toggle(root.get_node("WorldViewGroup/Content/WorldOptions/Dungeon3d") as CheckButton, settings.dungeon_3d, &"dungeon_3d")
	_bind_toggle(root.get_node("WorldViewGroup/Content/WorldOptions/ClassicExplorationVisibility") as CheckButton, settings.classic_exploration_visibility, &"classic_exploration_visibility")
	_bind_toggle(root.get_node("WorldViewGroup/Content/WorldOptions/CustomFogTile") as CheckButton, settings.custom_fog_tile_enabled, &"custom_fog_tile_enabled")


func _bind_controls(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content")
	if _controller_draft == null or not _controller_draft_dirty:
		_controller_draft = settings.controller.duplicate_value()
		_committed_controller_draft = settings.controller.duplicate_value()
	_bind_controller_editor(root.get_node("ControllerSettings/Content") as GridContainer)
	_bind_toggle(root.get_node("AutoSwitchToMelee") as CheckButton, settings.auto_switch_to_melee, &"auto_switch_to_melee")
	_bind_toggle(root.get_node("ImmediateSingleTargetActions") as CheckButton, settings.immediate_single_target_actions, &"immediate_single_target_actions")
	_bind_toggle(root.get_node("ClassicKeyboardShortcuts") as CheckButton, settings.classic_keyboard_shortcuts, &"classic_keyboard_shortcuts")
	_bind_toggle(root.get_node("ShowExplorationMinimap") as CheckButton, settings.show_exploration_minimap, &"show_exploration_minimap")
	_bind_toggle(root.get_node("AutojournalEnabled") as CheckButton, settings.autojournal_enabled, &"autojournal_enabled")
	for entry: Dictionary in CONTROL_HELP:
		var card := root.get_node("ControlHelp%s" % String(entry["title"]).replace(" ", "")) as PanelContainer
		var row := card.get_node("Row") as BoxContainer
		_bind_label(row.get_node("Identity") as Label, "%s  •  %s" % [entry["title"], entry["keys"]], GOLD, 14)
		_bind_label(row.get_node("Detail") as Label, String(entry["detail"]), MUTED, 13)
		(row.get_node("Identity") as Label).custom_minimum_size.x = 0.0 if _layout_profile == UiLayoutProfile.COMPACT else 330.0


func _bind_controller_editor(root: GridContainer) -> void:
	var tuning := root.get_node("TuningColumn") as VBoxContainer
	var bindings := root.get_node("BindingColumn/Content") as VBoxContainer
	var prompt := tuning.get_node("PromptFamily") as OptionButton
	SystemSignalBinding.clear_item_selected(prompt)
	prompt.clear()
	for family: String in ControllerPreferences.PROMPT_FAMILIES:
		prompt.add_item("Prompt family • %s" % family.capitalize())
		prompt.set_item_metadata(prompt.item_count - 1, family)
		if family == _controller_draft.prompt_family:
			prompt.select(prompt.item_count - 1)
	prompt.item_selected.connect(func(index: int) -> void:
		_controller_draft.prompt_family = String(prompt.get_item_metadata(index))
		_controller_draft_dirty = true
	)
	_bind_controller_slider(tuning.get_node("LeftDeadZone") as HSlider, tuning.get_node("LeftDeadZoneLabelRow/Value") as Label, _controller_draft.left_stick_dead_zone, "Left stick dead zone", func(value: float) -> void: _controller_draft.left_stick_dead_zone = value)
	_bind_controller_slider(tuning.get_node("RightDeadZone") as HSlider, tuning.get_node("RightDeadZoneLabelRow/Value") as Label, _controller_draft.right_stick_dead_zone, "Right stick dead zone", func(value: float) -> void: _controller_draft.right_stick_dead_zone = value)
	_bind_controller_slider(tuning.get_node("RepeatInitial") as HSlider, tuning.get_node("RepeatInitialLabelRow/Value") as Label, _controller_draft.repeat_initial_ms, "UI repeat start delay", func(value: float) -> void: _controller_draft.repeat_initial_ms = int(value))
	_bind_controller_slider(tuning.get_node("RepeatInterval") as HSlider, tuning.get_node("RepeatIntervalLabelRow/Value") as Label, _controller_draft.repeat_interval_ms, "UI repeat interval", func(value: float) -> void: _controller_draft.repeat_interval_ms = int(value))
	(tuning.get_node("LiveInput") as Label).text = "Live input • %s" % (_controller_live_text if not _controller_live_text.is_empty() else "move or press a controller control")
	var conflicts := _controller_draft.conflicts()
	var reachable := _controller_draft.required_navigation_is_reachable()
	var status := bindings.get_node("BindingStatus") as Label
	controller.bind_binding_list(bindings, conflicts, reachable, status)
	var restore := bindings.get_node("Actions/RestoreControllerDefaults") as Button
	SystemSignalBinding.clear_pressed(restore)
	var restore_dock := _workspace.get_node("ControlsDraftFooter/RestoreControllerDefaultsDock") as Button
	SystemSignalBinding.clear_pressed(restore_dock)
	var discard_dock := _workspace.get_node("ControlsDraftFooter/DiscardControllerDraftDock") as Button
	SystemSignalBinding.clear_pressed(discard_dock)
	discard_dock.disabled = not _controller_draft_dirty
	discard_dock.tooltip_text = "Discard controller changes and restore the committed profile."
	discard_dock.pressed.connect(func() -> void: discard_controller_draft())
	var restore_defaults := func() -> void:
		_controller_draft = ControllerPreferences.new()
		_controller_draft_dirty = true
		_controller_capture_action = &""
		refresh_controller_editor()
	restore.pressed.connect(restore_defaults)
	restore_dock.pressed.connect(restore_defaults)
	var apply := bindings.get_node("Actions/ApplyControllerBindings") as Button
	SystemSignalBinding.clear_pressed(apply)
	var apply_dock := _workspace.get_node("ControlsDraftFooter/ApplyControllerBindingsDock") as Button
	SystemSignalBinding.clear_pressed(apply_dock)
	apply.disabled = not reachable or not conflicts.is_empty() or not _controller_capture_action.is_empty()
	apply.tooltip_text = status.text if apply.disabled else "Apply this complete controller draft."
	apply_dock.disabled = apply.disabled
	apply_dock.tooltip_text = apply.tooltip_text
	var apply_bindings := func() -> void:
		apply_controller_draft()
	apply.pressed.connect(apply_bindings)
	apply_dock.pressed.connect(apply_bindings)


func _bind_controller_slider(slider: HSlider, value_label: Label, value: float, caption: String, assign: Callable) -> void:
	SystemSignalBinding.clear_value_changed(slider)
	slider.value = value
	var format_value := func(next: float) -> String:
		return "%d%%" % int(round(next * 100.0)) if slider.name.ends_with("DeadZone") else "%d ms" % int(round(next))
	value_label.text = format_value.call(value)
	slider.tooltip_text = "%s • %s" % [caption, value_label.text]
	slider.value_changed.connect(func(next: float) -> void:
		assign.call(next)
		_controller_draft_dirty = true
		value_label.text = format_value.call(next)
		slider.tooltip_text = "%s • %s" % [caption, value_label.text]
	)


func refresh_controller_editor() -> void:
	if _workspace != null:
		_bind_controller_editor(_workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControllerSettings/Content") as GridContainer)


func _bind_diagnostics(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Diagnostics/DiagnosticsSettingsScroll/DiagnosticsSettingsPanel/Content")
	_bind_toggle(root.get_node("TopologyDebug") as CheckButton, settings.topology_debug, &"topology_debug")


func _bind_option(picker: OptionButton, entries: Array[Dictionary], selected_id: String, setting_id: StringName) -> void:
	SystemSignalBinding.clear_item_selected(picker)
	picker.clear()
	for entry: Dictionary in entries:
		picker.add_item(entry["label"])
		picker.set_item_metadata(picker.item_count - 1, entry["id"])
		if entry["id"] == selected_id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: setting_changed.emit(setting_id, String(picker.get_item_metadata(index))))


func _bind_slider(slider: Range, value: float, setting_id: StringName) -> void:
	SystemSignalBinding.clear_value_changed(slider)
	slider.value = value
	slider.value_changed.connect(func(changed_value: float) -> void: setting_changed.emit(setting_id, changed_value))


func _bind_toggle(toggle: CheckButton, enabled: bool, setting_id: StringName) -> void:
	SystemSignalBinding.clear_toggled(toggle)
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: setting_changed.emit(setting_id, value))


func _bind_action(button: Button, action: Callable) -> void:
	SystemSignalBinding.clear_pressed(button)
	button.custom_minimum_size.y = 38.0
	button.pressed.connect(action)


static func _bind_label(label: Label, text: String, color: Color, size: int) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)


static func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
