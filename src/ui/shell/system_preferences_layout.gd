## Seven-category shell for the shared System workspace.
class_name SystemPreferencesLayout
extends SystemWorkspace

signal category_selected(category: StringName)
signal setting_changed(setting_id: StringName, value: Variant)
signal action_requested(action_id: StringName, value: Variant)

const PREFERENCE_SECTIONS: Array[StringName] = [&"Display", &"Interface", &"Controls", &"Audio", &"Pacing", &"Accessibility", &"Diagnostics"]

@export var setting_caption_width := 200.0
@export var setting_field_width := 246.0

var _save_mode := false
var _compact := false


static func interface_size_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for mode: String in PresentationSettings.UI_SCALE_MODES:
		options.append({"label": "Auto" if mode == PresentationSettings.UI_SCALE_AUTO else "%s%%" % mode, "id": mode})
	return options


static func display_mode_options() -> Array[Dictionary]:
	return [
		{"label": "Responsive", "id": PresentationSettings.DISPLAY_RESPONSIVE},
		{"label": "Integer: whole window", "id": PresentationSettings.DISPLAY_INTEGER_WINDOW},
		{"label": "Integer: world canvas", "id": PresentationSettings.DISPLAY_INTEGER_CANVAS},
		{"label": "Fill window", "id": PresentationSettings.DISPLAY_FILL_WINDOW},
	]


static func refresh_interface_size_feedback(workspace: Control, settings: PresentationSettings) -> void:
	var feedback := workspace.get_node_or_null("SystemWorkspaceBody/SystemWorkspaceTabs/Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/Window & Scale/DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content/InterfaceSizeFeedback") as Label
	if feedback == null or workspace.get_window() == null:
		return
	var output := DisplayScalingPolicy.geometry(workspace.get_window().size, settings.display_scaling_mode)
	var profile := UiLayoutProfile.for_viewport(Vector2(output["source_size"]), settings.ui_scale_mode, settings.display_scaling_mode)
	var text := "Draft interface size: %d%%" % roundi(profile.ui_scale * 100.0)
	if settings.display_scaling_mode in [PresentationSettings.DISPLAY_INTEGER_WINDOW, PresentationSettings.DISPLAY_FILL_WINDOW]:
		text = "Draft: %d%% logical · %d%% on screen" % [roundi(profile.ui_scale * 100.0), roundi(profile.ui_scale * float(output["scale"]) * 100.0)]
	if profile.scale_limited:
		text += " · %s requested, limited by window size" % ("Auto" if settings.ui_scale_mode == PresentationSettings.UI_SCALE_AUTO else "%s%%" % settings.ui_scale_mode)
	feedback.text = text


func _ready() -> void:
	tabs().tabs_visible = false
	var search := get_node("PreferencesSearch") as PreferencesSearch
	search.bind_pages(tabs())
	search.result_selected.connect(_focus_search_result)
	for category: StringName in PREFERENCE_SECTIONS:
		var button := get_node("SystemWorkspaceBody/SystemCategoryRail/%s" % category) as Button
		button.set_meta("setting_id", category)
		button.pressed.connect(show_category.bind(category))
	var compact_picker := get_node("CompactCategory") as OptionButton
	compact_picker.item_selected.connect(func(index: int) -> void: show_category(PREFERENCE_SECTIONS[index]))
	for control: Node in tabs().find_children("*", "Control", true, false):
		if control is BaseButton or control is Range:
			(control as Control).focus_entered.connect(_show_context_help.bind(control))
			(control as Control).mouse_entered.connect(_show_context_help.bind(control))
	show_category(&"Display")


func prepare(compact: bool) -> void:
	visible = true
	_compact = compact
	var controller_tabs := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content") as TabContainer
	controller_tabs.set_tab_title(0, "Bindings")
	controller_tabs.set_tab_title(1, "Tuning")
	(get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns") as BoxContainer).vertical = false
	(get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceFooter/NewSaveSlotRow") as BoxContainer).vertical = compact
	_apply_compact_rows(self, compact)
	_apply_preference_row_density(compact)
	clear_variable_save_rows()
	get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotBrowser/Content/Empty").visible = false
	get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Save & Load/SaveWorkspaceColumns/SaveSlotDetail/Content/SaveSlotDetailBody/Empty").visible = false
	save_detail_record().visible = false
	if _save_mode:
		show_saves()
	else:
		show_category(_current_category())


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_apply_preference_row_density(_compact)


func show_category(category: StringName) -> void:
	var index := PREFERENCE_SECTIONS.find(category)
	if index < 0:
		return
	_save_mode = false
	tabs().current_tab = tabs().get_node(NodePath(category)).get_index()
	_sync_category_rail(tabs().current_tab)
	_update_screen_heading(false)
	(get_node("CompactCategory") as OptionButton).select(index)
	category_selected.emit(category)


func show_saves() -> void:
	_save_mode = true
	tabs().current_tab = 0
	_sync_category_rail(0)
	_update_screen_heading(true)


func _update_screen_heading(save_mode: bool) -> void:
	var ancestor := get_parent()
	while ancestor != null:
		if ancestor is SystemScreen:
			(ancestor as SystemScreen).set_mode_title(save_mode)
			return
		ancestor = ancestor.get_parent()


func set_save_record_order(record: VBoxContainer, compact: bool) -> void:
	var location := record.get_node("Location")
	var party := record.get_node("Party")
	var map_preview := record.get_node("MapPreview")
	var map_status := record.get_node("MapPreviewStatus")
	var error := record.get_node("Error")
	record.move_child(map_preview, 2)
	record.move_child(map_status, 3)
	record.move_child(error, 4)
	record.move_child(location, 5)
	record.move_child(party, 6)
	if compact:
		record.move_child(location, 2)
		record.move_child(party, 3)
		record.move_child(map_preview, 4)
		record.move_child(map_status, 5)


static func slot_label(slot_id: String) -> String:
	if slot_id.length() == 1 and SaveSlotPreview.SCENARIO_SLOTS.contains(slot_id):
		return "Slot %s" % slot_id
	match slot_id:
		"quick": return "Quick Save 1"
		"quick-2": return "Quick Save 2"
		_: return slot_id


func _sync_category_rail(index: int) -> void:
	var rail := get_node("SystemWorkspaceBody/SystemCategoryRail") as VBoxContainer
	rail.visible = not _save_mode and not _compact
	get_node("CompactCategory").visible = not _save_mode and _compact
	get_node("PreferencesSearch").visible = not _save_mode
	get_node("SystemWorkspaceBody/ContextHelp").visible = not _save_mode and not _compact
	for category_index: int in PREFERENCE_SECTIONS.size():
		var button := get_node("SystemWorkspaceBody/SystemCategoryRail/%s" % PREFERENCE_SECTIONS[category_index]) as Button
		button.button_pressed = not _save_mode and String(tabs().get_child(index).name) == String(PREFERENCE_SECTIONS[category_index])
	get_node("PreferencesFooter").visible = not _save_mode


func _show_context_help(control: Control) -> void:
	var heading := "Settings"
	var row := control.get_parent()
	if row.is_in_group(&"system_setting_rows") and row.get_child(0) is Label:
		heading = (row.get_child(0) as Label).text
	elif control is BaseButton:
		heading = (control as BaseButton).text
	(get_node("SystemWorkspaceBody/ContextHelp/Heading") as Label).text = heading
	(get_node("SystemWorkspaceBody/ContextHelp/Detail") as Label).text = control.tooltip_text if not control.tooltip_text.is_empty() else "Changes stay in this draft until Apply. Cancel keeps your current settings."


func _focus_search_result(category: StringName, target: Control) -> void:
	show_category(category)
	var child: Node = target
	while child.get_parent() != null and child != tabs():
		var parent := child.get_parent()
		if parent is TabContainer:
			(parent as TabContainer).current_tab = child.get_index()
		child = parent
	(get_node("PreferencesSearch") as PreferencesSearch).hide_results()
	target.grab_focus.call_deferred()
	_scroll_to_setting.call_deferred(target)


func _scroll_to_setting(target: Control) -> void:
	var ancestor := target.get_parent()
	while ancestor != null and ancestor != self:
		if ancestor is ScrollContainer:
			(ancestor as ScrollContainer).ensure_control_visible(target)
		ancestor = ancestor.get_parent()


func _current_category() -> StringName:
	var category := StringName(tabs().get_current_tab_control().name)
	return category if category in PREFERENCE_SECTIONS else &"Display"


func _apply_preference_row_density(_compact: bool) -> void:
	var profile := UiSizing.profile_for(self)
	var scale := profile.ui_scale if profile != null else 1.0
	for row: Node in find_children("*", "BoxContainer", true, false):
		if not row.is_in_group(&"system_setting_rows"):
			continue
		(row as BoxContainer).vertical = false
		var caption := row.get_child(0) as Label
		if caption != null:
			UiSizing.minimum_size(caption, Vector2(setting_caption_width, 0.0))
			caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		for child: Node in row.get_children():
			if child is OptionButton or child is HSlider or child is Button:
				(child as Control).size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				UiSizing.minimum_size(child as Control, Vector2(setting_field_width, 0.0))

	for toggle: Node in find_children("*", "CheckButton", true, false):
		_fit_toggle(toggle as CheckButton, (setting_caption_width + setting_field_width + 8.0) * scale)


func _fit_toggle(toggle: CheckButton, maximum_width: float) -> void:
	var font := toggle.get_theme_font(&"font")
	var text_width := font.get_string_size(toggle.text, HORIZONTAL_ALIGNMENT_LEFT, -1, toggle.get_theme_font_size(&"font_size")).x
	var icon_width := maxf(toggle.get_theme_icon(&"checked").get_width(), toggle.get_theme_icon(&"unchecked").get_width())
	var margins := toggle.get_theme_stylebox(&"normal").get_minimum_size().x
	var available := tabs().size.x if tabs().size.x > 32.0 else maximum_width
	var profile := UiSizing.profile_for(self)
	var scale := profile.ui_scale if profile != null else 1.0
	toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var width := minf(minf(maximum_width, available), text_width + icon_width + toggle.get_theme_constant(&"h_separation") + margins)
	UiSizing.minimum_size(toggle, Vector2(width / scale, 0.0))


func bind_indoor_icon(index: int, media: ClassicMediaCatalog) -> void:
	var picker := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs/World View/WorldViewGroup/Content/IndoorPartyIcon") as IndoorPartyIconPicker
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
	_bind_option(root.get_node("MusicTransitionRow/MusicTransition") as OptionButton, [
		{"label": "Restart current song", "id": PresentationSettings.MUSIC_RESTART_SONG},
		{"label": "Restart playlist", "id": PresentationSettings.MUSIC_RESTART_PLAYLIST},
		{"label": "Resume where it stopped", "id": PresentationSettings.MUSIC_RESUME},
	], settings.music_transition, &"music_transition")
	_bind_action(root.get_node("OpenMusicPlaylist") as Button, func() -> void: action_requested.emit(&"music_playlist", null))


func bind_command_titles(settings: PresentationSettings) -> void:
	var world := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Commands")
	var titles := world.get_node("OverworldCommandTitles") as CheckButton
	var fit := world.get_node("FitHiddenCommandArt") as CheckButton
	SystemSignalBinding.clear_toggled(titles)
	titles.button_pressed = settings.show_overworld_command_titles
	titles.toggled.connect(func(value: bool) -> void:
		fit.disabled = value
		setting_changed.emit(&"show_overworld_command_titles", value)
	)
	_bind_toggle(fit, settings.integer_fit_hidden_commands, &"integer_fit_hidden_commands")
	fit.disabled = settings.show_overworld_command_titles


func bind_pacing(settings: PresentationSettings) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Pacing/PacingSettingsScroll/PacingSettingsPanel/Content")
	_bind_combat_text_speed(root, settings.combat_text_speed_percent)
	_bind_combat_text_background(root, settings.combat_text_background_opacity_percent)
	_bind_toggle(root.get_node("HurrySpellResolution") as CheckButton, settings.hurry_spell_resolution, &"hurry_spell_resolution")
	var combat := root.get_node("CombatSpeedRow/CombatPlaybackSpeedSlider") as HSlider
	var combat_caption := root.get_node("CombatSpeedRow/CombatPlaybackSpeedCaption") as Label
	bind_label(combat_caption, "Combat & animation speed  •  %d%%" % settings.combat_playback_speed_percent, Color("e0e2e5"), 15)
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
	bind_label(movement_caption, "Exploration travel speed  •  %d%%" % settings.exploration_speed_percent, Color("e0e2e5"), 15)
	_clear_value_changed_connections(movement)
	movement.value = settings.exploration_speed_percent
	movement.tooltip_text = "%d%%  •  %.3f seconds per held step" % [settings.exploration_speed_percent, HeldMovementController.BASE_INTERVAL_SECONDS * 100.0 / float(settings.exploration_speed_percent)]
	movement.value_changed.connect(func(value: float) -> void:
		var percent := int(value)
		movement_caption.text = "Exploration travel speed  •  %d%%" % percent
		movement.tooltip_text = "%d%%  •  %.3f seconds per held step" % [percent, HeldMovementController.BASE_INTERVAL_SECONDS * 100.0 / float(percent)]
		setting_changed.emit(&"exploration_speed_percent", percent)
	)


func _bind_combat_text_speed(root: Node, percent: int) -> void:
	var slider := root.get_node("CombatTextSpeedRow/CombatTextSpeedSlider") as HSlider
	var caption := root.get_node("CombatTextSpeedRow/CombatTextSpeedCaption") as Label
	bind_label(caption, "Scrolling combat text speed  •  %d%%" % percent, Color("e0e2e5"), 15)
	_clear_value_changed_connections(slider)
	slider.value = percent
	slider.tooltip_text = "Lower values slow damage and status text without slowing combat."
	slider.value_changed.connect(func(value: float) -> void:
		caption.text = "Scrolling combat text speed  •  %d%%" % int(value)
		setting_changed.emit(&"combat_text_speed_percent", int(value))
	)


func _bind_combat_text_background(root: Node, percent: int) -> void:
	var slider := root.get_node("CombatTextBackgroundRow/CombatTextBackgroundSlider") as HSlider
	var caption := root.get_node("CombatTextBackgroundRow/CombatTextBackgroundCaption") as Label
	bind_label(caption, "Combat text background opacity  •  %d%%" % percent, Color("e0e2e5"), 15)
	_clear_value_changed_connections(slider)
	slider.value = percent
	slider.tooltip_text = "Change only the backing behind combat text; letters keep their contrast."
	slider.value_changed.connect(func(value: float) -> void:
		caption.text = "Combat text background opacity  •  %d%%" % int(value)
		setting_changed.emit(&"combat_text_background_opacity_percent", int(value))
	)


func bind_accessibility(settings: PresentationSettings, _fonts: FontResolver) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Accessibility/AccessibilitySettingsScroll/AccessibilitySettingsPanel/Content")
	_bind_toggle(root.get_node("ReducedMotion") as CheckButton, settings.reduced_motion, &"reduced_motion")
	_bind_toggle(root.get_node("ReducedSound") as CheckButton, settings.reduced_sound, &"reduced_sound")


func bind_interface(settings: PresentationSettings, fonts: FontResolver) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/Text")
	_bind_font_choices(root, settings, fonts)
	bind_command_titles(settings)
	var preview := ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme, settings, 1.0, fonts)
	var sample := root.get_node("TextPreview/Content/Sample") as Label
	var narrative := root.get_node("TextPreview/Content/PreviewDetail") as Label
	sample.add_theme_font_override(&"font", preview.default_font)
	narrative.add_theme_font_override(&"font", preview.get_font(&"normal_font", &"ClassicNarrative"))
	var profile := UiSizing.profile_for(self)
	var ui_scale := profile.ui_scale if profile != null else 1.0
	sample.add_theme_font_size_override(&"font_size", roundi(18 * ui_scale * settings.interface_text_scale))
	narrative.add_theme_font_size_override(&"font_size", roundi(16 * ui_scale * settings.narrative_text_scale))
	for role: String in ["Interface", "Narrative"]:
		var slider := root.get_node("%sTextScaleRow/TextScaleSlider" % role) as HSlider
		var percentage := root.get_node("%sTextScaleRow/SizeValue" % role) as Label
		var scale := settings.interface_text_scale if role == "Interface" else settings.narrative_text_scale
		var update_caption := func(value: float) -> void:
			percentage.text = "%d%%" % roundi(value * 100.0)
			slider.tooltip_text = "%s text size: %d%%" % [role, roundi(value * 100.0)]
		_clear_value_changed_connections(slider)
		slider.value = scale
		update_caption.call(scale)
		slider.value_changed.connect(func(value: float) -> void:
			update_caption.call(value)
			setting_changed.emit(StringName(role.to_lower() + "_text_scale"), value)
		)


func _bind_font_choices(root: Node, settings: PresentationSettings, fonts: FontResolver) -> void:
	for role: String in ["interface", "narrative"]:
		var identity := settings.interface_font if role == "interface" else settings.narrative_font
		var button := root.get_node("%sFontRow/ChooseFont" % role.capitalize()) as Button
		button.text = fonts.label(identity)
		button.tooltip_text = "%s\nChoose from bundled, installed, or imported fonts." % fonts.label(identity)
		_bind_action(button, func() -> void: action_requested.emit(StringName("choose_%s_font" % role), null))
	(root.get_node("FontStatus") as Label).text = "\n".join(PackedStringArray([fonts.unavailable_message(settings.interface_font), fonts.unavailable_message(settings.narrative_font)])) .strip_edges()


func _bind_volume_row(row: BoxContainer, title: String, value: float, setting_id: StringName) -> void:
	bind_label(row.get_node("Caption") as Label, "%s  •  %d%%" % [title, int(round(value * 100.0))], Color("e0e2e5"), 15)
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


static func bind_label(label: Label, text: String, color: Color, size: int) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	UiSizing.font_size(label, &"font_size", size)


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


func bind_diagnostics(settings: PresentationSettings) -> void:
	var root := get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Diagnostics/DiagnosticsSettingsScroll/DiagnosticsSettingsPanel/Content")
	_bind_toggle(root.get_node("TopologyDebug") as CheckButton, settings.topology_debug, &"topology_debug")
