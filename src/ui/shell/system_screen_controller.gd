## Binds save operations and host preferences to the authored System workspace.
class_name SystemScreenController
extends RefCounted

const WORKSPACE_SCENE_PATH := "res://src/ui/shell/system_workspace.tscn"

signal action_requested(action_id: StringName, value: Variant)
signal setting_changed(setting_id: StringName, value: Variant)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")
const CONTROL_HELP: Array[Dictionary] = [
	{"title": "Explore", "keys": "Arrows, WASD, or numpad", "detail": "Move one step; hold a direction or the map stage to keep traveling."},
	{"title": "Field commands", "keys": "F Search  •  C Camp  •  R Rest  •  H Heal", "detail": "The visible command deck provides the same actions and their current availability."},
	{"title": "Fast Spells", "keys": "1–0 select  •  Ctrl/Cmd + 1–0 cast", "detail": "In battle, hold Alt for the Fast Spell dock; Alt + 1–0 casts an assigned slot."},
	{"title": "Battle", "keys": "Shift costs  •  T target  •  Space confirm/skip", "detail": "Movement also uses arrows, WASD, or numpad; mouse targeting remains available."},
	{"title": "Workspaces", "keys": "Alt + 1–9  •  Escape Back/Cancel", "detail": "Every reversible workspace also keeps its visible Back, Done, or Cancel action."},
]

var _save_previews: Array[SaveSlotPreview] = []
var _selected_save_key: String = ""
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _save_and_quit_mode: bool = false
var _workspace: SystemWorkspace


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_save_previews = previews.duplicate()
	if not _save_previews.any(func(preview: SaveSlotPreview) -> bool: return _key(preview) == _selected_save_key):
		_selected_save_key = _key(_save_previews[0]) if not _save_previews.is_empty() else ""


func set_save_and_quit_mode(enabled: bool) -> void:
	if enabled and not _save_and_quit_mode:
		for preview: SaveSlotPreview in _save_previews:
			if preview.source == SaveSlotPreview.PRIMARY and preview.can_load:
				_selected_save_key = _key(preview)
				break
	_save_and_quit_mode = enabled


func present(target: Control, view: GameView, settings: PresentationSettings) -> void:
	if target == null or view == null or settings == null:
		return
	var screen := target as SystemScreen
	if screen != null:
		screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
		_workspace = screen.workspace()
	else:
		var parent := target as VBoxContainer
		_clear(parent)
		_workspace = (load(WORKSPACE_SCENE_PATH) as PackedScene).instantiate() as SystemWorkspace
		parent.add_child(_workspace)
		_workspace.prepare(_layout_profile == UiLayoutProfile.COMPACT)
	_bind_header(view)
	_bind_save_workspace(view)
	_bind_display(settings)
	_bind_audio(settings)
	_bind_pacing(settings)
	_bind_accessibility(settings)
	_bind_controls(settings)
	_bind_diagnostics(settings)


func _bind_header(view: GameView) -> void:
	var campaign := view.campaign_summary.title if view.campaign_summary != null else view.campaign_id
	_bind_label(_workspace.campaign_context(), "%s  •  %s" % [campaign, view.rules_version], CYAN, 13)


func _bind_save_workspace(view: GameView) -> void:
	var rows := _workspace.save_slot_rows()
	var empty := _workspace.save_browser_empty()
	empty.visible = _save_previews.is_empty()
	if empty.visible:
		(empty.get_node("Text") as Label).text = "No saves for this campaign\n%s" % ("Return to party setup and begin a new adventure." if view.party_setup_available else "Use either Quick Save slot or create a named save below.")
	var group := ButtonGroup.new()
	for preview: SaveSlotPreview in _save_previews:
		var button := _workspace.save_slot_row_scene.instantiate() as Button
		button.name = "SavePreview_%s_%s" % [preview.slot_id, String(preview.source)]
		button.text = "%s  •  %s\n%s" % [slot_label(preview.slot_id), preview.source_label(), preview.status_label()]
		button.button_group = group
		button.button_pressed = _key(preview) == _selected_save_key
		button.pressed.connect(_select_save.bind(preview))
		rows.add_child(button)
	_bind_save_footer(view)
	_refresh_save_detail()


func _bind_save_footer(view: GameView) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter") as VBoxContainer
	var actions := root.get_node("SaveWorkspaceActions") as BoxContainer
	var save_and_quit := actions.get_node("SaveAndQuitSelected") as Button
	var quick_one := actions.get_node("QuickSave1") as Button
	var quick_two := actions.get_node("QuickSave2") as Button
	var save_selected := actions.get_node("SaveSelectedSlot") as Button
	var load_selected := actions.get_node("LoadSelectedSave") as Button
	var refresh := actions.get_node("RefreshSaves") as Button
	var main_menu := actions.get_node("MainMenu") as Button
	var new_row := root.get_node("NewSaveSlotRow") as BoxContainer
	var ordinary_save := not _save_and_quit_mode and not view.party_setup_available
	save_and_quit.visible = _save_and_quit_mode
	quick_one.visible = ordinary_save
	quick_two.visible = ordinary_save
	save_selected.visible = ordinary_save
	new_row.visible = ordinary_save
	_bind_action(save_and_quit, func() -> void: _save_selected_and_quit())
	_bind_action(quick_one, func() -> void: action_requested.emit(&"save", "quick"))
	_bind_action(quick_two, func() -> void: action_requested.emit(&"save", "quick-2"))
	_bind_action(save_selected, func() -> void: _save_selected_preview())
	_bind_action(load_selected, func() -> void: _load_selected_preview())
	_bind_action(refresh, func() -> void: action_requested.emit(&"refresh_saves", null))
	_bind_action(main_menu, func() -> void: action_requested.emit(&"end_adventure", null))
	save_and_quit.tooltip_text = "Save to the selected slot, then quit Realmz Rebuilt."
	main_menu.disabled = view.pending_interaction != null and view.pending_interaction.kind != InteractionRequest.COMBAT
	main_menu.tooltip_text = "Resolve the current interaction first." if main_menu.disabled else "Close this campaign session and return to the Realmz Rebuilt main menu."
	var slot_name := new_row.get_node("NewSaveSlotName") as LineEdit
	var save_new := new_row.get_node("SaveNewSlot") as Button
	_clear_text_changed_connections(slot_name)
	_clear_pressed_connections(save_new)
	slot_name.text = ""
	var update_new_slot := func(value: String) -> void:
		save_new.disabled = not slot_id_is_portable(value)
		save_new.tooltip_text = "Use only letters, numbers, hyphens, or underscores." if save_new.disabled else "Create or replace this named save slot."
	slot_name.text_changed.connect(update_new_slot)
	save_new.pressed.connect(func() -> void: action_requested.emit(&"save", slot_name.text))
	update_new_slot.call(slot_name.text)


func _select_save(preview: SaveSlotPreview) -> void:
	_selected_save_key = _key(preview)
	_refresh_save_detail()


func _refresh_save_detail() -> void:
	if _workspace == null:
		return
	var preview := _selected_preview()
	var load_selected := _workspace.get_node("SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/SaveWorkspaceActions/LoadSelectedSave") as Button
	load_selected.disabled = preview == null or not preview.can_load
	load_selected.tooltip_text = "Select a validated save record." if preview == null else preview.error_message if not preview.can_load else "Restore this validated %s record." % preview.source_label().to_lower()
	var record := _workspace.save_detail_record()
	var empty := _workspace.save_detail_empty()
	record.visible = preview != null
	empty.visible = preview == null
	if preview == null:
		return
	_bind_label(record.get_node("Title") as Label, "%s  •  %s" % [slot_label(preview.slot_id), preview.source_label()], GOLD, 18)
	_bind_label(record.get_node("Status") as Label, preview.status_label(), CYAN if preview.can_load else Color("d48a78"), 14)
	var error := record.get_node("Error") as Label
	error.visible = preview.status != SaveSlotPreview.VALID
	_bind_label(error, preview.error_message, MUTED, 14)
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
	action_requested.emit(&"load_backup" if preview.source == SaveSlotPreview.BACKUP else &"load", preview.slot_id)


func _save_selected_preview() -> void:
	var preview := _selected_preview()
	if preview != null:
		action_requested.emit(&"save", preview.slot_id)


func _save_selected_and_quit() -> void:
	var preview := _selected_preview()
	action_requested.emit(&"save_and_quit", preview.slot_id if preview != null else "quick")


func _selected_preview() -> SaveSlotPreview:
	for preview: SaveSlotPreview in _save_previews:
		if _key(preview) == _selected_save_key:
			return preview
	return null


func _key(preview: SaveSlotPreview) -> String:
	return "%s:%s" % [preview.slot_id, String(preview.source)] if preview != null else ""


static func slot_id_is_portable(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for index: int in value.length():
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or code in [45, 95]):
			return false
	return true


static func slot_label(slot_id: String) -> String:
	match slot_id:
		"quick": return "Quick Save 1"
		"quick-2": return "Quick Save 2"
		_: return slot_id


func _bind_display(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Display/DisplaySettingsScroll/DisplaySettingsPanel/Content")
	_bind_option(root.get_node("InterfaceScaleRow/InterfaceScalePicker") as OptionButton, [
		{"label": "Fit to window", "id": PresentationSettings.UI_SCALE_AUTO},
		{"label": "Interface density: 100%", "id": PresentationSettings.UI_SCALE_100},
		{"label": "Interface density: 125%", "id": PresentationSettings.UI_SCALE_125},
		{"label": "Interface density: 150%", "id": PresentationSettings.UI_SCALE_150},
	], settings.ui_scale_mode, &"ui_scale_mode")
	var text_scale := root.get_node("TextScaleRow/TextScaleSlider") as HSlider
	_bind_slider(text_scale, settings.text_scale, &"text_scale")
	text_scale.tooltip_text = "Text scale %d%%" % int(round(settings.text_scale * 100.0))
	_bind_label(root.get_node("TextScaleRow/Caption") as Label, "Text size  •  %d%%" % int(round(settings.text_scale * 100.0)), Color("e0e2e5"), 15)
	_bind_option(root.get_node("TypographyRow/TypographyPicker") as OptionButton, [
		{"label": "Classic Realmz fonts", "id": PresentationSettings.TYPOGRAPHY_CLASSIC},
		{"label": "Readable modern fonts", "id": PresentationSettings.TYPOGRAPHY_READABLE},
	], settings.typography_mode, &"typography_mode")
	_bind_option(root.get_node("WindowModeRow/WindowModePicker") as OptionButton, [
		{"label": "Windowed", "id": PresentationSettings.WINDOWED},
		{"label": "Borderless fullscreen", "id": PresentationSettings.BORDERLESS_FULLSCREEN},
	], settings.window_mode, &"window_mode")
	_bind_toggle(root.get_node("Dungeon3d") as CheckButton, settings.dungeon_3d, &"dungeon_3d")
	_bind_toggle(root.get_node("ClassicExplorationVisibility") as CheckButton, settings.classic_exploration_visibility, &"classic_exploration_visibility")


func _bind_audio(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Audio/AudioSettingsScroll/AudioSettingsPanel/Content")
	_bind_volume_row(root.get_node("MasterVolumeRow") as BoxContainer, "Master volume", settings.master_volume, &"master_volume")
	_bind_volume_row(root.get_node("SoundVolumeRow") as BoxContainer, "Sound effects", settings.sound_volume, &"sound_volume")
	_bind_volume_row(root.get_node("MusicVolumeRow") as BoxContainer, "Music", settings.music_volume, &"music_volume")
	_bind_toggle(root.get_node("MusicEnabled") as CheckButton, settings.music_enabled, &"music_enabled")
	_bind_toggle(root.get_node("ReducedSound") as CheckButton, settings.reduced_sound, &"reduced_sound")
	_bind_action(root.get_node("OpenMusicPlaylist") as Button, func() -> void: action_requested.emit(&"music_playlist", null))


func _bind_volume_row(row: BoxContainer, title: String, value: float, setting_id: StringName) -> void:
	_bind_label(row.get_node("Caption") as Label, "%s  •  %d%%" % [title, int(round(value * 100.0))], Color("e0e2e5"), 15)
	var slider := row.get_child(1) as HSlider
	_bind_slider(slider, value, setting_id)
	slider.tooltip_text = "%s volume %d%%" % [title, int(round(value * 100.0))]


func _bind_pacing(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Pacing/PacingSettingsScroll/PacingSettingsPanel/Content")
	var combat := root.get_node("CombatSpeedRow/CombatPlaybackSpeedSlider") as HSlider
	var combat_caption := root.get_node("CombatSpeedRow/CombatPlaybackSpeedCaption") as Label
	_bind_label(combat_caption, "Combat & animation speed  •  %d%%" % settings.combat_playback_speed_percent, Color("e0e2e5"), 15)
	_clear_value_changed_connections(combat)
	combat.value = settings.combat_playback_speed_percent
	combat.tooltip_text = "%d%%  •  affects movement, attacks, projectiles, spells, and result holds" % settings.combat_playback_speed_percent
	combat.value_changed.connect(func(value: float) -> void:
		var percent := int(value)
		combat_caption.text = "Combat & animation speed  •  %d%%" % percent
		combat.tooltip_text = "%d%%  •  affects movement, attacks, projectiles, spells, and result holds" % percent
		setting_changed.emit(&"combat_playback_speed_percent", percent)
	)
	var movement := root.get_node("MovementSpeedRow/ExplorationSpeedSlider") as HSlider
	var movement_caption := root.get_node("MovementSpeedRow/ExplorationSpeedCaption") as Label
	_bind_label(movement_caption, "Exploration travel speed  •  %d%%" % settings.exploration_speed_percent, Color("e0e2e5"), 15)
	_clear_value_changed_connections(movement)
	movement.value = settings.exploration_speed_percent
	movement.tooltip_text = "%d%%  •  %.3f seconds per held step" % [settings.exploration_speed_percent, HeldMovementController.BASE_INTERVAL_SECONDS * 100.0 / float(settings.exploration_speed_percent)]
	movement.value_changed.connect(func(value: float) -> void:
		var percent := int(value)
		movement_caption.text = "Exploration travel speed  •  %d%%" % percent
		movement.tooltip_text = "%d%%  •  %.3f seconds per held step" % [percent, HeldMovementController.BASE_INTERVAL_SECONDS * 100.0 / float(percent)]
		setting_changed.emit(&"exploration_speed_percent", percent)
	)


func _bind_accessibility(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Accessibility/AccessibilitySettingsScroll/AccessibilitySettingsPanel/Content")
	_bind_toggle(root.get_node("ReducedMotion") as CheckButton, settings.reduced_motion, &"reduced_motion")


func _bind_controls(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content")
	_bind_toggle(root.get_node("AutoSwitchToMelee") as CheckButton, settings.auto_switch_to_melee, &"auto_switch_to_melee")
	_bind_toggle(root.get_node("ShowExplorationMinimap") as CheckButton, settings.show_exploration_minimap, &"show_exploration_minimap")
	_bind_toggle(root.get_node("AutojournalEnabled") as CheckButton, settings.autojournal_enabled, &"autojournal_enabled")
	for entry: Dictionary in CONTROL_HELP:
		var card := root.get_node("ControlHelp%s" % String(entry["title"]).replace(" ", "")) as PanelContainer
		var row := card.get_node("Row") as BoxContainer
		_bind_label(row.get_node("Identity") as Label, "%s  •  %s" % [entry["title"], entry["keys"]], GOLD, 14)
		_bind_label(row.get_node("Detail") as Label, String(entry["detail"]), MUTED, 13)
		(row.get_node("Identity") as Label).custom_minimum_size.x = 0.0 if _layout_profile == UiLayoutProfile.COMPACT else 330.0


func _bind_diagnostics(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceTabs/Diagnostics/DiagnosticsSettingsScroll/DiagnosticsSettingsPanel/Content")
	_bind_toggle(root.get_node("TopologyDebug") as CheckButton, settings.topology_debug, &"topology_debug")


func _bind_option(picker: OptionButton, entries: Array[Dictionary], selected_id: String, setting_id: StringName) -> void:
	_clear_item_selected_connections(picker)
	picker.clear()
	for entry: Dictionary in entries:
		picker.add_item(entry["label"])
		picker.set_item_metadata(picker.item_count - 1, entry["id"])
		if entry["id"] == selected_id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: setting_changed.emit(setting_id, String(picker.get_item_metadata(index))))


func _bind_slider(slider: Range, value: float, setting_id: StringName) -> void:
	_clear_value_changed_connections(slider)
	slider.value = value
	slider.value_changed.connect(func(changed_value: float) -> void: setting_changed.emit(setting_id, changed_value))


func _bind_toggle(toggle: CheckButton, enabled: bool, setting_id: StringName) -> void:
	_clear_toggled_connections(toggle)
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: setting_changed.emit(setting_id, value))


func _bind_action(button: Button, action: Callable) -> void:
	_clear_pressed_connections(button)
	button.custom_minimum_size.y = 38.0
	button.pressed.connect(action)


static func _bind_label(label: Label, text: String, color: Color, size: int) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", size)


static func _clear_pressed_connections(button: Button) -> void:
	for connection: Dictionary in button.pressed.get_connections():
		button.pressed.disconnect(connection["callable"] as Callable)


static func _clear_toggled_connections(button: BaseButton) -> void:
	for connection: Dictionary in button.toggled.get_connections():
		button.toggled.disconnect(connection["callable"] as Callable)


static func _clear_item_selected_connections(picker: OptionButton) -> void:
	for connection: Dictionary in picker.item_selected.get_connections():
		picker.item_selected.disconnect(connection["callable"] as Callable)


static func _clear_value_changed_connections(control: Range) -> void:
	for connection: Dictionary in control.value_changed.get_connections():
		control.value_changed.disconnect(connection["callable"] as Callable)


static func _clear_text_changed_connections(control: LineEdit) -> void:
	for connection: Dictionary in control.text_changed.get_connections():
		control.text_changed.disconnect(connection["callable"] as Callable)


static func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
