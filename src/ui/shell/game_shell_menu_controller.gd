## Populates shell menus and routes enabled selections to their named owner.
class_name GameShellMenuController
extends RefCounted

var _owner_ref: WeakRef
var _actions: Dictionary = {}
var _connected: Dictionary = {}
var _controller_active: bool = false
var _controller_popup_open: bool = false
var _controller_heading: int = 0
var _controller_item: int = 0
var _controller_restore_focus: WeakRef


func _init(owner: Control) -> void:
	_owner_ref = weakref(owner)


func _owner():
	return _owner_ref.get_ref()


func rebuild(game_view: GameView, settings: PresentationSettings, music_title: String, music_playing: bool) -> void:
	var owner = _owner()
	if owner == null or not owner.is_node_ready():
		return
	var contextual_definition: Dictionary = owner._command_controller.presentation_definition(ClassicCommandCatalog.command(&"contextual"))
	var contextual_label := String(contextual_definition.get("label", "Encounter"))
	var contextual_availability := StringName(contextual_definition.get("availability", &"contextual_encounter"))
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/InfoMenu"), [
		{"label": "About Realmz Rebuilt", "route": &"system"},
		{"label": "Package identity and readiness", "route": &"system"},
		{"label": "Diagnostics", "route": &"system"},
	])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/GameMenu"), [
		{"label": "Campaigns…", "system": &"campaigns", "disabled_reason": GameShellAvailability.campaign_library_reason(game_view)},
		{"label": "Save & Load…", "route": &"system", "disabled_reason": GameShellAvailability.save_reason(game_view)}, {"label": "Quick Save 1", "system": &"save", "value": "quick", "disabled_reason": GameShellAvailability.save_reason(game_view)}, {"label": "Quick Save 2", "system": &"save", "value": "quick-2", "disabled_reason": GameShellAvailability.save_reason(game_view)},
		{"label": "Quick Load 1", "system": &"load", "value": "quick", "disabled_reason": GameShellAvailability.load_reason(game_view)}, {"label": "Quick Load 2", "system": &"load", "value": "quick-2", "disabled_reason": GameShellAvailability.load_reason(game_view)},
		{"label": "Main Menu…", "system": &"end_adventure", "disabled_reason": GameShellAvailability.end_adventure_reason(game_view)},
		{"label": "Quit", "system": &"quit"},
	])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/AdventureMenu"), [
		{"label": "Explore", "route": &"exploration"},
		{"label": "Search", "command": &"search_mode", "disabled_reason": GameShellAvailability.action_reason(game_view, &"toggle_search")},
		{"label": "Area Search", "command": &"area_search", "disabled_reason": GameShellAvailability.action_reason(game_view, &"area_search")},
		{"label": "Torch", "command": &"torch", "disabled_reason": GameShellAvailability.action_reason(game_view, &"use_torch")},
		{"label": "Camp", "command": &"camp", "disabled_reason": GameShellAvailability.action_reason(game_view, &"camp")},
		{"label": "Rest", "command": &"rest", "disabled_reason": GameShellAvailability.action_reason(game_view, &"rest")},
		{"label": "Heal", "command": &"heal", "disabled_reason": GameShellAvailability.action_reason(game_view, &"heal")},
		{"label": contextual_label, "command": &"contextual", "disabled_reason": GameShellAvailability.action_reason(game_view, contextual_availability)},
		{"label": "Money", "command": &"money", "disabled_reason": GameShellAvailability.action_reason(game_view, &"money_action")},
	])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/CharacterMenu"), [
		{"label": "Party Order", "route": &"character"}, {"label": "Character Sheets", "route": &"character"},
		{"label": "Inventory", "route": &"inventory"}, {"label": "Spells", "route": &"spells"}, {"label": "Vault", "route": &"vault"},
	])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/AlliesMenu"), [
		{"label": "Current Allies", "route": &"allies", "disabled_reason": GameShellAvailability.allies_reason(game_view)},
		{"label": "Bestiary", "route": &"bestiary"},
	])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/MapsMenu"), [{"label": "Maps and Notes", "route": &"journal"}, {"label": "Acquired Maps", "route": &"journal"}])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/PreferencesMenu"), [{"label": "Display, Audio, and Access", "route": &"system"}, {"label": "Save, Load, and Package Diagnostics", "route": &"system"}])
	fill(owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/MusicMenu"), [
		{"label": "Now Playing: %s" % (music_title if music_playing else "Nothing"), "disabled_reason": "Current music title"},
		{"label": "Stop Music" if settings.music_enabled else "Play Music", "system": &"music_toggle"},
		{"label": "Playlist…", "system": &"music_playlist"},
	])
	fill(owner.get_node("%CompactMenu"), _compact_entries(game_view, settings, contextual_label, contextual_availability))


static func _compact_entries(game_view: GameView, settings: PresentationSettings, contextual_label: String, contextual_availability: StringName) -> Array[Dictionary]:
	return [
		{"label": "Adventure — Explore", "route": &"exploration"},
		{"label": "Adventure — Search", "command": &"search_mode", "disabled_reason": GameShellAvailability.action_reason(game_view, &"toggle_search")},
		{"label": "Adventure — Area Search", "command": &"area_search", "disabled_reason": GameShellAvailability.action_reason(game_view, &"area_search")},
		{"label": "Adventure — Torch", "command": &"torch", "disabled_reason": GameShellAvailability.action_reason(game_view, &"use_torch")},
		{"label": "Adventure — Camp", "command": &"camp", "disabled_reason": GameShellAvailability.action_reason(game_view, &"camp")},
		{"label": "Adventure — Rest", "command": &"rest", "disabled_reason": GameShellAvailability.action_reason(game_view, &"rest")},
		{"label": "Adventure — Heal", "command": &"heal", "disabled_reason": GameShellAvailability.action_reason(game_view, &"heal")},
		{"label": "Adventure — %s" % contextual_label, "command": &"contextual", "disabled_reason": GameShellAvailability.action_reason(game_view, contextual_availability)},
		{"label": "Adventure — Money", "command": &"money", "disabled_reason": GameShellAvailability.action_reason(game_view, &"money_action")},
		{"label": "Character — Party Order", "route": &"character"}, {"label": "Character — Character Sheets", "route": &"character"},
		{"label": "Character — Inventory", "route": &"inventory"}, {"label": "Character — Spells", "route": &"spells"}, {"label": "Character — Vault", "route": &"vault"},
		{"label": "Allies — Current Allies", "route": &"allies", "disabled_reason": GameShellAvailability.allies_reason(game_view)}, {"label": "Allies — Bestiary", "route": &"bestiary"},
		{"label": "Maps / Notes", "route": &"journal"},
		{"label": "Game — Save & Load…", "route": &"system", "disabled_reason": GameShellAvailability.save_reason(game_view)}, {"label": "Game — Quick Save 1", "system": &"save", "value": "quick", "disabled_reason": GameShellAvailability.save_reason(game_view)}, {"label": "Game — Quick Save 2", "system": &"save", "value": "quick-2", "disabled_reason": GameShellAvailability.save_reason(game_view)},
		{"label": "Game — Quick Load 1", "system": &"load", "value": "quick", "disabled_reason": GameShellAvailability.load_reason(game_view)}, {"label": "Game — Quick Load 2", "system": &"load", "value": "quick-2", "disabled_reason": GameShellAvailability.load_reason(game_view)},
		{"label": "Game — Main Menu", "system": &"end_adventure", "disabled_reason": GameShellAvailability.end_adventure_reason(game_view)},
		{"label": "Game — Campaigns", "system": &"campaigns", "disabled_reason": GameShellAvailability.campaign_library_reason(game_view)},
		{"label": "Preferences", "route": &"system"},
		{"label": "Music — %s" % ("Stop" if settings.music_enabled else "Play"), "system": &"music_toggle"},
		{"label": "Music — Playlist…", "system": &"music_playlist"}, {"label": "Info / Diagnostics", "route": &"system"}, {"label": "Quit", "system": &"quit"},
	]


func fill(menu: MenuButton, entries: Array[Dictionary]) -> void:
	var owner = _owner()
	var popup := menu.get_popup()
	popup.clear()
	var actions: Dictionary = {}
	var enabled_count := 0
	for index: int in entries.size():
		var entry := entries[index]
		popup.add_item(String(entry["label"]), index)
		var reason := String(entry.get("disabled_reason", ""))
		if reason.is_empty() and entry.has("route"):
			reason = GameShellAvailability.route_change_reason(owner._current_view)
		if not reason.is_empty():
			entry["disabled_reason"] = reason
		actions[index] = entry
		if not reason.is_empty():
			popup.set_item_disabled(index, true)
			popup.set_item_tooltip(index, reason)
		else:
			enabled_count += 1
	_actions[menu.get_instance_id()] = actions
	menu.disabled = enabled_count == 0
	if not _connected.has(menu.get_instance_id()):
		popup.id_pressed.connect(_on_item_pressed.bind(menu))
		_connected[menu.get_instance_id()] = true


func _on_item_pressed(item_id: int, menu: MenuButton) -> void:
	var owner = _owner()
	var entry: Dictionary = _actions.get(menu.get_instance_id(), {}).get(item_id, {})
	if entry.is_empty() or not String(entry.get("disabled_reason", "")).is_empty():
		return
	if entry.has("route"):
		owner._navigator.open_screen(StringName(entry["route"]))
	elif entry.has("command"):
		owner._command_controller.activate(StringName(entry["command"]))
	elif entry.has("system"):
		owner.handle_system_action_requested(StringName(entry["system"]), entry.get("value"))


func controller_open() -> bool:
	var menus := _controller_menus()
	if menus.is_empty():
		return false
	var owner = _owner()
	var focused: Control = owner.get_viewport().gui_get_focus_owner() if owner != null else null
	_controller_restore_focus = weakref(focused) if focused != null else null
	_controller_active = true
	_controller_popup_open = false
	_controller_heading = clampi(_controller_heading, 0, menus.size() - 1)
	_controller_item = 0
	_focus_heading(menus[_controller_heading])
	return true


func controller_is_open() -> bool:
	return _controller_active


func controller_direction(direction: Vector2i) -> bool:
	if not _controller_active or direction == Vector2i.ZERO:
		return false
	if direction.x != 0:
		var reopen := _controller_popup_open
		_hide_popup()
		var menus := _controller_menus()
		if menus.is_empty():
			return false
		_controller_heading = wrapi(_controller_heading + direction.x, 0, menus.size())
		_controller_item = 0
		_focus_heading(menus[_controller_heading])
		if reopen:
			_show_popup()
		return true
	if not _controller_popup_open:
		if direction.y > 0:
			_show_popup()
		return true
	var menu := _current_controller_menu()
	if menu == null or menu.get_popup().item_count == 0:
		return true
	_controller_item = wrapi(_controller_item + direction.y, 0, menu.get_popup().item_count)
	menu.get_popup().set_focused_item(_controller_item)
	return true


func controller_confirm() -> bool:
	if not _controller_active:
		return false
	if not _controller_popup_open:
		_show_popup()
		return true
	var menu := _current_controller_menu()
	if menu == null:
		return true
	var entry: Dictionary = _actions.get(menu.get_instance_id(), {}).get(_controller_item, {})
	if entry.is_empty() or not String(entry.get("disabled_reason", "")).is_empty():
		return true
	_hide_popup()
	_controller_active = false
	_on_item_pressed(_controller_item, menu)
	return true


func controller_back() -> bool:
	if not _controller_active:
		return false
	if _controller_popup_open:
		_hide_popup()
		_focus_heading(_current_controller_menu())
		return true
	_controller_active = false
	var restore: Control = _controller_restore_focus.get_ref() if _controller_restore_focus != null else null
	_controller_restore_focus = null
	if restore != null and restore.is_inside_tree() and restore.is_visible_in_tree():
		restore.grab_focus()
	return true


func controller_selected_label() -> String:
	var menu := _current_controller_menu()
	if menu == null:
		return ""
	if not _controller_popup_open:
		return menu.text
	var entry: Dictionary = _actions.get(menu.get_instance_id(), {}).get(_controller_item, {})
	return String(entry.get("label", menu.text))


func _controller_menus() -> Array[MenuButton]:
	var result: Array[MenuButton] = []
	var owner = _owner()
	if owner == null:
		return result
	var compact := owner.get_node("%CompactMenu") as MenuButton
	if compact.visible:
		result.append(compact)
		return result
	var row: Node = owner.get_node("MenuStrip/MenuChromeColumn/MenuSurface/MenuRow")
	for child: Node in row.get_children():
		if child is MenuButton and child.visible:
			result.append(child as MenuButton)
	return result


func _current_controller_menu() -> MenuButton:
	var menus := _controller_menus()
	return menus[clampi(_controller_heading, 0, menus.size() - 1)] if not menus.is_empty() else null


func _focus_heading(menu: MenuButton) -> void:
	if menu == null:
		return
	menu.focus_mode = Control.FOCUS_ALL
	menu.grab_focus()


func _show_popup() -> void:
	var menu := _current_controller_menu()
	if menu == null or menu.disabled or menu.get_popup().item_count == 0:
		return
	_controller_popup_open = true
	_controller_item = clampi(_controller_item, 0, menu.get_popup().item_count - 1)
	menu.show_popup()
	menu.get_popup().set_focused_item(_controller_item)


func _hide_popup() -> void:
	var menu := _current_controller_menu()
	if menu != null:
		menu.get_popup().hide()
	_controller_popup_open = false
