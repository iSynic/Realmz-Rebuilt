## Keeps a font choice local until the parent Settings draft accepts it.
class_name FontPickerDialog
extends Control

signal opened
signal applied(role: StringName, identity: String)
signal import_requested(path: String)

const THEME_PATH := "res://src/ui/shared/style/classic_ui_theme.tres"
const ANDROID_PREVIEW_FONT_REASON := "Font file import is unavailable in the Android preview."

var resolver := FontResolver.new()
var _settings: PresentationSettings
var _role: StringName
var _selected: String
var _source: StringName = &"Bundled"
var _compact_preview := false
var _focus_before_open: WeakRef


func _ready() -> void:
	(%FontSearch as LineEdit).text_changed.connect(func(_value: String) -> void: _refresh_choices())
	(%FontChoices as ItemList).item_selected.connect(_choose)
	(%BundledTab as Button).pressed.connect(_set_source.bind(&"Bundled"))
	(%SystemTab as Button).pressed.connect(_set_source.bind(&"System"))
	(%ImportedTab as Button).pressed.connect(_set_source.bind(&"Imported"))
	(%PreviewSelected as Button).pressed.connect(_show_compact_preview)
	(%BackToFonts as Button).pressed.connect(_show_font_list)
	(%FontUse as Button).pressed.connect(_stage_selection)
	(%FontCancel as Button).pressed.connect(dismiss)
	(%ImportFont as Button).pressed.connect(func() -> void:
		if OS.has_feature("android"):
			return
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
	if OS.has_feature("android"):
		(%ImportFont as Button).disabled = true
		(%ImportFont as Button).text = "Font import unavailable (Android preview)"
		(%ImportFont as Button).tooltip_text = ANDROID_PREVIEW_FONT_REASON
		(%FontImportStatus as Label).text = ANDROID_PREVIEW_FONT_REASON
	_compact_preview = false
	(%ListPage as Control).visible = true
	(%PreviewPage as Control).visible = true
	visible = true
	opened.emit()
	_source = _source_for_identity(_selected)
	_sync_source_tabs()
	_refresh_choices()
	_fit()
	(%FontSearch as LineEdit).grab_focus()


func refresh_library(message: String = "") -> void:
	(%FontImportStatus as Label).text = message
	if visible:
		_refresh_choices()


func controller_focus_root() -> Node:
	if (%FontFiles as FileDialog).visible:
		return %FontFiles
	return self


func close() -> void:
	if (%FontFiles as FileDialog).visible:
		(%FontFiles as FileDialog).hide()
		(%ImportFont as Button).grab_focus()
		return
	if _compact_preview:
		_show_font_list()
		return
	dismiss()


func dismiss() -> void:
	_compact_preview = false
	hide()
	var previous := _focus_before_open.get_ref() as Control if _focus_before_open != null else null
	_focus_before_open = null
	if previous != null and previous.is_visible_in_tree():
		previous.grab_focus()


func _stage_selection() -> void:
	if not _selection_is_available():
		return
	applied.emit(_role, _selected)
	dismiss()


func _set_source(source: StringName) -> void:
	_source = source
	_sync_source_tabs()
	_refresh_choices()


func _sync_source_tabs() -> void:
	for pair: Array in [[&"Bundled", %BundledTab], [&"System", %SystemTab], [&"Imported", %ImportedTab]]:
		var button := pair[1] as Button
		button.button_pressed = _source == pair[0]


func _refresh_choices() -> void:
	var list := %FontChoices as ItemList
	var query := (%FontSearch as LineEdit).text.strip_edges().to_lower()
	var retained_index := -1
	list.clear()
	var matches := 0
	for choice: FontResolver.Choice in resolver.choices():
		var group := &"Bundled" if choice.group.is_empty() else StringName(choice.group)
		if group != _source or (not query.is_empty() and not choice.name.to_lower().contains(query)):
			continue
		matches += 1
		list.add_item(choice.name)
		var index := list.item_count - 1
		list.set_item_metadata(index, choice.id)
		if choice.id == _selected:
			retained_index = index
	if not _selected.is_empty() and _source_for_identity(_selected) == _source and not _identity_exists(_selected):
		var missing_label := "%s · unavailable" % resolver.label(_selected)
		if not query.is_empty() and not missing_label.to_lower().contains(query):
			missing_label = ""
		if not missing_label.is_empty():
			list.add_item(missing_label)
			retained_index = list.item_count - 1
			list.set_item_metadata(retained_index, _selected)
	if list.item_count == 0:
		list.add_item("No matching fonts" if matches == 0 else "No fonts available")
		list.set_item_selectable(0, false)
	if retained_index >= 0:
		list.select(retained_index)
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
	var preview := ClassicTypography.themed_copy(load(THEME_PATH) as Theme, draft, 1.0, resolver)
	var selected_font := preview.get_font(&"normal_font", &"ClassicNarrative") if _role == &"narrative" else preview.default_font
	(%FontFamily as Label).text = resolver.label(_selected)
	var text_scale := _settings.narrative_text_scale if _role == &"narrative" else _settings.interface_text_scale
	(%PreviewScale as Label).text = "%s preview · %d%%" % [String(_role).capitalize(), roundi(text_scale * 100.0)]
	for node: Label in [%FontIdentitySample, %FontNumberSample, %FontNarrativeSample]:
		node.add_theme_font_override(&"font", selected_font)
		node.theme_type_variation = &"ClassicNarrativeText" if _role == &"narrative" else &""
	_apply_preview_font_sizes()
	var unavailable := not _selected.is_empty() and not _identity_exists(_selected)
	(%FontUnavailable as Label).visible = unavailable
	(%FontUnavailable as Label).text = "%s\nChoose an available font or cancel to keep its saved identity." % resolver.unavailable_message(_selected) if unavailable else ""
	(%FontUse as Button).disabled = not _selection_is_available()


func _selection_is_available() -> bool:
	return _identity_exists(_selected)


func _identity_exists(identity: String) -> bool:
	if identity.is_empty():
		return true
	for choice: FontResolver.Choice in resolver.choices():
		if choice.id == identity:
			return resolver.unavailable_message(identity).is_empty()
	return false


func _source_for_identity(identity: String) -> StringName:
	if identity.begins_with("system:"):
		return &"System"
	if identity.begins_with("imported:"):
		return &"Imported"
	return &"Bundled"


func _show_compact_preview() -> void:
	_compact_preview = true
	_fit()
	(%BackToFonts as Button).grab_focus()


func _show_font_list() -> void:
	_compact_preview = false
	_fit()
	(%FontChoices as ItemList).grab_focus()


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_fit.call_deferred()
	_apply_preview_font_sizes.call_deferred()


func _apply_preview_font_sizes() -> void:
	if not is_node_ready() or _settings == null:
		return
	var profile := UiSizing.profile_for(self)
	var interface_size := profile.ui_scale if profile != null else 1.0
	var role_scale := _settings.narrative_text_scale if _role == &"narrative" else _settings.interface_text_scale
	var preview_size := maxi(1, roundi(20.0 * interface_size * role_scale))
	for node: Label in [%FontIdentitySample, %FontNumberSample, %FontNarrativeSample]:
		node.add_theme_font_size_override(&"font_size", preview_size)


func _fit() -> void:
	if not is_node_ready():
		return
	var profile := UiSizing.profile_for(self)
	var area := profile.application_rect if profile != null else Rect2(Vector2.ZERO, size)
	var scale := profile.ui_scale if profile != null else 1.0
	var window := %FontPickerWindow as PanelContainer
	window.size = Vector2(minf(1100.0 * scale, area.size.x * 0.94), minf(620.0 * scale, area.size.y * 0.92))
	window.position = area.position + (area.size - window.size) * 0.5
	var compact := profile != null and profile.id == UiLayoutProfile.COMPACT and maxf(profile.font_scale, profile.narrative_font_scale) >= 1.45
	if not compact:
		_compact_preview = false
	(%PreviewSelected as Button).visible = compact
	(%BackToFonts as Button).visible = compact and _compact_preview
	var list_page := %ListPage as Control
	var preview_page := %PreviewPage as Control
	list_page.visible = not compact or not _compact_preview
	preview_page.visible = not compact or _compact_preview
	list_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact else Control.SIZE_FILL
	if not compact:
		(%FontChoices as ItemList).custom_minimum_size.x = minf(270.0 * scale, window.size.x * 0.36)
