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
var _controller_repeat_allowed: bool = true
var _pointer_open: bool = false
var _pointer_menu: MenuButton
var _native_open_menu: MenuButton
var _pointer_activation_pending: MenuButton
var _switching_pointer_heading: bool = false
var _pointer_close_generation: int = 0


func _init(owner: Control) -> void:
	_owner_ref = weakref(owner)
	var window := owner.get_window()
	if window != null and not window.focus_exited.is_connected(_on_window_focus_exited):
		window.focus_exited.connect(_on_window_focus_exited, CONNECT_DEFERRED)


func _owner():
	return _owner_ref.get_ref()


func rebuild(game_view: GameView, settings: PresentationSettings, music_title: String, music_playing: bool) -> void:
	var owner = _owner()
	if owner == null or not owner.is_node_ready():
		return
	var retained_heading: String = String(_current_controller_menu().name) if _controller_active and _current_controller_menu() != null else ""
	var retained_entry := _controller_selected_identity()
	var contextual_definition: Dictionary = owner._command_controller.presentation_definition(ClassicCommandCatalog.command(&"contextual"))
	var contextual_label := String(contextual_definition.get("label", "Encounter"))
	var contextual_availability := StringName(contextual_definition.get("availability", &"contextual_encounter"))
	var groups := _menu_catalog(game_view, settings, music_title, music_playing, contextual_label, contextual_availability, owner._navigator.content_presenter.system_preferences.active_slot_id)
	var row_path := "MenuStrip/MenuChromeColumn/MenuSurface/MenuRow/"
	for group: Dictionary in groups:
		var menu := owner.get_node(row_path + String(group["node"])) as MenuButton
		menu.text = String(group["heading"])
		fill(menu, group["entries"])
		_bind_pointer_menu(menu)
	var compact_menu := owner.get_node("%CompactMenu") as MenuButton
	fill(compact_menu, _compact_entries(groups))
	_bind_pointer_menu(compact_menu)
	if _controller_active:
		_restore_controller_selection(retained_heading, retained_entry)


static func _menu_catalog(game_view: GameView, settings: PresentationSettings, music_title: String, music_playing: bool, contextual_label: String, contextual_availability: StringName, active_slot_id: String) -> Array[Dictionary]:
	return [
		{"node": "GameMenu", "heading": "Game", "entries": [
			{"label": "Campaigns…", "system": &"campaigns", "disabled_reason": GameShellAvailability.campaign_library_reason(game_view)},
			{"label": "Save & Load…", "route": &"save_load", "disabled_reason": GameShellAvailability.save_reason(game_view)},
			{"label": "Quicksave %s" % active_slot_id, "system": &"save", "value": "quick", "disabled_reason": GameShellAvailability.save_reason(game_view)},
			{"label": "Quickload %s" % active_slot_id, "system": &"load", "value": active_slot_id, "disabled_reason": GameShellAvailability.load_reason(game_view)},
			{"label": "Main Menu…", "system": &"end_adventure", "disabled_reason": GameShellAvailability.end_adventure_reason(game_view)},
			{"label": "Quit", "system": &"quit"},
		]},
		{"node": "AdventureMenu", "heading": "Adventure", "entries": [
			{"label": "Explore", "route": &"exploration"},
			{"label": "Move To", "system": &"click_to_move_toggle", "checkable": true, "checked": settings.click_to_move_enabled},
			{"label": "Search", "command": &"search_mode", "disabled_reason": GameShellAvailability.action_reason(game_view, &"toggle_search")},
			{"label": "Area Search", "command": &"area_search", "disabled_reason": GameShellAvailability.action_reason(game_view, &"area_search")},
			{"label": "Torch", "command": &"torch", "disabled_reason": GameShellAvailability.action_reason(game_view, &"use_torch")},
			{"label": "Camp", "command": &"camp", "disabled_reason": GameShellAvailability.action_reason(game_view, &"camp")},
			{"label": "Rest", "command": &"rest", "disabled_reason": GameShellAvailability.action_reason(game_view, &"rest")},
			{"label": "Heal", "command": &"heal", "disabled_reason": GameShellAvailability.action_reason(game_view, &"heal")},
			{"label": contextual_label, "command": &"contextual", "disabled_reason": GameShellAvailability.action_reason(game_view, contextual_availability)},
			{"label": "Bestiary", "route": &"bestiary"},
			{"label": "Maps and Notes", "route": &"journal"},
			{"label": "Acquired Maps", "route": &"journal"},
		]},
		{"node": "PartyMenu", "heading": "Party", "entries": [
			{"label": "Party Order", "route": &"character"}, {"label": "Character Sheets", "route": &"character"},
			{"label": "Inventory", "route": &"inventory"}, {"label": "Spells", "route": &"spells"},
			{"label": "Vault", "route": &"vault"},
			{"label": "Current Allies", "route": &"allies", "disabled_reason": GameShellAvailability.allies_reason(game_view)},
			{"label": "Money", "command": &"money", "disabled_reason": GameShellAvailability.action_reason(game_view, &"money_action")},
		]},
		{"node": "SettingsMenu", "heading": "Settings", "entries": [
			{"label": "Preferences…", "route": &"system"},
			{"label": "Display…", "route": &"system", "section": &"Display"},
			{"label": "Audio & Pacing…", "route": &"system", "section": &"Audio"},
			{"label": "Accessibility…", "route": &"system", "section": &"Accessibility"},
			{"label": "Controls…", "route": &"system", "section": &"Controls"},
			{"label": "Now Playing: %s" % (music_title if music_playing else "Nothing"), "disabled_reason": "Current music title"},
			{"label": "Stop Music" if settings.music_enabled else "Play Music", "system": &"music_toggle"},
			{"label": "Playlist…", "system": &"music_playlist"},
		]},
		{"node": "HelpMenu", "heading": "Help", "entries": [
			{"label": "About Realmz Rebuilt", "route": &"system", "section": &"Diagnostics"},
			{"label": "Package identity and readiness", "route": &"system", "section": &"Diagnostics"},
			{"label": "Diagnostics", "route": &"system", "section": &"Diagnostics"},
		]},
	]


static func _compact_entries(groups: Array[Dictionary]) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for group: Dictionary in groups:
		for source_entry: Dictionary in group["entries"]:
			var entry := source_entry.duplicate(true)
			entry["label"] = "%s — %s" % [group["heading"], entry["label"]]
			entries.append(entry)
	return entries


func fill(menu: MenuButton, entries: Array) -> void:
	var owner = _owner()
	var popup := menu.get_popup()
	popup.clear()
	# Exclusive embedded windows block the outer compositor's input forwarding.
	popup.exclusive = false
	var actions: Dictionary = {}
	var enabled_count := 0
	for index: int in entries.size():
		var entry: Dictionary = entries[index]
		popup.add_item(String(entry["label"]), index)
		if bool(entry.get("checkable", false)):
			popup.set_item_as_checkable(index, true)
			popup.set_item_checked(index, bool(entry.get("checked", false)))
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


func _bind_pointer_menu(menu: MenuButton) -> void:
	var key := menu.get_instance_id()
	if _connected.has("pointer_%d" % key):
		return
	menu.switch_on_hover = false
	menu.mouse_entered.connect(_on_heading_mouse_entered.bind(menu))
	menu.mouse_exited.connect(_schedule_pointer_close)
	menu.gui_input.connect(_on_menu_gui_input.bind(menu))
	var popup := menu.get_popup()
	popup.about_to_popup.connect(_on_popup_opened.bind(menu))
	popup.popup_hide.connect(_on_popup_hidden.bind(menu))
	popup.mouse_entered.connect(_on_popup_mouse_entered.bind(menu))
	popup.mouse_exited.connect(_schedule_pointer_close)
	popup.focus_exited.connect(_on_window_focus_exited, CONNECT_DEFERRED)
	_connected["pointer_%d" % key] = true


func _on_popup_opened(menu: MenuButton) -> void:
	if _controller_active:
		return
	_native_open_menu = menu
	if _pointer_activation_pending == menu:
		_pointer_activation_pending = null
		_pointer_open = true
		_pointer_menu = menu
		_cancel_pointer_close()


func _on_popup_hidden(menu: MenuButton) -> void:
	if _switching_pointer_heading or _controller_active:
		return
	if _native_open_menu == menu:
		_owner().get_viewport().set_input_as_handled()
		_native_open_menu = null
	if _pointer_menu == menu:
		_close_pointer_menu()


func _on_menu_gui_input(event: InputEvent, menu: MenuButton) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT and mouse_button.pressed:
		_pointer_activation_pending = menu


func _on_popup_mouse_entered(menu: MenuButton) -> void:
	if _controller_active or _native_open_menu != menu:
		return
	_pointer_open = true
	_pointer_menu = menu
	_cancel_pointer_close()


func _on_heading_mouse_entered(menu: MenuButton) -> void:
	if _controller_active:
		return
	if _native_open_menu != null and not _pointer_open:
		_pointer_open = true
		_pointer_menu = _native_open_menu
	_cancel_pointer_close()
	if not _pointer_open or _native_open_menu == menu:
		return
	_switching_pointer_heading = true
	if _native_open_menu != null:
		_native_open_menu.get_popup().hide()
	_pointer_activation_pending = menu
	menu.show_popup()
	_switching_pointer_heading = false


func _cancel_pointer_close() -> void:
	_pointer_close_generation += 1


func _schedule_pointer_close() -> void:
	if not _pointer_open or _controller_active:
		return
	_pointer_close_generation += 1
	_close_pointer_menu_after_grace(_pointer_close_generation)


func _close_pointer_menu_after_grace(generation: int) -> void:
	var owner = _owner()
	if owner == null:
		return
	await owner.get_tree().create_timer(0.15).timeout
	if generation == _pointer_close_generation and _pointer_open and not _controller_active:
		_close_pointer_menu()


func _close_pointer_menu() -> void:
	_pointer_close_generation += 1
	var menu := _native_open_menu if _native_open_menu != null else _pointer_menu
	_native_open_menu = null
	_pointer_menu = null
	_pointer_open = false
	_pointer_activation_pending = null
	if menu != null and is_instance_valid(menu):
		menu.get_popup().hide()


func _on_window_focus_exited() -> void:
	var current_owner = _owner()
	if current_owner != null and current_owner.get_window().has_focus(): return
	if _native_open_menu != null and _native_open_menu.get_popup().has_focus(): return
	_close_pointer_menu()
	if _controller_active:
		var owner = _owner()
		if owner != null and owner.is_inside_tree():
			controller_back()
		else:
			_controller_active = false
			_controller_popup_open = false


func _on_item_pressed(item_id: int, menu: MenuButton) -> void:
	_close_pointer_menu()
	var owner = _owner()
	var entry: Dictionary = _actions.get(menu.get_instance_id(), {}).get(item_id, {})
	if entry.is_empty() or not String(entry.get("disabled_reason", "")).is_empty():
		return
	if entry.has("route"):
		owner._navigator.open_screen(StringName(entry["route"]), true, StringName(entry.get("section", &"Display")) if entry["route"] == &"system" else &"")
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
	_close_pointer_menu()
	_controller_restore_focus = weakref(focused) if focused != null else null
	_controller_active = true
	_controller_popup_open = false
	_controller_heading = clampi(_controller_heading, 0, menus.size() - 1)
	_controller_item = 0
	_controller_repeat_allowed = true
	_hide_native_popups()
	_controller_overlay().close()
	_focus_heading(menus[_controller_heading])
	return true


func controller_is_open() -> bool:
	return _controller_active


## Lets the application input router keep native menu events out of gameplay.
func owns_native_menu_input() -> bool:
	return _native_open_menu != null


## Returns true when a raw host event belongs to either top-menu interaction.
## The host should stop gameplay routing but leave the event available to GUI controls.
func handle_host_input(event: InputEvent) -> bool:
	if _native_open_menu != null:
		if event is InputEventMouseButton and event.pressed:
			var popup := _native_open_menu.get_popup()
			if not Rect2(popup.position, popup.size).has_point(event.position):
				_close_pointer_menu()
				_owner().get_viewport().set_input_as_handled()
		return true
	if not _controller_active:
		return false
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed:
			match key.keycode:
				KEY_ESCAPE: controller_back()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: controller_confirm()
				KEY_LEFT: controller_direction(Vector2i.LEFT, key.echo)
				KEY_RIGHT: controller_direction(Vector2i.RIGHT, key.echo)
				KEY_UP: controller_direction(Vector2i.UP, key.echo)
				KEY_DOWN: controller_direction(Vector2i.DOWN, key.echo)
		else:
			controller_direction(Vector2i.ZERO)
		_owner().get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mouse_button := event as InputEventMouseButton
		var over_heading := _pointer_is_over_heading(mouse_button.position)
		controller_pointer_takeover()
		if not over_heading:
			var owner = _owner()
			if owner != null:
				owner.get_viewport().set_input_as_handled()
	return true


func _pointer_is_over_heading(position: Vector2) -> bool:
	for menu: MenuButton in _controller_menus():
		if menu.get_global_rect().has_point(position):
			return true
	return false


func controller_direction(direction: Vector2i, repeated: bool = false) -> bool:
	if not _controller_active:
		return false
	if direction == Vector2i.ZERO:
		_controller_repeat_allowed = true
		return true
	if repeated and not _controller_repeat_allowed:
		return true
	if direction.x != 0:
		var menus := _controller_menus()
		if menus.is_empty():
			return false
		_controller_heading = clampi(_controller_heading + direction.x, 0, menus.size() - 1) if repeated else wrapi(_controller_heading + direction.x, 0, menus.size())
		_controller_item = 0
		_focus_heading(menus[_controller_heading])
		if _controller_popup_open:
			_present_controller_dropdown()
		_controller_repeat_allowed = false
		return true
	if not _controller_popup_open:
		if direction.y > 0:
			_show_popup()
		return true
	var menu := _current_controller_menu()
	if menu == null or menu.get_popup().item_count == 0:
		return true
	_controller_item = clampi(_controller_item + direction.y, 0, menu.get_popup().item_count - 1)
	_present_controller_dropdown()
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
		_present_controller_dropdown()
		return true
	_hide_popup()
	_controller_active = false
	_controller_restore_focus = null
	_on_item_pressed(_controller_item, menu)
	return true


func controller_back() -> bool:
	if not _controller_active:
		return false
	if _controller_popup_open:
		_hide_popup()
		_focus_heading(_current_controller_menu())
		_controller_repeat_allowed = false
		return true
	_controller_active = false
	_controller_overlay().close()
	var restore: Control = _controller_restore_focus.get_ref() if _controller_restore_focus != null else null
	_controller_restore_focus = null
	if restore != null and restore.is_inside_tree() and restore.is_visible_in_tree():
		restore.grab_focus()
	return true


func controller_pointer_takeover() -> void:
	if not _controller_active:
		return
	_hide_popup()
	_controller_active = false
	_controller_restore_focus = null
	_controller_repeat_allowed = false


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
	if menu == null or menu.get_popup().item_count == 0:
		return
	_controller_popup_open = true
	_controller_item = clampi(_controller_item, 0, menu.get_popup().item_count - 1)
	_controller_repeat_allowed = false
	_present_controller_dropdown()


func _hide_popup() -> void:
	_controller_overlay().close()
	_controller_popup_open = false


func _present_controller_dropdown() -> void:
	var menu := _current_controller_menu()
	if menu == null:
		return
	_controller_overlay().present(menu.text, _controller_entries(menu), _controller_item, menu.get_global_rect())


func _controller_entries(menu: MenuButton) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actions: Dictionary = _actions.get(menu.get_instance_id(), {})
	for index: int in menu.get_popup().item_count:
		var entry: Dictionary = actions.get(index, {}).duplicate(true)
		if bool(entry.get("checkable", false)):
			entry["label"] = "%s  %s" % [entry["label"], "✓" if menu.get_popup().is_item_checked(index) else "○"]
		result.append(entry)
	return result


func _controller_overlay() -> Variant:
	return _owner().get_node("%ControllerTopMenuOverlay")


func _hide_native_popups() -> void:
	for menu: MenuButton in _controller_menus():
		menu.get_popup().hide()


func _controller_selected_identity() -> String:
	var menu := _current_controller_menu()
	if menu == null or not _controller_popup_open:
		return ""
	var entry: Dictionary = _actions.get(menu.get_instance_id(), {}).get(_controller_item, {})
	for key: String in ["route", "command", "system", "value", "label", "section"]:
		if entry.has(key):
			return "%s:%s" % [key, entry[key]]
	return ""


func _restore_controller_selection(heading_name: String, entry_identity: String) -> void:
	var menus := _controller_menus()
	for index: int in menus.size():
		if menus[index].name == heading_name:
			_controller_heading = index
			break
	var menu := _current_controller_menu()
	if menu == null:
		return
	if not entry_identity.is_empty():
		for index: int in menu.get_popup().item_count:
			_controller_item = index
			if _controller_selected_identity() == entry_identity:
				break
	_controller_item = clampi(_controller_item, 0, maxi(0, menu.get_popup().item_count - 1))
	_focus_heading(menu)
	if _controller_popup_open:
		_present_controller_dropdown()
