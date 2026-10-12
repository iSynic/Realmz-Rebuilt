## Keeps font browsing and preview local until the player applies a choice.
class_name FontPickerDialog
extends Control

signal opened
signal applied(role: StringName, identity: String)
signal import_requested(path: String)

var resolver := FontResolver.new()
var _settings: PresentationSettings
var _role: StringName
var _selected: String
var _focus_before_open: WeakRef


func _ready() -> void:
	(%FontSearch as LineEdit).text_changed.connect(func(_value: String) -> void: _refresh_choices())
	(%FontChoices as ItemList).item_selected.connect(_choose)
	(%FontApply as Button).pressed.connect(_apply)
	(%FontCancel as Button).pressed.connect(close)
	(%ImportFont as Button).pressed.connect(func() -> void:
		(%FontFiles as FileDialog).popup_centered_ratio(0.88)
		(%FontFiles as FileDialog).get_line_edit().grab_focus()
	)
	(%FontFiles as FileDialog).file_selected.connect(func(path: String) -> void: import_requested.emit(path))
	(%FontFiles as FileDialog).canceled.connect(func() -> void: (%ImportFont as Button).grab_focus())
	resized.connect(_fit)
	(%FontPickerWindow as PanelContainer).minimum_size_changed.connect(_fit, CONNECT_DEFERRED)


func open(role: StringName, settings: PresentationSettings) -> void:
	_role = role
	_settings = PresentationSettings.from_data(settings.to_data())
	_selected = settings.narrative_font if role == &"narrative" else settings.interface_font
	var focused := get_viewport().gui_get_focus_owner()
	_focus_before_open = weakref(focused) if focused != null else null
	(%FontPickerTitle as Label).text = "Choose %s font" % String(role).capitalize()
	(%FontSearch as LineEdit).text = ""
	(%FontImportStatus as Label).text = ""
	visible = true
	opened.emit()
	_refresh_choices()
	_fit()
	(%FontSearch as LineEdit).grab_focus()


func refresh_library(message: String = "") -> void:
	(%FontImportStatus as Label).text = message
	if visible:
		_refresh_choices()


func controller_focus_root() -> Node:
	return %FontFiles if (%FontFiles as FileDialog).visible else self


func close() -> void:
	if (%FontFiles as FileDialog).visible:
		(%FontFiles as FileDialog).hide()
		(%ImportFont as Button).grab_focus()
		return
	hide()
	var previous := _focus_before_open.get_ref() as Control if _focus_before_open != null else null
	_focus_before_open = null
	if previous != null and previous.is_visible_in_tree():
		previous.grab_focus()


func _apply() -> void:
	applied.emit(_role, _selected)
	close()


func _refresh_choices() -> void:
	var list := %FontChoices as ItemList
	var query := (%FontSearch as LineEdit).text.strip_edges().to_lower()
	list.clear()
	var group := ""
	for choice: FontResolver.Choice in resolver.choices():
		if not query.is_empty() and not choice.name.to_lower().contains(query):
			continue
		if choice.group != group:
			group = choice.group
			list.add_item(group)
			list.set_item_selectable(list.item_count - 1, false)
			list.set_item_custom_fg_color(list.item_count - 1, Color("8fcfd1"))
		list.add_item(choice.name)
		list.set_item_metadata(list.item_count - 1, choice.id)
		if choice.id == _selected:
			list.select(list.item_count - 1)
	_update_preview()


func _choose(index: int) -> void:
	var value: Variant = (%FontChoices as ItemList).get_item_metadata(index)
	if value is String:
		_selected = value
		_update_preview()


func _update_preview() -> void:
	if _settings == null:
		return
	var draft := PresentationSettings.from_data(_settings.to_data())
	if _role == &"narrative":
		draft.narrative_font = _selected
	else:
		draft.interface_font = _selected
	var preview := ClassicTypography.themed_copy(load("res://src/ui/shared/style/classic_ui_theme.tres") as Theme, draft, 1.0, resolver)
	var selected_font := preview.get_font(&"normal_font", &"ClassicNarrative") if _role == &"narrative" else preview.default_font
	(%FontFamily as Label).text = resolver.label(_selected)
	for node: Label in [%FontIdentitySample, %FontNumberSample, %FontNarrativeSample]:
		node.add_theme_font_override(&"font", selected_font)
		node.theme_type_variation = &"ClassicNarrativeText" if _role == &"narrative" else &""
		UiSizing.font_size(node, &"font_size", 20)
	(%FontUnavailable as Label).text = resolver.unavailable_message(_selected)
	(%FontApply as Button).disabled = not PresentationSettings.font_choice_is_valid(_selected)


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_fit.call_deferred()


func _fit() -> void:
	if not is_node_ready():
		return
	var profile := UiSizing.profile_for(self)
	var area := profile.application_rect if profile != null else Rect2(Vector2.ZERO, size)
	var scale := profile.ui_scale if profile != null else 1.0
	var window := %FontPickerWindow as PanelContainer
	window.size = Vector2(minf(1100.0 * scale, area.size.x * 0.94), minf(620.0 * scale, area.size.y * 0.92))
	window.position = area.position + (area.size - window.size) * 0.5
	(%FontChoices as ItemList).custom_minimum_size.x = minf(270.0 * scale, window.size.x * 0.36)
