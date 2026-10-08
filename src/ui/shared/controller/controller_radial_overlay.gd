## Presents a paged, tap-and-confirm quick-access command wheel.

class_name ControllerRadialOverlay
extends Control

signal command_selected(command_id: StringName)

const MAX_SECTORS_PER_PAGE := 8
const TILE_NAMES: Array[StringName] = [
	&"North", &"NorthEast", &"East", &"SouthEast",
	&"South", &"SouthWest", &"West", &"NorthWest",
]
const SLOT_KEYS: Array[int] = [
	KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8,
]

@export var page_size: int = 8
@export var prompt_family: String = ControllerPreferences.PROMPT_AUTO

@onready var _page_indicator: Label = %PageIndicator
@onready var _title: Label = %Title
@onready var _selection_label: Label = %SelectionLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _reason_label: Label = %ReasonLabel
@onready var _reason_panel: Control = %ReasonPanel
@onready var _reason_scroll: ScrollContainer = %ReasonScroll
@onready var _title_label: Label = %Title
@onready var _detail_heading: Label = %DetailHeading
@onready var _tile_buttons: Array[Button] = [
	%North as Button, %NorthEast as Button, %East as Button, %SouthEast as Button,
	%South as Button, %SouthWest as Button, %West as Button, %NorthWest as Button,
]
@onready var _tile_icons: Array[TextureRect] = [
	%NorthIcon as TextureRect, %NorthEastIcon as TextureRect, %EastIcon as TextureRect, %SouthEastIcon as TextureRect,
	%SouthIcon as TextureRect, %SouthWestIcon as TextureRect, %WestIcon as TextureRect, %NorthWestIcon as TextureRect,
]
@onready var _tile_symbols: Array[Label] = [
	%NorthSymbol as Label, %NorthEastSymbol as Label, %EastSymbol as Label, %SouthEastSymbol as Label,
	%SouthSymbol as Label, %SouthWestSymbol as Label, %WestSymbol as Label, %NorthWestSymbol as Label,
]
@onready var _tile_labels: Array[Label] = [
	%NorthLabel as Label, %NorthEastLabel as Label, %EastLabel as Label, %SouthEastLabel as Label,
	%SouthLabel as Label, %SouthWestLabel as Label, %WestLabel as Label, %NorthWestLabel as Label,
]
@onready var _previous_button: Button = %PreviousButton
@onready var _next_button: Button = %NextButton
@onready var _select_button: Button = %SelectButton
@onready var _cancel_button: Button = %CancelButton
@onready var _panel: Control = $Panel
@onready var _window_frame: PanelContainer = $WindowFrame
@onready var _wheel: Control = $Panel/Wheel
@onready var _divider: Control = $Panel/Wheel/Divider
@onready var _detail: Control = $Panel/Wheel/Detail
@onready var _footer: Control = $Panel/Wheel/Footer
@onready var _workspace_hints: Label = %WorkspaceHints
@onready var _tile_contents: Array[VBoxContainer] = [
	$Panel/Wheel/North/NorthContent as VBoxContainer, $Panel/Wheel/NorthEast/NorthEastContent as VBoxContainer,
	$Panel/Wheel/East/EastContent as VBoxContainer, $Panel/Wheel/SouthEast/SouthEastContent as VBoxContainer,
	$Panel/Wheel/South/SouthContent as VBoxContainer, $Panel/Wheel/SouthWest/SouthWestContent as VBoxContainer,
	$Panel/Wheel/West/WestContent as VBoxContainer, $Panel/Wheel/NorthWest/NorthWestContent as VBoxContainer,
]

var _entries: Array[ControllerRadialEntry] = []
var _page: int = 0
var _selected_index: int = 0
var _open: bool = false
var _text_scale: float = 1.0
var _interface_size := 1.0
var _standalone_workspaces: bool = false
@onready var _tile_icon_pairs: Array[HBoxContainer] = [
	%NorthPairedIcons as HBoxContainer, %NorthEastPairedIcons as HBoxContainer,
	%EastPairedIcons as HBoxContainer, %SouthEastPairedIcons as HBoxContainer,
	%SouthPairedIcons as HBoxContainer, %SouthWestPairedIcons as HBoxContainer,
	%WestPairedIcons as HBoxContainer, %NorthWestPairedIcons as HBoxContainer,
]


func _ready() -> void:
	visible = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	for index: int in MAX_SECTORS_PER_PAGE:
		var tile := _tile_buttons[index]
		tile.focus_entered.connect(_select_index.bind(index))
		tile.mouse_entered.connect(_select_index.bind(index))
		tile.pressed.connect(_on_tile_pressed.bind(index))
	_previous_button.pressed.connect(previous_page)
	_next_button.pressed.connect(next_page)
	_select_button.pressed.connect(confirm_selected)
	_cancel_button.pressed.connect(cancel)
	_apply_text_scale()
	_update_text()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_text_scale()
	elif what == NOTIFICATION_RESIZED and is_node_ready() and _standalone_workspaces:
		_apply_mode_layout()


func open(entries: Array[ControllerRadialEntry], initial_index: int = 0) -> void:
	_entries = entries.duplicate()
	_page = 0
	_selected_index = clampi(initial_index, 0, maxi(0, mini(_effective_page_size(), _entries.size()) - 1))
	_open = not _entries.is_empty()
	visible = _open
	_apply_mode_layout()
	if _open:
		_update_text()
		_tile_buttons[_selected_index].grab_focus.call_deferred()


func set_title(value: String) -> void:
	if is_node_ready():
		_title.text = value


func set_workspaces_presentation(enabled: bool) -> void:
	_standalone_workspaces = enabled
	_apply_mode_layout()


## Lets the presentation owner supply its already-resolved platform prompt family.
func set_prompt_family(value: String) -> void:
	if value in ControllerPreferences.PROMPT_FAMILIES:
		prompt_family = value
		_update_text()


func close() -> void:
	_open = false
	visible = false


func is_open() -> bool:
	return _open


func set_entries(entries: Array[ControllerRadialEntry]) -> void:
	_entries = entries.duplicate()
	_page = mini(_page, maxi(0, page_count() - 1))
	_selected_index = mini(_selected_index, maxi(0, current_page_entries().size() - 1))
	_update_text()


func confirm_selected() -> void:
	if not _open:
		return
	var current := current_page_entries()
	if _selected_index < 0 or _selected_index >= current.size():
		return
	var entry := current[_selected_index]
	if not entry.enabled:
		_update_text()
		return
	command_selected.emit(entry.id)
	close()


func cancel() -> void:
	close()


func previous_page() -> void:
	if page_count() <= 1:
		return
	_page = posmod(_page - 1, page_count())
	_selected_index = mini(_selected_index, maxi(0, current_page_entries().size() - 1))
	_update_text()
	_focus_selected_tile()


func next_page() -> void:
	if page_count() <= 1:
		return
	_page = (_page + 1) % page_count()
	_selected_index = mini(_selected_index, maxi(0, current_page_entries().size() - 1))
	_update_text()
	_focus_selected_tile()


func move_direction(direction: Vector2) -> void:
	if not _open or direction.is_zero_approx():
		return
	var count := current_page_entries().size()
	if count == 0:
		return
	var requested_angle := atan2(direction.y, direction.x)
	var nearest_index := 0
	var nearest_distance := INF
	for index: int in count:
		var sector_angle := -PI * 0.5 + TAU * float(index) / float(MAX_SECTORS_PER_PAGE)
		var distance := absf(wrapf(requested_angle - sector_angle, -PI, PI))
		if distance < nearest_distance:
			nearest_distance = distance
			nearest_index = index
	_select_index(nearest_index)
	_focus_selected_tile()


func scroll_reason(direction: Vector2i) -> void:
	if not _open or not _reason_panel.visible or direction.y == 0:
		return
	_reason_scroll.scroll_vertical += direction.y * 28


func _unhandled_key_input(event: InputEvent) -> void:
	if not _open or not event is InputEventKey or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var key_index := SLOT_KEYS.find(key.keycode)
	if key_index < 0:
		key_index = SLOT_KEYS.find(key.physical_keycode)
	if key_index >= 0:
		_select_index(key_index)
		_focus_selected_tile()
		get_viewport().set_input_as_handled()
		return
	match key.keycode:
		KEY_UP: move_direction(Vector2.UP)
		KEY_DOWN: move_direction(Vector2.DOWN)
		KEY_LEFT: move_direction(Vector2.LEFT)
		KEY_RIGHT: move_direction(Vector2.RIGHT)
		KEY_Q: move_direction(Vector2(-1, -1))
		KEY_E: move_direction(Vector2(1, -1))
		KEY_C: move_direction(Vector2(1, 1))
		KEY_Z: move_direction(Vector2(-1, 1))
		KEY_PAGEUP: previous_page()
		KEY_PAGEDOWN: next_page()
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: confirm_selected()
		KEY_ESCAPE: cancel()
		_: return
	get_viewport().set_input_as_handled()


func current_page_entries() -> Array[ControllerRadialEntry]:
	var result: Array[ControllerRadialEntry] = []
	var first := _page * _effective_page_size()
	var last := mini(first + _effective_page_size(), _entries.size())
	for index: int in range(first, last):
		result.append(_entries[index])
	return result


func page_count() -> int:
	return maxi(1, ceili(float(_entries.size()) / float(_effective_page_size())))


func _effective_page_size() -> int:
	return clampi(page_size, 1, MAX_SECTORS_PER_PAGE)


func _apply_text_scale() -> void:
	if not is_node_ready():
		return
	var active_theme := get_theme()
	var baseline_size := 15.0
	if active_theme != null and active_theme.default_font != null and active_theme.default_font.resource_path.ends_with("Theldrow-Rebuilt.ttf"):
		baseline_size = 17.0
	var scale := float(get_theme_default_font_size()) / baseline_size
	_text_scale = scale
	_scale_label(_title_label, 20, scale)
	_scale_label(_detail_heading, 14, scale)
	_scale_label(_detail_label, 22, scale)
	_scale_label(_selection_label, 14, scale)
	_scale_label(_reason_label, 15, scale)
	for label: Label in _tile_labels:
		_scale_caption(label)
	for symbol: Label in _tile_symbols:
		_scale_label(symbol, 20, scale)


func _scale_label(label: Label, base_size: int, _scale: float) -> void:
	UiSizing.font_size(label, &"font_size", base_size)


func _scale_caption(label: Label) -> void:
	UiSizing.font_size(label, &"font_size", 12)


func _select_index(index: int) -> void:
	if not _open or index < 0 or index >= current_page_entries().size():
		return
	_selected_index = index
	_update_text()


func _on_tile_pressed(index: int) -> void:
	_select_index(index)
	confirm_selected()


func _focus_selected_tile() -> void:
	var current := current_page_entries()
	if not current.is_empty():
		_tile_buttons[_selected_index].grab_focus()


func _update_text() -> void:
	if not is_node_ready():
		return
	var current := current_page_entries()
	_page_indicator.text = "Page %d / %d" % [_page + 1, page_count()]
	if _standalone_workspaces:
		_title.text = "Workspaces  •  Page %d / %d" % [_page + 1, page_count()]
		_page_indicator.hide()
	else:
		_page_indicator.show()
	_previous_button.disabled = page_count() <= 1
	_next_button.disabled = page_count() <= 1
	_update_tiles(current)
	if current.is_empty():
		_selection_label.text = "No commands"
		_detail_label.text = ""
		_reason_label.text = ""
		_reason_panel.visible = false
	else:
		var entry := current[clampi(_selected_index, 0, current.size() - 1)]
		_selection_label.text = ("%s\nConfirm" % entry.label) if _standalone_workspaces and entry.enabled else entry.label
		_detail_label.text = entry.label
		_reason_label.text = "Unavailable: %s" % entry.disabled_reason if not entry.enabled and not entry.disabled_reason.is_empty() else ("Unavailable" if not entry.enabled else "")
		_reason_panel.visible = not _reason_label.text.is_empty()
		_reason_scroll.scroll_vertical = 0
	_select_button.disabled = current.is_empty() or not current[_selected_index].enabled
	_select_button.text = "%s  Select" % _binding_label(&"realmz_controller_confirm")
	_cancel_button.text = "%s  Cancel" % _binding_label(&"realmz_controller_back")
	_previous_button.text = "%s  Previous" % _binding_label(&"realmz_controller_section_previous")
	_next_button.text = "%s  Next" % _binding_label(&"realmz_controller_section_next")
	_workspace_hints.text = "%s / %s  Page\n%s  Confirm\n%s  Cancel" % [
		_binding_label(&"realmz_controller_section_previous"),
		_binding_label(&"realmz_controller_section_next"),
		_binding_label(&"realmz_controller_confirm"),
		_binding_label(&"realmz_controller_back"),
	]
	queue_redraw()


func _update_tiles(current: Array[ControllerRadialEntry]) -> void:
	for index: int in MAX_SECTORS_PER_PAGE:
		var present := index < current.size()
		_tile_buttons[index].visible = present
		if not present:
			continue
		var entry := current[index]
		_tile_labels[index].text = entry.label
		if _standalone_workspaces:
			_scale_workspace_caption(_tile_labels[index])
		else:
			_scale_caption(_tile_labels[index])
		_tile_icons[index].texture = entry.icon
		_tile_icons[index].visible = entry.icon != null and entry.secondary_icon == null
		_tile_symbols[index].text = entry.fallback_symbol
		_tile_symbols[index].visible = entry.icon == null and entry.secondary_icon == null and not entry.fallback_symbol.is_empty()
		var paired := _tile_icon_pairs[index]
		paired.visible = entry.icon != null and entry.secondary_icon != null
		if paired.visible:
			(paired.get_child(0) as TextureRect).texture = entry.icon
			(paired.get_child(1) as TextureRect).texture = entry.secondary_icon
		_tile_buttons[index].tooltip_text = "Unavailable: %s" % entry.disabled_reason if not entry.enabled and not entry.disabled_reason.is_empty() else entry.label
		_tile_buttons[index].modulate = Color.WHITE if entry.enabled else Color(0.58, 0.62, 0.64)
		_tile_buttons[index].add_theme_stylebox_override("normal", _tile_style(index, false))
		_tile_buttons[index].add_theme_stylebox_override("hover", _tile_style(index, true))
		_tile_buttons[index].add_theme_stylebox_override("focus", _tile_style(index, true))
		_tile_buttons[index].add_theme_stylebox_override("pressed", _tile_style(index, true))


func _apply_mode_layout() -> void:
	if not is_node_ready():
		return
	if _standalone_workspaces:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window_frame.hide()
		_wheel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_wheel.size = Vector2(776, 538) * _interface_size
		var center := Vector2(size.x * 0.36, maxf(size.y * 0.395, 260.0 * _interface_size))
		_wheel.scale = Vector2.ONE
		_wheel.position = center - Vector2(230, 286) * _interface_size
		$Panel/Wheel/Heading.position = Vector2(12.0 * _interface_size, size.y * 0.07 - _wheel.position.y)
		$Panel/Wheel/Heading.size = Vector2(440, 42) * _interface_size
		_divider.hide()
		_detail.hide()
		_footer.hide()
		_workspace_hints.show()
		_workspace_hints.position = Vector2(458, 226) * _interface_size
		_workspace_hints.size = Vector2(155, 112) * _interface_size
		UiSizing.font_size(_workspace_hints, &"font_size", 18)
		$Panel/Wheel/ReasonPanel.position = Vector2(458, 340) * _interface_size
		$Panel/Wheel/ReasonPanel.size = Vector2(155, 108) * _interface_size
		UiSizing.minimum_size(_reason_label, Vector2(130, 0))
		UiSizing.font_size(_reason_label, &"font_size", 14)
		var center_size := 108.0 * _interface_size
		$Panel/Wheel/Card.position = Vector2(230, 286) * _interface_size - Vector2.ONE * center_size * 0.5
		$Panel/Wheel/Card.size = Vector2.ONE * center_size
		$Panel/Wheel/Card.add_theme_stylebox_override("panel", _workspace_center_style(center_size * 0.5))
		UiSizing.minimum_size(_selection_label, Vector2.ONE * 92.0)
		UiSizing.font_size(_selection_label, &"font_size", 16)
	else:
		_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_window_frame.show()
		_wheel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_wheel.size = Vector2(776, 538) * _interface_size
		_wheel.scale = Vector2.ONE
		_wheel.position = size * 0.5 - Vector2(400, 280) * _interface_size
		$Panel/Wheel/Heading.position = Vector2(12, 4) * _interface_size
		$Panel/Wheel/Heading.size = Vector2(438, 48) * _interface_size
		_divider.show()
		_detail.show()
		_footer.show()
		_workspace_hints.hide()
		$Panel/Wheel/ReasonPanel.position = Vector2(480, 330) * _interface_size
		$Panel/Wheel/ReasonPanel.size = Vector2(290, 108) * _interface_size
		UiSizing.minimum_size(_reason_label, Vector2(264, 0))
		$Panel/Wheel/Card.position = Vector2(174, 258) * _interface_size
		$Panel/Wheel/Card.size = Vector2(112, 56) * _interface_size
		$Panel/Wheel/Card.remove_theme_stylebox_override("panel")
		UiSizing.minimum_size(_selection_label, Vector2(96, 40))
		_apply_text_scale()
	queue_redraw()


func _workspace_center_style(radius: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#202b30")
	style.border_color = Color("#d1ad61")
	style.set_border_width_all(3)
	style.set_corner_radius_all(int(round(radius)))
	return style


func _scale_workspace_caption(label: Label) -> void:
	UiSizing.font_size(label, &"font_size", 13)


func apply_ui_sizing(profile: UiLayoutProfile) -> void:
	_interface_size = profile.ui_scale
	_apply_mode_layout()


func _draw() -> void:
	if not _standalone_workspaces or _wheel == null:
		return
	draw_set_transform(_wheel.position, 0.0, Vector2.ONE * _interface_size)
	var center := Vector2(230, 286)
	var outer_radius := 208.0
	for index: int in MAX_SECTORS_PER_PAGE:
		var start_angle := -PI * 0.5 - PI / 8.0 + TAU * float(index) / 8.0
		var end_angle := start_angle + TAU / 8.0
		var wedge := PackedVector2Array([center])
		for step: int in 15:
			var angle := lerpf(start_angle, end_angle, float(step) / 14.0)
			wedge.append(center + Vector2.from_angle(angle) * outer_radius)
		var current := _page * _effective_page_size() + index
		var color := Color("#394951") if index % 2 == 0 else Color("#303f47")
		if current == _page * _effective_page_size() + _selected_index:
			color = Color("#655536")
		if current < _entries.size() and not _entries[current].enabled:
			color = color.darkened(0.22)
		draw_colored_polygon(wedge, color)
		draw_line(center, center + Vector2.from_angle(start_angle) * outer_radius, Color("#9ba6a1"), 1.2, true)
	draw_line(center, center + Vector2.from_angle(-PI * 0.5 - PI / 8.0 + TAU) * outer_radius, Color("#9ba6a1"), 1.2, true)
	draw_arc(center, outer_radius, 0.0, TAU, 96, Color("#b6c0b8"), 1.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tile_style(index: int, highlighted: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	if _standalone_workspaces:
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = Color(0, 0, 0, 0)
		style.set_border_width_all(0)
		return style
	var entry := current_page_entries()[index]
	style.bg_color = Color("#6b5734") if index == _selected_index and highlighted else Color("#473b28") if index == _selected_index else Color("#263743") if entry.enabled else Color("#242d32")
	style.border_color = Color("#d1ad61") if index == _selected_index else Color("#75868a")
	style.set_border_width_all(2 if index == _selected_index else 1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style


func _binding_label(action_id: StringName) -> String:
	if not InputMap.has_action(action_id):
		return ""
	for event: InputEvent in InputMap.action_get_events(action_id):
		if event is InputEventJoypadButton:
			return _joy_button_label((event as InputEventJoypadButton).button_index)
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			return "Axis %d%s" % [motion.axis, "+" if motion.axis_value > 0.0 else "−"]
	return "Unbound"


func _joy_button_label(code: int) -> String:
	var family := prompt_family
	if family == ControllerPreferences.PROMPT_AUTO:
		var devices := Input.get_connected_joypads()
		if devices.size() == 1:
			var name := Input.get_joy_name(devices[0]).to_lower()
			if "playstation" in name or "dualshock" in name or "dualsense" in name or "sony" in name:
				family = ControllerPreferences.PROMPT_PLAYSTATION
			elif "switch" in name or "nintendo" in name or "joy-con" in name:
				family = ControllerPreferences.PROMPT_SWITCH
			elif "xbox" in name or "xinput" in name:
				family = ControllerPreferences.PROMPT_XBOX
			else:
				family = ControllerPreferences.PROMPT_GENERIC
		else:
			family = ControllerPreferences.PROMPT_GENERIC
	if code == JOY_BUTTON_A: return _face_label(&"south", family)
	if code == JOY_BUTTON_B: return _face_label(&"east", family)
	if code == JOY_BUTTON_X: return _face_label(&"west", family)
	if code == JOY_BUTTON_Y: return _face_label(&"north", family)
	if code == JOY_BUTTON_LEFT_SHOULDER: return "L1" if family == ControllerPreferences.PROMPT_PLAYSTATION else "LB"
	if code == JOY_BUTTON_RIGHT_SHOULDER: return "R1" if family == ControllerPreferences.PROMPT_PLAYSTATION else "RB"
	return "Button %d" % code


func _face_label(position: StringName, family: String) -> String:
	match family:
		ControllerPreferences.PROMPT_PLAYSTATION:
			return {&"south": "Cross", &"east": "Circle", &"west": "Square", &"north": "Triangle"}.get(position, "Button")
		ControllerPreferences.PROMPT_SWITCH:
			return {&"south": "B", &"east": "A", &"west": "Y", &"north": "X"}.get(position, "Button")
		ControllerPreferences.PROMPT_XBOX:
			return {&"south": "A", &"east": "B", &"west": "X", &"north": "Y"}.get(position, "Button")
	return {&"south": "South", &"east": "East", &"west": "West", &"north": "North"}.get(position, "Button")
