## Binds the scene-authored HUD layout controls to a detached Preferences draft.
class_name HudSettingsPanel
extends VBoxContainer

signal preferences_changed(value: HudPreferences)
signal arrange_requested

const PANEL_COUNT := 4

var _preferences: HudPreferences
var _active_adventure := false
var _selected_panel := 0
var _binding := false


func _ready() -> void:
	(get_node("SettingsScroll/SettingsPanel/Content/LayoutGroup/Content/LayoutRow/LayoutChoice") as OptionButton).item_selected.connect(_on_layout_selected)
	(get_node("SettingsScroll/SettingsPanel/Content/LayoutGroup/Content/CompactCommands") as CheckButton).toggled.connect(_on_compact_commands_toggled)
	(get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/PanelRow/PanelChoice") as OptionButton).item_selected.connect(_on_panel_selected)
	(get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/VisibilityRow/VisibilityChoice") as OptionButton).item_selected.connect(_on_visibility_selected)
	(get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/OpacityRow/OpacitySlider") as HSlider).value_changed.connect(_on_opacity_changed)
	(get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/HoverReveal") as CheckButton).toggled.connect(_on_hover_reveal_toggled)
	(get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/ChangeReveal") as CheckButton).toggled.connect(_on_change_reveal_toggled)
	(get_node("SettingsScroll/SettingsPanel/Content/ArrangeGroup/Content/ArrangeButton") as Button).pressed.connect(_on_arrange_pressed)

	%AllVisibility.item_selected.connect(_on_all_visibility_selected)
	%AllVisibility.get_popup().exclusive = false


func bind_preferences(value: HudPreferences, active_adventure: bool) -> void:
	_preferences = value.duplicate_value()
	_active_adventure = active_adventure
	_selected_panel = clampi(_selected_panel, 0, PANEL_COUNT - 1)
	_refresh_controls()


func _refresh_controls() -> void:
	if _preferences == null or _preferences.panels.size() != PANEL_COUNT:
		return
	_binding = true
	var layout := get_node("SettingsScroll/SettingsPanel/Content/LayoutGroup/Content/LayoutRow/LayoutChoice") as OptionButton
	var panel_choice := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/PanelRow/PanelChoice") as OptionButton
	var visibility := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/VisibilityRow/VisibilityChoice") as OptionButton
	var opacity := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/OpacityRow/OpacitySlider") as HSlider
	var opacity_value := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/OpacityRow/OpacityValue") as Label
	var hover := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/HoverReveal") as CheckButton
	var changes := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/ChangeReveal") as CheckButton
	var reveal_help := get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/RevealHelp") as Label
	var arrange := get_node("SettingsScroll/SettingsPanel/Content/ArrangeGroup/Content/ArrangeButton") as Button
	var unavailable := get_node("SettingsScroll/SettingsPanel/Content/ArrangeGroup/Content/ArrangeUnavailableReason") as Label
	var panel_preferences := _preferences.panels[_selected_panel]

	layout.select(1 if _preferences.modular else 0)
	var compact := get_node("SettingsScroll/SettingsPanel/Content/LayoutGroup/Content/CompactCommands") as CheckButton
	compact.set_pressed_no_signal(_preferences.compact_commands)
	compact.disabled = not _preferences.modular
	var hidden_count := _preferences.panels.filter(func(panel: HudPanelPreferences) -> bool: return panel.auto_hide).size()
	%AllVisibility.select(1 if hidden_count == 0 else 2 if hidden_count == PANEL_COUNT else 0)
	%AllVisibility.set_item_disabled(0, true)
	%AllVisibility.disabled = not _preferences.modular
	panel_choice.select(_selected_panel)
	visibility.select(1 if panel_preferences.auto_hide else 0)
	opacity.value = clampf(panel_preferences.background_opacity * 100.0, 40.0, 100.0)
	opacity_value.text = "%d%%" % roundi(opacity.value)
	hover.button_pressed = panel_preferences.reveal_on_hover
	changes.button_pressed = panel_preferences.reveal_on_changes
	var modular_controls_enabled := _preferences.modular
	panel_choice.disabled = not modular_controls_enabled
	visibility.disabled = not modular_controls_enabled
	opacity.editable = modular_controls_enabled
	hover.disabled = not modular_controls_enabled
	changes.disabled = not modular_controls_enabled or _selected_panel >= 2
	reveal_help.visible = _selected_panel >= 2
	arrange.disabled = not _active_adventure or not _preferences.modular
	unavailable.visible = not _active_adventure
	_binding = false


func _selected_panel_preferences() -> HudPanelPreferences:
	if _preferences == null or _preferences.panels.size() != PANEL_COUNT:
		return null
	return _preferences.panels[_selected_panel]


func _publish_preferences() -> void:
	preferences_changed.emit(_preferences.duplicate_value())


func _on_layout_selected(index: int) -> void:
	if _binding or _preferences == null:
		return
	_preferences.modular = index == 1
	_refresh_controls()
	_publish_preferences()


func _on_panel_selected(index: int) -> void:
	if _binding or index < 0 or index >= PANEL_COUNT:
		return
	_selected_panel = index
	_refresh_controls()


func _on_compact_commands_toggled(enabled: bool) -> void:
	if _binding or _preferences == null:
		return
	_preferences.compact_commands = enabled
	_publish_preferences()


func _on_all_visibility_selected(index: int) -> void:
	if _binding or _preferences == null or index == 0: return
	for panel: HudPanelPreferences in _preferences.panels: panel.auto_hide = index == 2
	_refresh_controls()
	_publish_preferences()


func _on_visibility_selected(index: int) -> void:
	if _binding:
		return
	var panel_preferences := _selected_panel_preferences()
	if panel_preferences == null:
		return
	panel_preferences.auto_hide = index == 1
	_refresh_controls()
	_publish_preferences()


func _on_opacity_changed(value: float) -> void:
	if _binding:
		return
	var panel_preferences := _selected_panel_preferences()
	if panel_preferences == null:
		return
	panel_preferences.background_opacity = clampf(value / 100.0, 0.4, 1.0)
	(get_node("SettingsScroll/SettingsPanel/Content/PanelGroup/Content/OpacityRow/OpacityValue") as Label).text = "%d%%" % roundi(value)
	_publish_preferences()


func _on_hover_reveal_toggled(enabled: bool) -> void:
	if _binding:
		return
	var panel_preferences := _selected_panel_preferences()
	if panel_preferences == null:
		return
	panel_preferences.reveal_on_hover = enabled
	_publish_preferences()


func _on_change_reveal_toggled(enabled: bool) -> void:
	if _binding or _selected_panel >= 2:
		return
	var panel_preferences := _selected_panel_preferences()
	if panel_preferences == null:
		return
	panel_preferences.reveal_on_changes = enabled
	_publish_preferences()


func _on_arrange_pressed() -> void:
	if _active_adventure and _preferences != null and _preferences.modular:
		arrange_requested.emit()
