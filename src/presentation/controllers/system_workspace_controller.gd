class_name SystemWorkspaceController
extends RefCounted

const SaveSlotPreviewScript := preload("res://src/core/view/save_slot_preview.gd")
const HeldMovementControllerScript := preload("res://src/presentation/held_movement_controller.gd")

signal action_requested(action_id: StringName, value: Variant)
signal setting_changed(setting_id: StringName, value: Variant)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")

var _save_previews: Array[SaveSlotPreview] = []
var _selected_save_key: String = ""
var _save_detail: VBoxContainer
var _load_selected: Button
var _layout_profile: StringName = UiLayoutProfile.WIDE


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id


func set_save_previews(previews: Array[SaveSlotPreview]) -> void:
	_save_previews = previews.duplicate()
	if not _save_previews.any(func(preview: SaveSlotPreview) -> bool: return _key(preview) == _selected_save_key):
		_selected_save_key = _key(_save_previews[0]) if not _save_previews.is_empty() else ""


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
		_add_card(rows, "No saves for this campaign", "Quick Save creates the first validated slot.", "")
	else:
		var group := ButtonGroup.new()
		for preview: SaveSlotPreview in _save_previews:
			var button := Button.new()
			button.name = "SavePreview_%s_%s" % [preview.slot_id, String(preview.source)]
			button.text = "%s  •  %s\n%s" % [preview.slot_id, preview.source_label(), preview.status_label()]
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
	var footer := HBoxContainer.new()
	footer.name = "SaveWorkspaceFooter"
	footer.add_theme_constant_override("separation", 5)
	parent.add_child(footer)
	_add_action(footer, "Quick Save", &"save", "quick")
	_load_selected = _add_action(footer, "Load Selected", &"", null)
	_load_selected.name = "LoadSelectedSave"
	_load_selected.pressed.connect(_load_selected_preview)
	_add_action(footer, "Refresh", &"refresh_saves", null)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	_add_action(footer, "Campaign Library", &"campaigns", null)
	var end_adventure := _add_action(footer, "End Adventure", &"end_adventure", null)
	end_adventure.disabled = view.pending_interaction != null and view.pending_interaction.kind != InteractionRequest.COMBAT
	end_adventure.tooltip_text = "Resolve the current interaction first." if end_adventure.disabled else "Close this campaign session without quitting Realmz Rebuilt."


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
	_save_detail.add_child(_label("%s  •  %s" % [preview.slot_id, preview.source_label()], GOLD, 18))
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


func _selected_preview() -> SaveSlotPreview:
	for preview: SaveSlotPreview in _save_previews:
		if _key(preview) == _selected_save_key:
			return preview
	return null


func _key(preview: SaveSlotPreview) -> String:
	return "%s:%s" % [preview.slot_id, String(preview.source)] if preview != null else ""


func _build_display_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Display", "Interface scale, text size, and window mode apply immediately.")
	var ui_scale := OptionButton.new()
	for entry: Dictionary in [{"label": "UI scale: Auto", "id": PresentationSettings.UI_SCALE_AUTO}, {"label": "UI scale: 100%", "id": PresentationSettings.UI_SCALE_100}, {"label": "UI scale: 125%", "id": PresentationSettings.UI_SCALE_125}, {"label": "UI scale: 150%", "id": PresentationSettings.UI_SCALE_150}]:
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
	window_mode.add_item("Windowed"); window_mode.set_item_metadata(0, PresentationSettings.WINDOWED)
	window_mode.add_item("Borderless fullscreen"); window_mode.set_item_metadata(1, PresentationSettings.BORDERLESS_FULLSCREEN)
	window_mode.select(1 if settings.window_mode == PresentationSettings.BORDERLESS_FULLSCREEN else 0)
	window_mode.item_selected.connect(func(index: int) -> void: setting_changed.emit(&"window_mode", String(window_mode.get_item_metadata(index))))
	_add_setting_row(content, "Window mode", window_mode)
	_add_setting_toggle(content, "Use topology-derived 3D dungeons", settings.dungeon_3d, &"dungeon_3d")


func _build_audio_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Audio", "Presentation audio never advances the simulation.")
	var volume := HSlider.new()
	volume.min_value = 0.0; volume.max_value = 1.0; volume.step = 0.05; volume.value = settings.master_volume
	volume.tooltip_text = "Master volume %d%%" % int(round(settings.master_volume * 100.0))
	volume.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"master_volume", value))
	_add_setting_row(content, "Master volume  •  %d%%" % int(round(settings.master_volume * 100.0)), volume)


func _build_accessibility_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Accessibility", "Accessibility changes presentation only; Classic rules remain fixed.")
	_add_setting_toggle(content, "Reduced motion", settings.reduced_motion, &"reduced_motion")
	content.add_child(_label("Reduced motion settles combat feedback in one presentation frame without skipping committed events.", MUTED, 14))


func _build_controls_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Controls", "Exploration cadence and convenience controls.")
	var movement_row := HBoxContainer.new()
	var movement_speed := HSlider.new()
	movement_speed.min_value = 25.0; movement_speed.max_value = 400.0; movement_speed.step = 25.0; movement_speed.value = settings.exploration_speed_percent
	movement_speed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	movement_speed.tooltip_text = "%d%%  •  %.3f seconds per held step" % [settings.exploration_speed_percent, HeldMovementControllerScript.BASE_INTERVAL_SECONDS * 100.0 / float(settings.exploration_speed_percent)]
	movement_speed.value_changed.connect(func(value: float) -> void: setting_changed.emit(&"exploration_speed_percent", int(value)))
	movement_row.add_child(movement_speed)
	_add_setting_row(content, "Exploration speed  •  %d%%" % settings.exploration_speed_percent, movement_row)
	_add_setting_toggle(content, "Auto Switch To Melee Weapon", settings.auto_switch_to_melee, &"auto_switch_to_melee")
	_add_setting_toggle(content, "Show travel preview on the exploration map", settings.show_exploration_minimap, &"show_exploration_minimap")
	_add_setting_toggle(content, "Add eligible scenario text to Notes automatically", settings.autojournal_enabled, &"autojournal_enabled")
	content.add_child(_label("Move: arrows, WASD, or numpad  •  Hold Shift in battle to reveal adjacent movement costs  •  Space skips presentation playback", MUTED, 14))


func _build_diagnostics_tab(parent: VBoxContainer, settings: PresentationSettings) -> void:
	var content := _settings_panel(parent, "Diagnostics", "Developer overlays expose detached topology facts without becoming gameplay authority.")
	_add_setting_toggle(content, "Show topology diagnostics", settings.topology_debug, &"topology_debug")
	content.add_child(_label("Topology diagnostics display movement, visibility, and trigger projections derived from the same authoritative map model.", MUTED, 14))


func _settings_panel(parent: VBoxContainer, title: String, description: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = "%sSettingsPanel" % title.replace(" ", "")
	panel.theme_type_variation = &"ClassicTextWell"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
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


func _add_setting_row(parent: Container, label: String, control: Control) -> void:
	var row := BoxContainer.new()
	row.vertical = _layout_profile == UiLayoutProfile.COMPACT
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var caption := _label(label, Color("e0e2e5"), 15)
	caption.custom_minimum_size.x = 0.0 if row.vertical else 230.0
	row.add_child(caption)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)


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
	panel.theme_type_variation = &"ClassicTextWell"
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
	var toggle := CheckButton.new()
	toggle.text = label
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: setting_changed.emit(setting_id, value))
	parent.add_child(toggle)


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
