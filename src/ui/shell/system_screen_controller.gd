## Binds save operations and host preferences to the authored System workspace.
class_name SystemScreenController
extends RefCounted


const WORKSPACE_SCENE_PATH := "res://src/ui/shell/system_workspace.tscn"

signal action_requested(action_id: StringName, value: Variant)
signal controller_binding_capture_requested(action_id: StringName)

const GOLD := Color("d5b45d")
const CYAN := Color("8fcfd1")
const MUTED := Color("9aa0a8")

var saves := SaveWorkspaceController.new()
var _layout_profile: StringName = UiLayoutProfile.WIDE
var _selected_workspace_mode: StringName = &"Display"
var _workspace: SystemWorkspace
var _has_active_session: bool = false
var _draft := PreferencesDraft.new()
var _live_settings: PresentationSettings
var _settings_media: ClassicMediaCatalog
var cancel_binding_capture: Callable
var commit_preferences: Callable
var _draft_error := ""
var _display_settings: PresentationSettings
var font_resolver := FontResolver.new()
var _controller_draft: ControllerPreferences
var controller := SystemControllerBindings.new(self)
var controller_draft: ControllerPreferences:
	get: return _controller_draft
var workspace: SystemWorkspace:
	get: return _workspace


func _init() -> void:
	var controller_ref: WeakRef = weakref(self)
	saves.action_requested.connect(func(action_id: StringName, value: Variant) -> void:
		var controller := controller_ref.get_ref() as SystemScreenController
		if controller != null:
			controller.action_requested.emit(action_id, value))


func navigate_section(section_name: StringName = &"", delta: int = 0) -> bool:
	if _workspace == null:
		return false
	if section_name == &"Save & Load" or section_name == &"SaveAndLoad":
		if not _has_active_session:
			return false
		show_saves()
		return true
	var categories: Array[StringName] = SystemPreferencesLayout.PREFERENCE_SECTIONS
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
	if _workspace == null or not _has_active_session:
		return
	_workspace.call("show_saves")
	_selected_workspace_mode = &"Save & Load"


func indoor_icon_picker() -> IndoorPartyIconPicker:
	return _workspace.find_child("IndoorPartyIcon", true, false) as IndoorPartyIconPicker if _workspace != null else null


func close_local_picker() -> bool:
	if not controller.capture_action.is_empty():
		_cancel_capture()
		return true
	var picker := indoor_icon_picker()
	return picker != null and picker.close_picker()


func has_dirty_draft() -> bool:
	return _draft.is_dirty() or not controller.capture_action.is_empty()


func draft_settings() -> PresentationSettings:
	return _draft.values if _draft.values != null else _live_settings


func discard_draft() -> void:
	_cancel_capture()
	if _live_settings == null:
		return
	_draft.reset(_live_settings)
	_controller_draft = _draft.values.controller
	controller.capture_action = &""
	_draft_error = ""
	refresh_preferences()


func apply_draft() -> bool:
	_draft_error = _draft.validation_error()
	if not controller.capture_action.is_empty():
		_draft_error = "Finish or cancel controller capture before applying."
	if _draft_error.is_empty() and not commit_preferences.is_valid():
		_draft_error = "Settings storage is unavailable. Your changes are still here."
	if _draft_error.is_empty():
		_draft_error = String(commit_preferences.call(_draft.baseline, _draft.values))
	if not _draft_error.is_empty():
		refresh_draft_footer()
		return false
	_draft.reset(_live_settings)
	_controller_draft = _draft.values.controller
	refresh_preferences()
	return true


func stage_setting(setting_id: StringName, value: Variant) -> void:
	if _draft.values == null:
		return
	_draft.set_value(setting_id, value)
	_draft_error = ""
	refresh_draft_footer()
	if setting_id in [&"display_scaling_mode", &"interface_font", &"narrative_font", &"interface_text_scale", &"narrative_text_scale"]:
		refresh_preferences()


func refresh_preferences() -> void:
	if _workspace == null or _draft.values == null:
		return
	var settings := _draft.values
	_bind_display(settings)
	_workspace.call("bind_indoor_icon", settings.indoor_party_icon, _settings_media)
	_workspace.call("bind_audio", settings)
	_workspace.call("bind_pacing", settings)
	_workspace.call("bind_accessibility", settings, font_resolver)
	_workspace.call("bind_interface", settings, font_resolver)
	_bind_hud_settings(settings)
	_bind_controls(settings)
	_workspace.call("bind_diagnostics", settings)
	refresh_draft_footer()


func refresh_draft_footer() -> void:
	if _workspace == null:
		return
	var footer := _workspace.get_node("PreferencesFooter")
	var error := _draft_error if not _draft_error.is_empty() else _draft.validation_error()
	(footer.get_node("DraftStatus") as Label).text = error if not error.is_empty() else "Unsaved changes" if has_dirty_draft() else "No unsaved changes"
	(footer.get_node("Apply") as Button).disabled = not has_dirty_draft() or not _draft.validation_error().is_empty() or not controller.capture_action.is_empty()


func set_layout_profile(profile_id: StringName) -> void:
	_layout_profile = profile_id
	saves.set_layout_profile(profile_id)
	_refresh_interface_size_feedback()


func present(target: Control, view: GameView, settings: PresentationSettings, media: ClassicMediaCatalog = null) -> void:
	if target == null or settings == null:
		return
	_has_active_session = view != null and view.session_started
	var screen := target as SystemScreen
	if screen != null:
		screen.prepare_for_render(_layout_profile == UiLayoutProfile.COMPACT)
		var next_workspace := screen.workspace()
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
		_workspace.connect("setting_changed", stage_setting)
		_workspace.set_meta("system_setting_observer", true)
	if _workspace.has_signal("action_requested") and not _workspace.has_meta("system_action_observer"):
		_workspace.connect("action_requested", func(action_id: StringName, value: Variant) -> void: action_requested.emit(action_id, value))
		_workspace.set_meta("system_action_observer", true)
	if not _workspace.has_meta("interface_size_feedback_observer"):
		_workspace.resized.connect(_refresh_interface_size_feedback)
		_workspace.set_meta("interface_size_feedback_observer", true)
	if _workspace.has_method("tabs"):
		(_workspace.call("tabs") as TabContainer).set_tab_disabled(0, not _has_active_session)
	if not _has_active_session and _selected_workspace_mode == &"Save & Load":
		_selected_workspace_mode = &"Display"
	if _has_active_session:
		_bind_header(view)
	else:
		_workspace.campaign_context().text = ""
	saves.present(_workspace, view, screen != null)
	_live_settings = settings
	_settings_media = media if _has_active_session else null
	if _draft.values == null or not _draft.is_dirty():
		_draft.reset(settings)
	_controller_draft = _draft.values.controller
	_workspace.call("bind_indoor_icon", _draft.values.indoor_party_icon, media if _has_active_session else null)
	var footer := _workspace.get_node("PreferencesFooter")
	var apply := footer.get_node("Apply") as Button
	var cancel := footer.get_node("Cancel") as Button
	SystemSignalBinding.clear_pressed(apply)
	SystemSignalBinding.clear_pressed(cancel)
	apply.pressed.connect(apply_draft)
	cancel.pressed.connect(func() -> void:
		discard_draft()
		action_requested.emit(&"cancel_preferences", null)
	)
	refresh_preferences()
	if _selected_workspace_mode == &"Save & Load" and _has_active_session:
		_workspace.call("show_saves")
	else:
		_workspace.call("show_category", _selected_workspace_mode)


func _bind_header(view: GameView) -> void:
	var campaign := view.campaign_summary.title if view.campaign_summary != null else view.campaign_id
	_bind_label(_workspace.campaign_context(), "%s  •  %s" % [campaign, view.rules_version], CYAN, 13)


func _bind_hud_settings(settings: PresentationSettings) -> void:
	var panel := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Interface/InterfaceSettingsScroll/InterfaceSettingsPanel/Content/InterfaceTabs/HUD panels") as HudSettingsPanel
	if not panel.preferences_changed.is_connected(_on_hud_preferences_changed):
		panel.preferences_changed.connect(_on_hud_preferences_changed)
	if not panel.arrange_requested.is_connected(_on_hud_arrange_requested):
		panel.arrange_requested.connect(_on_hud_arrange_requested)
	panel.bind_preferences(settings.hud, _has_active_session)


func _on_hud_preferences_changed(value: HudPreferences) -> void:
	stage_setting(&"hud", value)


func _on_hud_arrange_requested() -> void:
	if _has_active_session and _draft.values != null and _draft.values.hud.modular:
		action_requested.emit(&"arrange_hud", null)


func _bind_display(settings: PresentationSettings) -> void:
	_display_settings = settings
	var root := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Display/DisplaySettingsScroll/DisplaySettingsPanel/Content/DisplayPreferenceTabs")
	var scale_root := root.get_node("Window & Scale/DisplayTopRow/DisplaySettingsColumn/ScaleGroup/Content")
	var effects_root := root.get_node("Image Effects/VisualEffectsGroup/Content")
	var world_root := root.get_node("World View/WorldViewGroup/Content")
	_bind_option(scale_root.get_node("DisplayScalingRow/DisplayScalingPicker") as OptionButton, SystemPreferencesLayout.display_mode_options(), settings.display_scaling_mode, &"display_scaling_mode")
	var zoom_picker := scale_root.get_node("WorldZoomRow/WorldZoomPicker") as OptionButton
	_bind_option(zoom_picker, [
		{"label": "Auto · fits the world stage", "id": "0"},
		{"label": "1× · 32-pixel tiles", "id": "1"},
		{"label": "2× · 64-pixel tiles", "id": "2"},
		{"label": "3× · 96-pixel tiles", "id": "3"},
		{"label": "4× · 128-pixel tiles", "id": "4"},
	], str(settings.world_zoom), &"world_zoom")
	zoom_picker.disabled = settings.display_scaling_mode != PresentationSettings.DISPLAY_INTEGER_CANVAS
	zoom_picker.tooltip_text = "Auto chooses the largest 1×–4× scale that fits the Classic world view. Available only with Integer: world canvas."
	_bind_option(effects_root.get_node("PixelSmoothingRow/PixelSmoothingPicker") as OptionButton, [
		{"label": "Off · crisp pixels", "id": PresentationSettings.SMOOTHING_OFF},
		{"label": "World canvas only", "id": PresentationSettings.SMOOTHING_WORLD},
		{"label": "Whole window", "id": PresentationSettings.SMOOTHING_WINDOW},
	], settings.pixel_art_smoothing, &"pixel_art_smoothing")
	_bind_toggle(effects_root.get_node("CrtEnabled") as CheckButton, settings.crt_enabled, &"crt_enabled")
	_bind_option(effects_root.get_node("CrtShaderRow/CrtShaderPicker") as OptionButton, [
		{"label": "CRT-Pi", "id": PresentationSettings.CRT_PI},
		{"label": "CRT-Lottes", "id": PresentationSettings.CRT_LOTTES},
	], settings.crt_shader, &"crt_shader")
	_bind_option(effects_root.get_node("CrtAreaRow/CrtAreaPicker") as OptionButton, [
		{"label": "World canvas", "id": PresentationSettings.CRT_WORLD},
		{"label": "Whole window", "id": PresentationSettings.CRT_WINDOW},
	], settings.crt_area, &"crt_area")
	var interface_size_picker := scale_root.get_node("InterfaceScaleRow/InterfaceScalePicker") as OptionButton
	_bind_option(interface_size_picker, SystemPreferencesLayout.interface_size_options(), settings.ui_scale_mode, &"ui_scale_mode")
	interface_size_picker.tooltip_text = "Auto fits the available window. Manual sizes may be limited by the current window."
	_bind_option(scale_root.get_node("WindowModeRow/WindowModePicker") as OptionButton, [
		{"label": "Windowed", "id": PresentationSettings.WINDOWED},
		{"label": "Borderless fullscreen", "id": PresentationSettings.BORDERLESS_FULLSCREEN},
	], settings.window_mode, &"window_mode")
	_bind_toggle(world_root.get_node("WorldOptions/Dungeon3d") as CheckButton, settings.dungeon_3d, &"dungeon_3d")
	_bind_toggle(world_root.get_node("WorldOptions/ClassicExplorationVisibility") as CheckButton, settings.classic_exploration_visibility, &"classic_exploration_visibility")
	_bind_toggle(world_root.get_node("WorldOptions/CustomFogTile") as CheckButton, settings.custom_fog_tile_enabled, &"custom_fog_tile_enabled")
	_refresh_interface_size_feedback()


func _refresh_interface_size_feedback() -> void:
	if _workspace == null or _display_settings == null:
		return
	SystemPreferencesLayout.refresh_interface_size_feedback(_workspace, _display_settings)


func _bind_controls(settings: PresentationSettings) -> void:
	var root := _workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content")
	_controller_draft = settings.controller
	_bind_controller_editor(root.get_node("ControlsTabs/Controller/ControllerSettings/Content") as TabContainer)
	_bind_toggle(root.get_node("ControlsTabs/Gameplay/AutoSwitchToMelee") as CheckButton, settings.auto_switch_to_melee, &"auto_switch_to_melee")
	_bind_toggle(root.get_node("ControlsTabs/Gameplay/ImmediateSingleTargetActions") as CheckButton, settings.immediate_single_target_actions, &"immediate_single_target_actions")
	_bind_toggle(root.get_node("ControlsTabs/Keyboard & Mouse/ClickToMove") as CheckButton, settings.click_to_move_enabled, &"click_to_move_enabled")
	_bind_toggle(root.get_node("ControlsTabs/Keyboard & Mouse/ClassicKeyboardShortcuts") as CheckButton, settings.classic_keyboard_shortcuts, &"classic_keyboard_shortcuts")
	_bind_toggle(root.get_node("ControlsTabs/Gameplay/ShowExplorationMinimap") as CheckButton, settings.show_exploration_minimap, &"show_exploration_minimap")
	_bind_toggle(root.get_node("ControlsTabs/Gameplay/AutojournalEnabled") as CheckButton, settings.autojournal_enabled, &"autojournal_enabled")


func _bind_controller_editor(root: TabContainer) -> void:
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
		refresh_draft_footer()
	)
	_bind_controller_slider(tuning.get_node("LeftDeadZone") as HSlider, tuning.get_node("LeftDeadZoneLabelRow/Value") as Label, _controller_draft.left_stick_dead_zone, "Left stick dead zone", func(value: float) -> void: _controller_draft.left_stick_dead_zone = value)
	_bind_controller_slider(tuning.get_node("RightDeadZone") as HSlider, tuning.get_node("RightDeadZoneLabelRow/Value") as Label, _controller_draft.right_stick_dead_zone, "Right stick dead zone", func(value: float) -> void: _controller_draft.right_stick_dead_zone = value)
	_bind_controller_slider(tuning.get_node("RepeatInitial") as HSlider, tuning.get_node("RepeatInitialLabelRow/Value") as Label, _controller_draft.repeat_initial_ms, "UI repeat start delay", func(value: float) -> void: _controller_draft.repeat_initial_ms = int(value))
	_bind_controller_slider(tuning.get_node("RepeatInterval") as HSlider, tuning.get_node("RepeatIntervalLabelRow/Value") as Label, _controller_draft.repeat_interval_ms, "UI repeat interval", func(value: float) -> void: _controller_draft.repeat_interval_ms = int(value))
	(tuning.get_node("LiveInput") as Label).text = "Live input • %s" % (controller.live_text if not controller.live_text.is_empty() else "move or press a controller control")
	var conflicts := _controller_draft.conflicts()
	var reachable := _controller_draft.required_navigation_is_reachable()
	var status := bindings.get_node("BindingStatus") as Label
	controller.bind_binding_list(bindings, conflicts, reachable, status)
	var restore := bindings.get_node("Actions/RestoreControllerDefaults") as Button
	SystemSignalBinding.clear_pressed(restore)
	restore.pressed.connect(func() -> void:
		_cancel_capture()
		_draft.values.controller = ControllerPreferences.new()
		_controller_draft = _draft.values.controller
		refresh_controller_editor()
	)
	refresh_draft_footer()


func _bind_controller_slider(slider: HSlider, value_label: Label, value: float, caption: String, assign: Callable) -> void:
	SystemSignalBinding.clear_value_changed(slider)
	slider.value = value
	var format_value := func(next: float) -> String:
		return "%d%%" % int(round(next * 100.0)) if slider.name.ends_with("DeadZone") else "%d ms" % int(round(next))
	value_label.text = format_value.call(value)
	slider.tooltip_text = "%s • %s" % [caption, value_label.text]
	slider.value_changed.connect(func(next: float) -> void:
		assign.call(next)
		refresh_draft_footer()
		value_label.text = format_value.call(next)
		slider.tooltip_text = "%s • %s" % [caption, value_label.text]
	)


func refresh_controller_editor() -> void:
	if _workspace != null:
		_bind_controller_editor(_workspace.get_node("SystemWorkspaceBody/SystemWorkspaceTabs/Controls/ControlsSettingsScroll/ControlsSettingsPanel/Content/ControlsTabs/Controller/ControllerSettings/Content") as TabContainer)


func _bind_option(picker: OptionButton, entries: Array[Dictionary], selected_id: String, setting_id: StringName) -> void:
	SystemSignalBinding.clear_item_selected(picker)
	picker.clear()
	for entry: Dictionary in entries:
		picker.add_item(entry["label"])
		picker.set_item_metadata(picker.item_count - 1, entry["id"])
		if entry["id"] == selected_id:
			picker.select(picker.item_count - 1)
	picker.item_selected.connect(func(index: int) -> void: stage_setting(setting_id, String(picker.get_item_metadata(index))))


func _bind_slider(slider: Range, value: float, setting_id: StringName) -> void:
	SystemSignalBinding.clear_value_changed(slider)
	slider.value = value
	slider.value_changed.connect(func(changed_value: float) -> void: stage_setting(setting_id, changed_value))


func _bind_toggle(toggle: CheckButton, enabled: bool, setting_id: StringName) -> void:
	SystemSignalBinding.clear_toggled(toggle)
	toggle.button_pressed = enabled
	toggle.toggled.connect(func(value: bool) -> void: stage_setting(setting_id, value))


func _bind_action(button: Button, action: Callable) -> void:
	SystemSignalBinding.clear_pressed(button)
	button.custom_minimum_size.y = 38.0
	button.pressed.connect(action)


static func _bind_label(label: Label, text: String, color: Color, size: int) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	UiSizing.font_size(label, &"font_size", size)


static func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()


func _cancel_capture() -> void:
	if controller.capture_action.is_empty():
		return
	if cancel_binding_capture.is_valid():
		cancel_binding_capture.call()
	controller.capture_action = &""
	refresh_controller_editor()
