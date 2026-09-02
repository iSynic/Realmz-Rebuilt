class_name SystemWorkspaceController
extends RefCounted

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")
const HeldMovementControllerScript := preload("res://src/presentation/held_movement_controller.gd")

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
var _save_detail: VBoxContainer
var _load_selected: Button
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _save_and_quit_mode: bool = false


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_save_previews = previews.duplicate()
	if not _save_previews.any(func(preview: SaveSlotPreview) -> bool: return _key(preview) == _selected_save_key):
		_selected_save_key = _key(_save_previews[0]) if not _save_previews.is_empty() else ""


func set_save_and_quit_mode(enabled: bool) -> void:
	if enabled and not _save_and_quit_mode:
		for preview: SaveSlotPreview in _save_previews:
			if preview.source == SaveSlotPreviewScript.PRIMARY and preview.can_load:
				_selected_save_key = _key(preview)
				break
	_save_and_quit_mode = enabled


func present(parent: VBoxContainer, view: GameView, settings: PresentationSettings) -> void:
	if parent == null or view == null or settings == null:
		return
	_add_header(parent, view)
	var tabs := TabContainer.new()
	tabs.name = "SystemWorkspaceTabs"
	tabs.clip_tabs = true
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(tabs)
	_build_save_tab(_tab(tabs, "Save & Load"), view)
	_build_display_tab(_tab(tabs, "Display"), settings)
	_build_audio_tab(_tab(tabs, "Audio"), settings)
	_build_pacing_tab(_tab(tabs, "Pacing"), settings)
	_build_accessibility_tab(_tab(tabs, "Accessibility"), settings)
	_build_controls_tab(_tab(tabs, "Controls"), settings)
	_build_diagnostics_tab(_tab(tabs, "Diagnostics"), settings)


func _add_header(parent: VBoxContainer, view: GameView) -> void:
	var row := HBoxContainer.new()
	row.name = "SystemHeader"
	parent.add_child(row)
	var campaign := view.campaign_summary.title if view.campaign_summary != null else view.campaign_id
	var fact := _label("%s  •  %s" % [campaign, view.rules_version], CYAN, 13)
	fact.name = "SystemCampaignContext"
	fact.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fact.max_lines_visible = 2
	fact.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(fact)


func _build_save_tab(parent: VBoxContainer, view: GameView) -> void:
	var columns := HBoxContainer.new()
	columns.name = "SaveWorkspaceColumns"
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 6)
	parent.add_child(columns)
	var browser := _pane(columns, "SaveSlotBrowser", "Save Slots", 0.85)
	var detail := _pane(columns, "SaveSlotDetail", "Selected Record", 1.25)
	_save_detail = VBoxContainer.new()
	_save_detail.name = "SaveSlotDetailBody"
	_save_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_detail.add_theme_constant_override("separation", 5)
	detail.add_child(_save_detail)
	var scroll := _scroll("SaveSlotScroll")
	browser.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "SaveSlotRows"
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	if _save_previews.is_empty():
		_add_card(rows, "No saves for this campaign", "Return to party setup and begin a new adventure." if view.party_setup_available else "Use either Quick Save slot or create a named save below.", "")
	else:
		var group := ButtonGroup.new()
		for preview: SaveSlotPreview in _save_previews:
			var button := Button.new()
			button.name = "SavePreview_%s_%s" % [preview.slot_id, String(preview.source)]
			button.text = "%s  •  %s\n%s" % [slot_label(preview.slot_id), preview.source_label(), preview.status_label()]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size.y = 54.0
			button.toggle_mode = true
			button.button_group = group
			button.button_pressed = _key(preview) == _selected_save_key
			button.pressed.connect(_select_save.bind(preview))
			rows.add_child(button)
	_build_save_footer(parent, view)
	_refresh_save_detail()


func _build_save_footer(parent: VBoxContainer, view: GameView) -> void:
	var footer := VBoxContainer.new()
	footer.name = "SaveWorkspaceFooter"
	footer.add_theme_constant_override("separation", 5)
	parent.add_child(footer)
	var actions := HBoxContainer.new()
	actions.name = "SaveWorkspaceActions"
	actions.add_theme_constant_override("separation", 5)
	footer.add_child(actions)
	if _save_and_quit_mode:
		var save_and_quit := _add_action(actions, "Save and Quit", &"", null)
		save_and_quit.name = "SaveAndQuitSelected"
		save_and_quit.tooltip_text = "Save to the selected slot, then quit Realmz Rebuilt."
		save_and_quit.pressed.connect(_save_selected_and_quit)
	elif not view.party_setup_available:
		_add_action(actions, "Quick Save 1", &"save", "quick")
		_add_action(actions, "Quick Save 2", &"save", "quick-2")
		var save_selected := _add_action(actions, "Save Selected", &"", null)
		save_selected.name = "SaveSelectedSlot"
		save_selected.pressed.connect(_save_selected_preview)
	_load_selected = _add_action(actions, "Load Selected", &"", null)
	_load_selected.name = "LoadSelectedSave"
	_load_selected.pressed.connect(_load_selected_preview)
	_add_action(actions, "Refresh", &"refresh_saves", null)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	var end_adventure := _add_action(actions, "Main Menu", &"end_adventure", null)
	end_adventure.disabled = view.pending_interaction != null and view.pending_interaction.kind != InteractionRequest.COMBAT
	end_adventure.tooltip_text = "Resolve the current interaction first." if end_adventure.disabled else "Close this campaign session and return to the Realmz Rebuilt main menu."
	if not _save_and_quit_mode and not view.party_setup_available:
		_build_new_save_row(footer)


func _build_new_save_row(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "NewSaveSlotRow"
	row.add_theme_constant_override("separation", 5)
	parent.add_child(row)
	var slot_name := LineEdit.new()
	slot_name.name = "NewSaveSlotName"
	slot_name.theme_type_variation = &"ClassicTheldrowLineEdit"
	slot_name.placeholder_text = "New slot name (letters, numbers, - or _)"
	slot_name.max_length = 128
	slot_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slot_name)
	var save_new := _add_action(row, "Save New Slot", &"", null)
	save_new.name = "SaveNewSlot"
	save_new.disabled = true
	var refresh := func(value: String) -> void:
		save_new.disabled = not slot_id_is_portable(value)
		save_new.tooltip_text = "Use only letters, numbers, hyphens, or underscores." if save_new.disabled else "Create or replace this named save slot."
	slot_name.text_changed.connect(refresh)
	save_new.pressed.connect(func() -> void: action_requested.emit(&"save", slot_name.text))
	refresh.call(slot_name.text)


func _select_save(preview: SaveSlotPreview) -> void:
	_selected_save_key = _key(preview)
	_refresh_save_detail()


func _refresh_save_detail() -> void:
	if _save_detail == null or _load_selected == null:
		return
	_clear(_save_detail)
	var preview := _selected_preview()
	_load_selected.disabled = preview == null or not preview.can_load
	_load_selected.tooltip_text = "Select a validated save record." if preview == null else preview.error_message if not preview.can_load else "Restore this validated %s record." % preview.source_label().to_lower()
	if preview == null:
		_add_card(_save_detail, "No selected record", "Save slots appear at left.", "")
		return
	_save_detail.add_child(_label("%s  •  %s" % [slot_label(preview.slot_id), preview.source_label()], GOLD, 18))
	_save_detail.add_child(_label(preview.status_label(), CYAN if preview.can_load else Color("d48a78"), 14))
	if preview.status != SaveSlotPreviewScript.VALID:
		_save_detail.add_child(_label(preview.error_message, MUTED, 14))
		return
	var party := ", ".join(preview.character_names) if not preview.character_names.is_empty() else "No party members"
	_save_detail.add_child(_label("Day %d  •  %02d:%02d  •  %s %d,%d" % [preview.realmz_day, preview.realmz_hour, preview.realmz_minute, preview.map_id, preview.coordinate.x, preview.coordinate.y], CYAN, 15))
	_save_detail.add_child(_label(party, Color("e0e2e5"), 15))
	_save_detail.add_child(HSeparator.new())
	_save_detail.add_child(_label("Package %s" % preview.package_hash.left(12), MUTED, 13))
	_save_detail.add_child(_label("Rules %s" % preview.rules_version, MUTED, 13))
	if preview.modified_unix > 0:
		_save_detail.add_child(_label("Saved %s" % Time.get_datetime_string_from_unix_time(preview.modified_unix), MUTED, 13))


func _load_selected_preview() -> void:
	var preview := _selected_preview()
	if preview == null or not preview.can_load:
		return
	var action: StringName = &"load_backup" if preview.source == SaveSlotPreviewScript.BACKUP else &"load"
	action_requested.emit(action, preview.slot_id)


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


func _build_display_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Display", "Fit keeps the Classic application centered at wide resolutions. Interface density and text size remain independent; exact bitmap art stays at native 1× or 2× pixels.")
	var ui_scale := OptionButton.new()
	ui_scale.name = "InterfaceScalePicker"
	ui_scale.theme_type_variation = &"ClassicTheldrowOptionButton"
	for entry: Dictionary in [{"label": "Fit to window", "id": PresentationSettings.UI_SCALE_AUTO}, {"label": "Interface density: 100%", "id": PresentationSettings.UI_SCALE_100}, {"label": "Interface density: 125%", "id": PresentationSettings.UI_SCALE_125}, {"label": "Interface density: 150%", "id": PresentationSettings.UI_SCALE_150}]:
		ui_scale.add_item(entry["label"])
		ui_scale.set_item_metadata(ui_scale.item_count - 1, entry["id"])
		if entry["id"] == settings.ui_scale_mode: ui_scale.select(ui_scale.item_count - 1)
	ui_scale.item_selected.connect(func(index: int) -> void: setting_changed.emit(&"ui_scale_mode", String(ui_scale.get_item_metadata(index))))
	_add_setting_row(content, "Interface scale", ui_scale)
	var text_scale := HSlider.new()
	text_scale.min_value = 0.8; text_scale.max_value = 1.5; text_scale.step = 0.1; text_scale.value = settings.text_scale
	text_scale.tooltip_text = "Text scale %d%%" % int(round(settings.text_scale * 100.0))
	text_scale.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"text_scale", value))
	_add_setting_row(content, "Text size  •  %d%%" % int(round(settings.text_scale * 100.0)), text_scale)
	var typography := OptionButton.new()
	typography.name = "TypographyPicker"
	typography.theme_type_variation = &"ClassicTheldrowOptionButton"
	for entry: Dictionary in [
		{"label": "Classic Realmz fonts", "id": PresentationSettings.TYPOGRAPHY_CLASSIC},
		{"label": "Readable modern fonts", "id": PresentationSettings.TYPOGRAPHY_READABLE},
	]:
		typography.add_item(entry["label"])
		typography.set_item_metadata(typography.item_count - 1, entry["id"])
		if entry["id"] == settings.typography_mode:
			typography.select(typography.item_count - 1)
	typography.item_selected.connect(func(index: int) -> void: setting_changed.emit(&"typography_mode", String(typography.get_item_metadata(index))))
	_add_setting_row(content, "Typography", typography)
	var window_mode := OptionButton.new()
	window_mode.name = "WindowModePicker"
	window_mode.theme_type_variation = &"ClassicTheldrowOptionButton"
	window_mode.add_item("Windowed"); window_mode.set_item_metadata(0, PresentationSettings.WINDOWED)
	window_mode.add_item("Borderless fullscreen"); window_mode.set_item_metadata(1, PresentationSettings.BORDERLESS_FULLSCREEN)
	window_mode.select(1 if settings.window_mode == PresentationSettings.BORDERLESS_FULLSCREEN else 0)
	window_mode.item_selected.connect(func(index: int) -> void: setting_changed.emit(&"window_mode", String(window_mode.get_item_metadata(index))))
	_add_setting_row(content, "Window mode", window_mode)
	_add_setting_toggle(content, "Use topology-derived 3D dungeons", settings.dungeon_3d, &"dungeon_3d")
	_add_setting_toggle(content, "Classic exploration distance with visited outer tiles", settings.classic_exploration_visibility, &"classic_exploration_visibility")


func _build_audio_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Audio", "Presentation audio never advances the simulation.")
	var volume := HSlider.new()
	volume.min_value = 0.0; volume.max_value = 1.0; volume.step = 0.05; volume.value = settings.master_volume
	volume.tooltip_text = "Master volume %d%%" % int(round(settings.master_volume * 100.0))
	volume.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"master_volume", value))
	_add_setting_row(content, "Master volume  •  %d%%" % int(round(settings.master_volume * 100.0)), volume)
	var sound := HSlider.new()
	sound.min_value = 0.0; sound.max_value = 1.0; sound.step = 0.05; sound.value = settings.sound_volume
	sound.tooltip_text = "Sound effects volume %d%%" % int(round(settings.sound_volume * 100.0))
	sound.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"sound_volume", value))
	_add_setting_row(content, "Sound effects  •  %d%%" % int(round(settings.sound_volume * 100.0)), sound)
	var music := HSlider.new()
	music.min_value = 0.0; music.max_value = 1.0; music.step = 0.05; music.value = settings.music_volume
	music.tooltip_text = "Music volume %d%%" % int(round(settings.music_volume * 100.0))
	music.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"music_volume", value))
	_add_setting_row(content, "Music  •  %d%%" % int(round(settings.music_volume * 100.0)), music)
	_add_setting_toggle(content, "Music enabled", settings.music_enabled, &"music_enabled")
	_add_setting_toggle(content, "Reduce Classic modal sounds", settings.reduced_sound, &"reduced_sound")
	var playlist := Button.new()
	playlist.name = "OpenMusicPlaylist"
	playlist.text = "Open Music Playlist…"
	playlist.tooltip_text = "Configure Castle's 20 context slots as Play, Continue, or Off."
	playlist.pressed.connect(func() -> void: action_requested.emit(&"music_playlist", null))
	content.add_child(playlist)


func _build_accessibility_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Accessibility", "Accessibility changes presentation only; Classic rules remain fixed.")
	_add_setting_toggle(content, "Reduced motion", settings.reduced_motion, &"reduced_motion")
	content.add_child(_label("Reduced motion settles combat feedback in one presentation frame without skipping committed events.", MUTED, 14))


func _build_pacing_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Pacing", "Choose how long committed movement and animation remain on screen. Pacing never changes rules, turn order, movement points, or random results.")
	var combat_speed := HSlider.new()
	combat_speed.name = "CombatPlaybackSpeedSlider"
	combat_speed.min_value = 25.0
	combat_speed.max_value = 200.0
	combat_speed.step = 25.0
	combat_speed.tick_count = 8
	combat_speed.ticks_on_borders = true
	combat_speed.value = settings.combat_playback_speed_percent
	combat_speed.tooltip_text = "%d%%  •  affects movement, attacks, projectiles, spells, and result holds" % settings.combat_playback_speed_percent
	var combat_caption := _add_setting_row(content, "Combat & animation speed  •  %d%%" % settings.combat_playback_speed_percent, combat_speed)
	combat_caption.name = "CombatPlaybackSpeedCaption"
	combat_speed.value_changed.connect(func(value: float) -> void:
		var percent := int(value)
		combat_caption.text = "Combat & animation speed  •  %d%%" % percent
		combat_speed.tooltip_text = "%d%%  •  affects movement, attacks, projectiles, spells, and result holds" % percent
		setting_changed.emit(&"combat_playback_speed_percent", percent)
	)
	content.add_child(_label("100% is the designed combat pace. Castle separated global speed from Hurry Spell Resolution; this single control applies consistently to every combat visual.", MUTED, 14))
	var movement_speed := HSlider.new()
	movement_speed.name = "ExplorationSpeedSlider"
	movement_speed.min_value = 25.0
	movement_speed.max_value = 400.0
	movement_speed.step = 25.0
	movement_speed.tick_count = 16
	movement_speed.ticks_on_borders = true
	movement_speed.value = settings.exploration_speed_percent
	movement_speed.tooltip_text = "%d%%  •  %.3f seconds per held step" % [settings.exploration_speed_percent, HeldMovementControllerScript.BASE_INTERVAL_SECONDS * 100.0 / float(settings.exploration_speed_percent)]
	var movement_caption := _add_setting_row(content, "Exploration travel speed  •  %d%%" % settings.exploration_speed_percent, movement_speed)
	movement_caption.name = "ExplorationSpeedCaption"
	movement_speed.value_changed.connect(func(value: float) -> void:
		var percent := int(value)
		movement_caption.text = "Exploration travel speed  •  %d%%" % percent
		movement_speed.tooltip_text = "%d%%  •  %.3f seconds per held step" % [percent, HeldMovementControllerScript.BASE_INTERVAL_SECONDS * 100.0 / float(percent)]
		setting_changed.emit(&"exploration_speed_percent", percent)
	)


func _build_controls_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Controls", "Keyboard and mouse controls remain fixed so prompts, shortcuts, and visible commands always agree.")
	_add_setting_toggle(content, "Auto Switch To Melee Weapon", settings.auto_switch_to_melee, &"auto_switch_to_melee")
	_add_setting_toggle(content, "Show travel preview on the exploration map", settings.show_exploration_minimap, &"show_exploration_minimap")
	_add_setting_toggle(content, "Add eligible scenario text to Notes automatically", settings.autojournal_enabled, &"autojournal_enabled")
	for entry: Dictionary in CONTROL_HELP:
		_add_control_help(content, entry)


func _build_diagnostics_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Diagnostics", "Developer overlays expose detached topology facts without becoming gameplay authority.")
	_add_setting_toggle(content, "Show topology diagnostics", settings.topology_debug, &"topology_debug")
	content.add_child(_label("Topology diagnostics display movement, visibility, and trigger projections derived from the same authoritative map model.", MUTED, 14))


func _settings_panel(parent: VBoxContainer, title: String, description: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = "%sSettingsScroll" % title.replace(" ", "")
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var panel := PanelContainer.new()
	panel.name = "%sSettingsPanel" % title.replace(" ", "")
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 10)
	panel.add_child(content)
	var heading := _label(title, GOLD, 20)
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	content.add_child(_label(description, MUTED, 14))
	content.add_child(HSeparator.new())
	return content


func _add_control_help(parent: Container, entry: Dictionary) -> void:
	var card := PanelContainer.new()
	card.name = "ControlHelp%s" % String(entry["title"]).replace(" ", "")
	card.theme_type_variation = &"ClassicInset"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var row := BoxContainer.new()
	row.vertical = _layout_profile == UiLayoutProfile.COMPACT
	row.add_theme_constant_override("separation", 8)
	card.add_child(row)
	var identity := _label("%s  •  %s" % [entry["title"], entry["keys"]], GOLD, 14)
	identity.custom_minimum_size.x = 0.0 if row.vertical else 330.0
	row.add_child(identity)
	var detail := _label(String(entry["detail"]), MUTED, 13)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(detail)


func _add_setting_row(parent: Container, label: String, control: Control) -> Label:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ClassicInset"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var row := BoxContainer.new()
	row.vertical = _layout_profile == UiLayoutProfile.COMPACT
	row.add_theme_constant_override("separation", 10)
	card.add_child(row)
	var caption := _label(label, Color("e0e2e5"), 15)
	caption.custom_minimum_size.x = 0.0 if row.vertical else 230.0
	row.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return caption


func _tab(tabs: TabContainer, tab_name: String) -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = tab_name
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 6)
	tabs.add_child(tab)
	return tab


func _pane(parent: HBoxContainer, pane_name: String, title: String, ratio: float) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = pane_name
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = ratio
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var heading := _label(title, GOLD, 18)
	heading.theme_type_variation = &"ClassicHeading"
	content.add_child(heading)
	return content


func _scroll(node_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return scroll


func _add_action(parent: Container, label: String, action_id: StringName, value: Variant) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size.y = 38.0
	if not action_id.is_empty():
		button.pressed.connect(func() -> void: action_requested.emit(action_id, value))
	parent.add_child(button)
	return button


func _add_card(parent: Container, title: String, subtitle: String, detail: String) -> void:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"ClassicInset"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	panel.add_child(column)
	column.add_child(_label(title, GOLD, 16))
	if not subtitle.is_empty(): column.add_child(_label(subtitle, MUTED, 13))
	if not detail.is_empty(): column.add_child(_label(detail, Color.WHITE, 14))
	parent.add_child(panel)


func _add_setting_toggle(parent: Container, label: String, enabled: bool, setting_id: StringName) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"ClassicInset"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var toggle := CheckButton.new()
	toggle.name = String(setting_id).to_pascal_case()
	toggle.text = label
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: setting_changed.emit(setting_id, value))
	card.add_child(toggle)


func _label(text: String, color: Color, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_color_override("font_color", color)
	result.add_theme_font_size_override("font_size", size)
	return result


func _clear(parent: Container) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()
