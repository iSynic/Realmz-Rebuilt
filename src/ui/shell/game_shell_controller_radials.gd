## Coordinates action, workspace and HUD panel selectors for the retained shell.
class_name GameShellControllerRadials
extends RefCounted

var _shell: GameShell
var _kind: StringName = &""
var _activation := Callable()

func _init(shell: GameShell) -> void:
	_shell = shell

func is_open() -> bool: return _shell.controller_radial.is_open()


func open_actions() -> bool:
	var entries: Array[ControllerRadialEntry] = _shell.commands.controller_entries()
	if _shell.navigator.current_screen() == &"exploration":
		var available: bool = _shell.exploration_move_to_available.is_valid() and _shell.exploration_move_to_available.call()
		entries.append(ControllerRadialEntry.new(&"move_to", "Move To", available, "Available on the active two-dimensional exploration map." if not available else "", null, "✥"))
	if entries.is_empty(): return false
	_open_radial(&"action", "ACTIONS", entries)
	return true


func open_interaction(entries: Array[ControllerRadialEntry], activation: Callable) -> bool:
	if entries.is_empty() or not activation.is_valid(): return false
	_open_radial(&"interaction", "ACTIONS", entries)
	_activation = activation
	return true


func open_workspaces() -> bool:
	var entries: Array[ControllerRadialEntry] = []
	var route_reason := GameShellAvailability.route_change_reason(_shell.current_view)
	var definitions: Array[Dictionary] = [
		{"id": &"inventory", "label": "Items", "icon": &"inventory"},
		{"id": &"spells", "label": "Spells", "icon": &"spells"},
		{"id": &"journal", "label": "Maps / Notes", "icon": &"maps"},
		{"id": &"character", "label": "Characters", "symbol": "♟"},
		{"id": &"services", "label": "Money", "icon": &"money"},
		{"id": &"workspace_preferences", "label": "Preferences", "icon": &"settings"},
		{"id": &"workspace_save_load", "label": "Save & Load", "icon": &"save"},
		{"id": &"exploration", "label": "Explore", "symbol": "✥"},
		{"id": &"vault", "label": "Character Files", "symbol": "▣"},
		{"id": &"allies", "label": "Allies", "symbol": "♙"},
		{"id": &"bestiary", "label": "Bestiary", "symbol": "♜"},
		{"id": &"workspace_music", "label": "Music", "symbol": "♫"},
		{"id": &"workspace_diagnostics", "label": "Diagnostics", "symbol": "◇"},
		{"id": &"workspace_pause", "label": "Pause", "symbol": "☰"},
	]
	for definition: Dictionary in definitions:
		var reason := route_reason
		if definition["id"] == &"allies" and reason.is_empty():
			reason = GameShellAvailability.allies_reason(_shell.current_view)
		var icon: Texture2D = _shell.commands.controller_icon(StringName(definition.get("icon", &"")))
		var entry := ControllerRadialEntry.new(StringName(definition["id"]), String(definition["label"]), reason.is_empty(), reason, icon, String(definition.get("symbol", "")))
		if entry.id == &"character" and _shell.media != null:
			entry.icon = _shell.media.image_texture(_shell.media.asset_by_resource("cicn", 9000))
			entry.secondary_icon = _shell.media.image_texture(_shell.media.asset_by_resource("cicn", 9006))
		entries.append(entry)
	if _shell.hud.active:
		entries.append(ControllerRadialEntry.new(&"workspace_hud", "HUD panels", true, "", null, "▤"))
	_open_radial(&"workspace", "WORKSPACES", entries, true)
	return true


func move(direction: Vector2i) -> void: _shell.controller_radial.move_direction(Vector2(direction))


func page(delta: int) -> void:
	if delta < 0: _shell.controller_radial.previous_page()
	else: _shell.controller_radial.next_page()


func scroll(direction: Vector2i) -> void: _shell.controller_radial.scroll_reason(direction)


func confirm() -> void: _shell.controller_radial.confirm_selected()


func release_hold() -> void: _shell.commands.release_controller_hold()


func cancel() -> bool:
	if not _shell.controller_radial.is_open(): return false
	_shell.controller_radial.cancel()
	_clear_radial_owner()
	return true


func on_selected(command_id: StringName) -> void:
	var kind := _kind
	var activation := _activation
	_clear_radial_owner()
	if kind == &"action" and command_id == &"move_to": _shell.exploration_move_to_requested.emit()
	elif kind == &"action": _shell.commands.activate_controller(command_id)
	elif kind == &"workspace": _activate_workspace(command_id)
	elif kind == &"hud": _shell.hud.focus_panel(int(String(command_id)))
	elif kind == &"interaction" and activation.is_valid(): activation.call(command_id)


func _activate_workspace(command_id: StringName) -> void:
	match command_id:
		&"workspace_preferences": _shell.navigator.open_screen(&"system", true, &"Display")
		&"workspace_save_load": _shell.navigator.open_screen(&"save_load")
		&"workspace_music": _shell.navigator.open_screen(&"system", true, &"Audio")
		&"workspace_diagnostics": _shell.navigator.open_screen(&"system", true, &"Diagnostics")
		&"workspace_pause": _shell.pause_controller.open()
		&"workspace_hud":
			var entries: Array[ControllerRadialEntry] = []
			for index: int in ModularHud.TITLES.size():
				entries.append(ControllerRadialEntry.new(StringName(str(index)), ModularHud.TITLES[index], true, "", null, "▤"))
			_open_radial(&"hud", "HUD PANELS", entries)
		_: _shell.navigator.open_screen(command_id)


func _open_radial(kind: StringName, title: String, entries: Array[ControllerRadialEntry], standalone_workspaces: bool = false) -> void:
	_kind = kind
	_activation = Callable()
	_shell.controller_radial.set_title(title)
	_shell.controller_radial.set_workspaces_presentation(standalone_workspaces)
	_shell.controller_radial.open(entries)


func _clear_radial_owner() -> void:
	_kind = &""
	_activation = Callable()
