## Five-category shell for the shared System workspace.
class_name SystemPreferencesLayout
extends SystemWorkspace

signal category_selected(category: StringName)
signal setting_changed(setting_id: StringName, value: Variant)
signal action_requested(action_id: StringName, value: Variant)

const PREFERENCE_SECTIONS: Array[StringName] = [&"Display", &"Audio", &"Accessibility", &"Controls", &"Diagnostics"]

var _save_mode := false


func _ready() -> void:
	tabs().tabs_visible = false
	for category: StringName in PREFERENCE_SECTIONS:
		var button := get_node("SystemWorkspaceBody/SystemCategoryRail/%s" % category) as Button
		button.set_meta("setting_id", category)
		button.pressed.connect(show_category.bind(category))
	show_category(&"Display")


func prepare(compact: bool) -> void:
	visible = true
	(get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControllerSettings/Content") as GridContainer).columns = 1 if compact else 2
	(get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns") as BoxContainer).vertical = false
	(get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/NewSaveSlotRow") as BoxContainer).vertical = compact
	_apply_compact_rows(self, compact)
	_clear(save_slot_rows())
	get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/Empty").visible = false
	get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Empty").visible = false
	save_detail_record().visible = false
	if _save_mode:
		show_saves()
	else:
		show_category(_current_category())


func show_category(category: StringName) -> void:
	var index := PREFERENCE_SECTIONS.find(category)
	if index < 0:
		return
	_save_mode = false
	tabs().current_tab = index + 1
	_sync_category_rail(index + 1)
	category_selected.emit(category)


func show_saves() -> void:
	_save_mode = true
	tabs().current_tab = 0
	_sync_category_rail(0)


func _sync_category_rail(index: int) -> void:
	var rail := get_node("SystemWorkspaceBody/SystemCategoryRail") as VBoxContainer
	rail.visible = not _save_mode
	for category_index: int in PREFERENCE_SECTIONS.size():
		var button := get_node("SystemWorkspaceBody/SystemCategoryRail/%s" % PREFERENCE_SECTIONS[category_index]) as Button
		button.button_pressed = not _save_mode and category_index + 1 == index
	get_node("ControlsDraftFooter").visible = not _save_mode and index == 4


func _current_category() -> StringName:
	var index := tabs().current_tab - 1
	return PREFERENCE_SECTIONS[index] if index >= 0 and index < PREFERENCE_SECTIONS.size() else &"Display"


func bind_indoor_icon(index: int, media: ClassicMediaCatalog) -> void:
	var picker := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/WorldViewGroup/Content/IndoorPartyIcon") as IndoorPartyIconPicker
	if not picker.icon_selected.is_connected(_on_indoor_icon_selected):
		picker.icon_selected.connect(_on_indoor_icon_selected)
	picker.bind_selection(index, media)


func _on_indoor_icon_selected(index: int) -> void:
	setting_changed.emit(&"indoor_party_icon", index)


func bind_audio(settings: PresentationSettings) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Audio/AudioSettingsScroll/AudioSettingsPanel/Content")
	_bind_volume_row(root.get_node("MasterVolumeRow") as BoxContainer, "Master volume", settings.master_volume, &"master_volume")
	_bind_volume_row(root.get_node("SoundVolumeRow") as BoxContainer, "Sound effects", settings.sound_volume, &"sound_volume")
	_bind_volume_row(root.get_node("MusicVolumeRow") as BoxContainer, "Music", settings.music_volume, &"music_volume")
	_bind_toggle(root.get_node("MusicEnabled") as CheckButton, settings.music_enabled, &"music_enabled")
	_bind_toggle(root.get_node("ReducedSound") as CheckButton, settings.reduced_sound, &"reduced_sound")
	_bind_action(root.get_node("OpenMusicPlaylist") as Button, func() -> void: action_requested.emit(&"music_playlist", null))


func bind_pacing(settings: PresentationSettings) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Audio/Pacing/PacingSettingsScroll/PacingSettingsPanel/Content")
	_bind_toggle(root.get_node("HurrySpellResolution") as CheckButton, settings.hurry_spell_resolution, &"hurry_spell_resolution")
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


func bind_accessibility(settings: PresentationSettings) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Accessibility/AccessibilitySettingsScroll/AccessibilitySettingsPanel/Content")
	_bind_toggle(root.get_node("ReducedMotion") as CheckButton, settings.reduced_motion, &"reduced_motion")
	var text_scale := root.get_node("TextScaleRow/TextScaleSlider") as HSlider
	var text_scale_caption := root.get_node("TextScaleRow/Caption") as Label
	var typography_picker := root.get_node("TypographyRow/TypographyPicker") as OptionButton
	var sample := root.get_node("TextPreview/Content/Sample") as Label
	var preview_detail := root.get_node("TextPreview/Content/PreviewDetail") as Label
	var update_preview := func(scale: float, typography_mode: String) -> void:
		var classic_mode := typography_mode == PresentationSettings.TYPOGRAPHY_CLASSIC
		var font_path := ClassicTypography.THELDROW_PATH if classic_mode else ClassicTypography.READABLE_UI_PATH
		var preview_font := load(font_path) as Font
		var readable_fallback := load(ClassicTypography.READABLE_UI_PATH) as Font
		if classic_mode and preview_font is FontFile and readable_fallback != null:
			(preview_font as FontFile).fallbacks = [readable_fallback]
		var size := int(round((17.0 if classic_mode else 15.0) * scale))
		sample.add_theme_font_override("font", preview_font)
		sample.add_theme_font_size_override("font_size", size)
		preview_detail.add_theme_font_override("font", preview_font)
		preview_detail.add_theme_font_size_override("font_size", maxi(12, size - 2))
		text_scale_caption.text = "Text size  •  %d%%" % int(round(scale * 100.0))
		text_scale.tooltip_text = "Text scale %d%%" % int(round(scale * 100.0))
	update_preview.call(settings.text_scale, settings.typography_mode)
	_clear_value_changed_connections(text_scale)
	text_scale.value = settings.text_scale
	text_scale.value_changed.connect(func(value: float) -> void:
		update_preview.call(value, String(typography_picker.get_item_metadata(typography_picker.selected)))
		setting_changed.emit(&"text_scale", value)
	)
	var text_preview_values: Array[Dictionary] = [
		{"label": "Classic Realmz fonts", "id": PresentationSettings.TYPOGRAPHY_CLASSIC},
		{"label": "Readable modern fonts", "id": PresentationSettings.TYPOGRAPHY_READABLE},
	]
	_bind_option(typography_picker, text_preview_values, settings.typography_mode, &"typography_mode", func(index: int) -> void:
		update_preview.call(settings.text_scale, String(typography_picker.get_item_metadata(index)))
	)


func _bind_volume_row(row: BoxContainer, title: String, value: float, setting_id: StringName) -> void:
	_bind_label(row.get_node("Caption") as Label, "%s  •  %d%%" % [title, int(round(value * 100.0))], Color("e0e2e5"), 15)
	var slider := row.get_child(1) as HSlider
	_bind_slider(slider, value, setting_id)
	slider.tooltip_text = "%s volume %d%%" % [title, int(round(value * 100.0))]


func _bind_option(picker: OptionButton, entries: Array[Dictionary], selected_id: String, setting_id: StringName, selection_changed: Callable = Callable()) -> void:
	_clear_item_selected_connections(picker)
	picker.clear()
	for entry: Dictionary in entries:
		picker.add_item(entry["label"])
		picker.set_item_metadata(picker.item_count - 1, entry["id"])
		if entry["id"] == selected_id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void:
		if selection_changed.is_valid(): selection_changed.call(index)
		setting_changed.emit(setting_id, String(picker.get_item_metadata(index)))
	)


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


func tabs() -> TabContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs") as TabContainer


func save_slot_rows() -> VBoxContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/SaveSlotScroll/SaveSlotRows") as VBoxContainer


func save_browser_empty() -> PanelContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/Empty") as PanelContainer


func save_detail_record() -> VBoxContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Record") as VBoxContainer


func save_detail_empty() -> PanelContainer:
	return get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Empty") as PanelContainer
