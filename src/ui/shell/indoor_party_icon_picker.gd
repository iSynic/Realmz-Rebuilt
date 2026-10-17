## Stages an indoor party marker locally until Use icon is pressed.
class_name IndoorPartyIconPicker
extends VBoxContainer

signal icon_selected(index: int)

const PAGE_SIZE := 24
const PAGE_COUNT := 5

var _media: ClassicMediaCatalog
var _current_index := PresentationSettings.DEFAULT_INDOOR_PARTY_ICON
var _selected_index := PresentationSettings.DEFAULT_INDOOR_PARTY_ICON
var _page: int = floori(float(PresentationSettings.DEFAULT_INDOOR_PARTY_ICON) / PAGE_SIZE)
var _icon_buttons: Array[Button] = []
var _picker_open := false


func _ready() -> void:
	var template := %IconTemplate as Button
	template.hide()
	for slot: int in PAGE_SIZE:
		var button := template.duplicate() as Button
		button.name = "Icon%d" % slot
		button.visible = true
		button.pressed.connect(_select_slot.bind(slot))
		%IconGrid.add_child(button)
		_icon_buttons.append(button)
	(%Change as Button).pressed.connect(_open_picker)
	(%PreviousPage as Button).pressed.connect(_change_page.bind(-1))
	(%NextPage as Button).pressed.connect(_change_page.bind(1))
	(%DefaultIcon as Button).pressed.connect(_select_default)
	(%CancelIcon as Button).pressed.connect(_cancel_picker)
	(%UseIcon as Button).pressed.connect(_use_icon)
	get_viewport().size_changed.connect(_fit_picker)
	(%PickerPanel as PanelContainer).minimum_size_changed.connect(_fit_picker, CONNECT_DEFERRED)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree(): close_picker()
	)
	_update_summary()
	_update_page()
	_fit_picker()


func bind_selection(index: int, media: ClassicMediaCatalog) -> void:
	_current_index = clampi(index, 0, PresentationSettings.INDOOR_PARTY_ICON_COUNT - 1)
	if not _picker_open:
		_selected_index = _current_index
	_media = media
	if is_node_ready():
		_update_summary()
		_update_page()
		_set_media_availability()


func picker_is_open() -> bool:
	return _picker_open


func controller_focus_root() -> Node:
	return %PickerPanel if _picker_open else self


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_apply_picker_theme()
	_fit_picker.call_deferred()


func close_picker() -> bool:
	if not _picker_open:
		return false
	_cancel_picker()
	return true


func _input(event: InputEvent) -> void:
	if _picker_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_picker()
		get_viewport().set_input_as_handled()


func _open_picker() -> void:
	if _media == null or not is_visible_in_tree():
		return
	_apply_picker_theme()
	_selected_index = _current_index
	_page = floori(float(_selected_index) / PAGE_SIZE)
	_picker_open = true
	%PickerOverlay.show()
	_update_summary()
	_update_page()
	_update_compact_layout()
	_fit_picker()
	_focus_selection.call_deferred()


func _cancel_picker() -> void:
	if not _picker_open:
		return
	_picker_open = false
	_selected_index = _current_index
	%PickerOverlay.hide()
	_update_summary()
	if is_visible_in_tree(): (%Change as Button).grab_focus()


func _use_icon() -> void:
	if _media == null or _texture(_selected_index) == null:
		return
	_current_index = _selected_index
	_update_summary()
	_picker_open = false
	%PickerOverlay.hide()
	if is_visible_in_tree(): (%Change as Button).grab_focus()
	icon_selected.emit(_current_index)


func _texture(index: int) -> Texture2D:
	if _media == null:
		return null
	var asset := _media.asset_by_resource("cicn", 9000 + index)
	return _media.image_texture(asset) if asset != null else null


func _update_summary() -> void:
	var current_number := _current_index + 1
	var selected_number := _selected_index + 1
	(%CurrentIcon as TextureRect).texture = _texture(_current_index)
	(%CurrentText as Label).text = "Icon %d%s" % [current_number, " · Classic default" if _current_index == PresentationSettings.DEFAULT_INDOOR_PARTY_ICON else ""]
	(%WideCurrentText as Label).text = "Current setting: Icon %d" % current_number
	(%WideSelectedText as Label).text = "Selected: Icon %d" % selected_number
	(%SelectedIcon as TextureRect).texture = _texture(_selected_index)
	(%CompactSummary as Label).text = "Current: %d   →   Selected: %d" % [current_number, selected_number]
	(%UseIcon as Button).disabled = _media == null or _texture(_selected_index) == null
	_set_media_availability()


func _set_media_availability() -> void:
	var unavailable := _media == null
	(%Change as Button).disabled = unavailable
	(%Change as Button).tooltip_text = "Party icons are available after opening an adventure." if unavailable else "Choose the indoor party icon."
	(%MediaUnavailable as Label).visible = unavailable
	(%MediaUnavailable as Label).text = "Icon previews are available after opening an adventure." if unavailable else ""
	(%UseIcon as Button).disabled = unavailable or _texture(_selected_index) == null


func _select_slot(slot: int) -> void:
	var index := _page * PAGE_SIZE + slot
	if _texture(index) == null:
		return
	_selected_index = index
	_update_summary()
	_update_page()


func _select_default() -> void:
	_selected_index = PresentationSettings.DEFAULT_INDOOR_PARTY_ICON
	_page = floori(float(_selected_index) / PAGE_SIZE)
	_update_summary()
	_update_page()


func _change_page(delta: int) -> void:
	_page = wrapi(_page + delta, 0, PAGE_COUNT)
	_update_page()


func _update_page() -> void:
	for slot: int in _icon_buttons.size():
		var index := _page * PAGE_SIZE + slot
		var button := _icon_buttons[slot]
		button.icon = _texture(index)
		button.disabled = button.icon == null
		button.set_pressed_no_signal(index == _selected_index)
		button.tooltip_text = "Indoor party icon %d" % (index + 1)
		button.set_meta("record_id", "indoor-icon-%d" % index)
	(%PageLabel as Label).text = "%d / %d" % [_page + 1, PAGE_COUNT]
	(%UseIcon as Button).disabled = _media == null or _texture(_selected_index) == null


func _focus_selection() -> void:
	if not _picker_open:
		return
	var selected_slot := _selected_index - _page * PAGE_SIZE
	if selected_slot >= 0 and selected_slot < _icon_buttons.size() and not _icon_buttons[selected_slot].disabled:
		_icon_buttons[selected_slot].grab_focus()
		return
	for button: Button in _icon_buttons:
		if not button.disabled:
			button.grab_focus()
			return
	(%DefaultIcon as Button).grab_focus()


func _update_compact_layout() -> void:
	var profile := UiSizing.profile_for(self)
	var compact := (profile != null and profile.id == UiLayoutProfile.COMPACT) or get_viewport_rect().size.x < 1000.0
	(%CompactSummary as Control).visible = compact
	(%WideSummary as Control).visible = not compact
	(%PickerDescription as Control).visible = not compact
	(%PageHint as Control).visible = not compact
	(%CompactGuidance as Control).visible = compact
	(%PickerBody as Control).add_theme_constant_override(&"separation", 14 if compact else 28)


func _fit_picker() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	_update_compact_layout()
	var viewport := get_viewport_rect().size
	var panel := %PickerPanel as PanelContainer
	var profile := UiSizing.profile_for(self)
	var compact := viewport.x < 1000.0 or (profile != null and profile.id == UiLayoutProfile.COMPACT)
	var preferred := Vector2(1136.0, 648.0) if not compact else Vector2(736.0, 552.0)
	panel.size = Vector2(minf(preferred.x, viewport.x * 0.92), minf(preferred.y, viewport.y * 0.92))
	panel.position = (viewport - panel.size) * 0.5
	_update_compact_layout()


func _apply_picker_theme() -> void:
	if not is_node_ready():
		return
	var ancestor := get_parent()
	var source: Theme
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).theme != null and (ancestor as Control).theme.default_font != null:
			source = (ancestor as Control).theme
			break
		ancestor = ancestor.get_parent()
	if source == null:
		return
	var resolved := source.duplicate() as Theme
	resolved.merge_with(theme)
	(%PickerPanel as PanelContainer).theme = resolved
