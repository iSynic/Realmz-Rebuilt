class_name DebugToolsDialog
extends PanelContainer

signal command_requested(command: SessionDebugCommand)
signal noclip_changed(enabled: bool)
signal console_requested
signal console_shortcut_changed(enabled: bool)

var _map_select: OptionButton
var _x: SpinBox
var _y: SpinBox
var _encounter_kind: OptionButton
var _encounter_id: SpinBox
var _battle_id: SpinBox
var _warp: Button
var _restore: Button
var _trigger_encounter: Button
var _trigger_battle: Button
var _win_battle: Button
var _noclip: CheckButton
var _status: Label
var _auto_log: MenuButton
var _console_shortcut: CheckButton


func _ready() -> void:
	name = "DebugToolsDialog"
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -260.0
	offset_top = -270.0
	offset_right = 260.0
	offset_bottom = 270.0
	z_index = 500
	var style := StyleBoxFlat.new()
	style.bg_color = Color("20262b")
	style.border_color = Color("bd9c55")
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 14.0
	style.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", style)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)
	var title := Label.new()
	title.text = "DEBUG TOOLS · F12"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	root.add_child(title)
	_status = Label.new()
	_status.text = "Debug-only commands are not saved."
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)
	root.add_child(_heading("Exploration"))
	_map_select = OptionButton.new()
	root.add_child(_labelled("Map", _map_select))
	_x = _integer_input(0, 255)
	_x.name = "WarpX"
	_y = _integer_input(0, 255)
	_y.name = "WarpY"
	var coordinates := HBoxContainer.new()
	coordinates.add_child(_labelled("X", _x))
	coordinates.add_child(_labelled("Y", _y))
	root.add_child(coordinates)
	_warp = _button("Warp to map / X,Y", func() -> void: command_requested.emit(SessionDebugCommand.warp(String(_map_select.get_item_metadata(_map_select.selected)), Vector2i(int(_x.value), int(_y.value)))))
	root.add_child(_warp)
	_noclip = CheckButton.new()
	_noclip.text = "No clip movement"
	_noclip.toggled.connect(func(enabled: bool) -> void: noclip_changed.emit(enabled))
	root.add_child(_noclip)
	root.add_child(_heading("Party and scenarios"))
	_restore = _button("Restore party HP / SP and bad conditions", func() -> void: command_requested.emit(SessionDebugCommand.restore_party()))
	root.add_child(_restore)
	_encounter_kind = OptionButton.new()
	_encounter_kind.add_item("Simple Encounter")
	_encounter_kind.set_item_metadata(0, &"simple")
	_encounter_kind.add_item("Complex Encounter")
	_encounter_kind.set_item_metadata(1, &"complex")
	_encounter_id = _integer_input(0, 32767)
	var encounter_row := HBoxContainer.new()
	encounter_row.add_child(_encounter_kind)
	encounter_row.add_child(_labelled("ID", _encounter_id))
	_trigger_encounter = _button("Trigger encounter", func() -> void: command_requested.emit(SessionDebugCommand.start_encounter(_encounter_kind.get_item_metadata(_encounter_kind.selected), int(_encounter_id.value))))
	encounter_row.add_child(_trigger_encounter)
	root.add_child(encounter_row)
	_battle_id = _integer_input(0, 32767)
	var battle_row := HBoxContainer.new()
	battle_row.add_child(_labelled("Battle ID", _battle_id))
	_trigger_battle = _button("Trigger battle", func() -> void: command_requested.emit(SessionDebugCommand.start_battle(int(_battle_id.value))))
	battle_row.add_child(_trigger_battle)
	root.add_child(battle_row)
	_win_battle = _button("Win current battle", func() -> void: command_requested.emit(SessionDebugCommand.win_battle()))
	root.add_child(_win_battle)
	_auto_log = MenuButton.new()
	_auto_log.name = "RecentAutoActions"
	root.add_child(_auto_log)
	root.add_child(_button("Open game-action console · ` / ~", func() -> void: console_requested.emit()))
	_console_shortcut = CheckButton.new()
	_console_shortcut.text = "Enable ` / ~ console shortcut"
	_console_shortcut.button_pressed = true
	_console_shortcut.toggled.connect(func(enabled: bool) -> void: console_shortcut_changed.emit(enabled))
	root.add_child(_console_shortcut)
	root.add_child(_button("Close", close_dialog))
	visible = false


func present(view: GameView, maps: Array[Dictionary], noclip: bool, auto_actions: Array[String] = [], console_shortcut_enabled: bool = true) -> void:
	var selected_map := "" if view == null else view.party_map_id
	_map_select.clear()
	for record: Dictionary in maps:
		_map_select.add_item(String(record["label"]))
		_map_select.set_item_metadata(_map_select.item_count - 1, String(record["id"]))
		if String(record["id"]) == selected_map:
			_map_select.select(_map_select.item_count - 1)
	var exploration := view != null and view.session_started and not view.party_setup_available and view.pending_interaction == null and view.combat_view == null
	var active_battle := view != null and view.combat_view != null and view.combat_view.outcome == &"active"
	_x.value = 0 if view == null else view.party_coordinate.x
	_y.value = 0 if view == null else view.party_coordinate.y
	_noclip.set_pressed_no_signal(noclip)
	_console_shortcut.set_pressed_no_signal(console_shortcut_enabled)
	_warp.disabled = not exploration or maps.is_empty()
	_noclip.disabled = not exploration
	_restore.disabled = not (exploration or active_battle)
	_trigger_encounter.disabled = not exploration
	_trigger_battle.disabled = not exploration
	_win_battle.disabled = not active_battle
	set_auto_actions(auto_actions)
	_status.text = "Exploration tools ready." if exploration else "Battle tools ready." if active_battle else "Commands are unavailable at this boundary."
	show()
	_x.get_line_edit().grab_focus()
	_x.get_line_edit().select_all()


func show_result(message: String, failed: bool) -> void:
	_status.text = ("Rejected · " if failed else "Committed · ") + message


func set_auto_actions(actions: Array[String]) -> void:
	_auto_log.text = "Recent Auto actions · %d" % actions.size()
	var popup := _auto_log.get_popup()
	popup.clear()
	if actions.is_empty():
		popup.add_item("No Auto actions recorded yet.")
	else:
		for index: int in range(actions.size() - 1, -1, -1):
			popup.add_item(actions[index])
	for index: int in popup.item_count:
		popup.set_item_disabled(index, true)


func close_dialog() -> void:
	hide()
	if is_inside_tree():
		release_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"realmz_back"):
		close_dialog()
		get_viewport().set_input_as_handled()


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color("efd88b"))
	return label


static func _labelled(text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return row


static func _integer_input(minimum: int, maximum: int) -> SpinBox:
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.allow_greater = false
	input.allow_lesser = false
	input.editable = true
	input.update_on_text_changed = true
	var line_edit := input.get_line_edit()
	line_edit.editable = true
	line_edit.select_all_on_focus = true
	line_edit.mouse_filter = Control.MOUSE_FILTER_STOP
	return input


static func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button
