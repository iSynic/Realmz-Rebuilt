## Presents debug tools dialog through the Godot interface.

class_name DebugToolsDialog
extends PanelContainer

signal command_requested(command: SessionDebugCommand)
signal noclip_changed(enabled: bool)
signal topology_debug_changed(enabled: bool)
signal console_requested
signal console_shortcut_changed(enabled: bool)

@export var developer_preferred_size := Vector2(740.0, 640.0)
@export var developer_window_fraction := Vector2(0.75, 0.9)
@export var diagnostics_preferred_size := Vector2(520.0, 240.0)

var _map_select: OptionButton
var _x: SpinBox
var _y: SpinBox
var _encounter_kind: OptionButton
var _encounter_id: SpinBox
var _battle_id: SpinBox
var _warp: Button
var _restore: Button
var _item_recipient: OptionButton
var _item_search: LineEdit
var _item_matches: OptionButton
var _grant_item: Button
var _item_records: Array[Dictionary] = []
var _item_grant_available: bool = false
var _trigger_encounter: Button
var _trigger_battle: Button
var _win_battle: Button
var _noclip: CheckButton
var _topology_debug: CheckButton
var _status: Label
var _auto_log: MenuButton
var _console_shortcut: CheckButton
var _title: Label
var _developer_tools_enabled: bool = false

const DEVELOPER_CONTROL_NAMES: Array[StringName] = [
	&"ExplorationHeading",
	&"MapRow",
	&"Coordinates",
	&"Warp",
	&"Noclip",
	&"PartyHeading",
	&"Restore",
	&"ItemGrantHeading",
	&"ItemRecipientRow",
	&"ItemSearchRow",
	&"ItemMatchRow",
	&"EncounterRow",
	&"BattleRow",
	&"WinBattle",
	&"RecentAutoActions",
	&"OpenConsole",
	&"ConsoleShortcut",
]


func _ready() -> void:
	_title = %Title
	_map_select = %MapSelect
	_x = %WarpX
	_y = %WarpY
	_encounter_kind = %EncounterKind
	_encounter_id = %EncounterId
	_battle_id = %BattleId
	_warp = %Warp
	_restore = %Restore
	_item_recipient = %ItemRecipient
	_item_search = %ItemSearch
	_item_matches = %ItemMatches
	_grant_item = %GrantItem
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
	_item_search.text_changed.connect(func(_text: String) -> void: _refresh_item_matches())
	_item_search.text_submitted.connect(func(_text: String) -> void: _request_item_grant())
	_item_recipient.item_selected.connect(func(_index: int) -> void: _update_item_grant_enabled())
	_item_matches.item_selected.connect(func(_index: int) -> void: _update_item_grant_enabled())
	_grant_item.pressed.connect(_request_item_grant)
	_trigger_encounter.pressed.connect(_request_encounter)
	_trigger_battle.pressed.connect(_request_battle)
	_win_battle.pressed.connect(func() -> void: command_requested.emit(SessionDebugCommand.win_battle()))
	%OpenConsole.pressed.connect(func() -> void: console_requested.emit())
	_console_shortcut.toggled.connect(func(enabled: bool) -> void: console_shortcut_changed.emit(enabled))
	%Close.pressed.connect(close_dialog)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_to_parent.call_deferred)
		visibility_changed.connect(_fit_to_parent)
	configure_capabilities(false)


func configure_capabilities(developer_tools_enabled: bool) -> void:
	_developer_tools_enabled = developer_tools_enabled
	for node_name: StringName in DEVELOPER_CONTROL_NAMES:
		var control := find_child(String(node_name), true, false) as Control
		if control != null:
			control.visible = developer_tools_enabled
	_title.text = "DEBUG TOOLS · F12" if developer_tools_enabled else "DIAGNOSTICS · F12"
	_status.text = "Debug commands can change this adventure." if developer_tools_enabled else "Optional map diagnostics are off until enabled here."
	_fit_to_parent()


func apply_ui_sizing(_profile: UiLayoutProfile) -> void:
	_fit_to_parent()


func _fit_to_parent() -> void:
	var parent := get_parent() as Control
	if parent == null or parent.size.x <= 0.0 or parent.size.y <= 0.0:
		return
	var profile := UiSizing.profile_for(self)
	var interface_scale := profile.ui_scale if profile != null else 1.0
	var preferred := (developer_preferred_size if _developer_tools_enabled else diagnostics_preferred_size) * interface_scale
	var desired := parent.size * developer_window_fraction if _developer_tools_enabled else preferred
	var available := parent.size - Vector2(32.0, 20.0) * interface_scale
	var modal_size := preferred.max(desired).min(available)
	offset_left = -modal_size.x * 0.5
	offset_right = modal_size.x * 0.5
	offset_top = -modal_size.y * 0.5
	offset_bottom = modal_size.y * 0.5


func _request_warp() -> void:
	command_requested.emit(SessionDebugCommand.warp(String(_map_select.get_item_metadata(_map_select.selected)), Vector2i(int(_x.value), int(_y.value))))


func _request_encounter() -> void:
	command_requested.emit(SessionDebugCommand.start_encounter(_encounter_kind.get_item_metadata(_encounter_kind.selected), int(_encounter_id.value)))


func _request_battle() -> void:
	command_requested.emit(SessionDebugCommand.start_battle(int(_battle_id.value)))


func _request_item_grant() -> void:
	if _grant_item.disabled:
		return
	command_requested.emit(SessionDebugCommand.grant_item(String(_item_matches.get_item_metadata(_item_matches.selected)), String(_item_recipient.get_item_metadata(_item_recipient.selected))))


func _refresh_item_matches() -> void:
	_item_matches.clear()
	var query := _item_search.text.strip_edges()
	if not query.is_empty():
		var numeric_id := query.is_valid_int()
		for record: Dictionary in _item_records:
			if (numeric_id and int(record["classicId"]) == int(query)) or (not numeric_id and String(record["name"]).to_lower().contains(query.to_lower())):
				_item_matches.add_item("%d · %s" % [int(record["classicId"]), String(record["name"])])
				_item_matches.set_item_metadata(_item_matches.item_count - 1, String(record["id"]))
				if _item_matches.item_count >= 50:
					break
	if _item_matches.item_count == 0:
		_item_matches.add_item("Enter an ID or title" if query.is_empty() else "No matching items")
		_item_matches.disabled = true
	else:
		_item_matches.select(0)
		_item_matches.disabled = false
	_update_item_grant_enabled()


func _update_item_grant_enabled() -> void:
	_grant_item.disabled = not _item_grant_available or _item_recipient.selected < 0 or _item_matches.disabled or _item_matches.selected < 0


func present(view: GameView, maps: Array[Dictionary], noclip: bool, auto_actions: Array[String] = [], console_shortcut_enabled: bool = false, topology_debug: bool = false, item_records: Array[Dictionary] = []) -> void:
	if not _developer_tools_enabled:
		_topology_debug.set_pressed_no_signal(topology_debug)
		_status.text = "AP and random-rectangle overlay enabled." if topology_debug else "Optional map diagnostics are off until enabled here."
		show()
		_topology_debug.grab_focus()
		return
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
	_item_records = item_records
	_item_grant_available = exploration
	_item_recipient.clear()
	if view != null:
		for member: CharacterView in view.party_members:
			_item_recipient.add_item(member.name)
			_item_recipient.set_item_metadata(_item_recipient.item_count - 1, member.id)
	if _item_recipient.item_count > 0:
		_item_recipient.select(0)
	_item_recipient.disabled = not exploration or _item_recipient.item_count == 0
	_item_search.editable = exploration
	_refresh_item_matches()
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
