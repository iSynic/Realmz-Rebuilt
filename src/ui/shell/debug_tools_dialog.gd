## Presents debug tools dialog through the Godot interface.

class_name DebugToolsDialog
extends PanelContainer

signal command_requested(command: SessionDebugCommand)
signal noclip_changed(enabled: bool)
signal topology_debug_changed(enabled: bool)
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
var _topology_debug: CheckButton
var _status: Label
var _auto_log: MenuButton
var _console_shortcut: CheckButton


func _ready() -> void:
	_map_select = %MapSelect
	_x = %WarpX
	_y = %WarpY
	_encounter_kind = %EncounterKind
	_encounter_id = %EncounterId
	_battle_id = %BattleId
	_warp = %Warp
	_restore = %Restore
	_trigger_encounter = %TriggerEncounter
	_trigger_battle = %TriggerBattle
	_win_battle = %WinBattle
	_noclip = %Noclip
	_topology_debug = %TopologyDebug
	_status = %Status
	_auto_log = %RecentAutoActions
	_console_shortcut = %ConsoleShortcut
	for input: SpinBox in [_x, _y, _encounter_id, _battle_id]:
		input.get_line_edit().select_all_on_focus = true
	_encounter_kind.set_item_metadata(0, &"simple")
	_encounter_kind.set_item_metadata(1, &"complex")
	_warp.pressed.connect(_request_warp)
	_noclip.toggled.connect(func(enabled: bool) -> void: noclip_changed.emit(enabled))
	_topology_debug.toggled.connect(func(enabled: bool) -> void: topology_debug_changed.emit(enabled))
	_restore.pressed.connect(func() -> void: command_requested.emit(SessionDebugCommand.restore_party()))
	_trigger_encounter.pressed.connect(_request_encounter)
	_trigger_battle.pressed.connect(_request_battle)
	_win_battle.pressed.connect(func() -> void: command_requested.emit(SessionDebugCommand.win_battle()))
	%OpenConsole.pressed.connect(func() -> void: console_requested.emit())
	_console_shortcut.toggled.connect(func(enabled: bool) -> void: console_shortcut_changed.emit(enabled))
	%Close.pressed.connect(close_dialog)


func _request_warp() -> void:
	command_requested.emit(SessionDebugCommand.warp(String(_map_select.get_item_metadata(_map_select.selected)), Vector2i(int(_x.value), int(_y.value))))


func _request_encounter() -> void:
	command_requested.emit(SessionDebugCommand.start_encounter(_encounter_kind.get_item_metadata(_encounter_kind.selected), int(_encounter_id.value)))


func _request_battle() -> void:
	command_requested.emit(SessionDebugCommand.start_battle(int(_battle_id.value)))


func present(view: GameView, maps: Array[Dictionary], noclip: bool, auto_actions: Array[String] = [], console_shortcut_enabled: bool = true, topology_debug: bool = false) -> void:
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
	_topology_debug.set_pressed_no_signal(topology_debug)
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


func set_topology_debug(enabled: bool) -> void:
	if _topology_debug != null:
		_topology_debug.set_pressed_no_signal(enabled)


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
