## Coordinates pause navigation without changing the playthrough or its rules.
class_name GameShellPauseController
extends RefCounted

var _owner_ref: WeakRef
var _view: PauseMenuView
var _active := false
var _workspace := false
var _entering_workspace := false
var _popup: Control
var _page: StringName = &"main"
var _origin: StringName
var _workspace_origin: StringName
var _restore_focus: WeakRef


func _init(owner: GameShell) -> void:
	_owner_ref = weakref(owner)
	_view = owner.get_node("PauseMenu") as PauseMenuView
	_view.action_requested.connect(activate)
	owner.navigator.screen_changed.connect(_on_route_changed)
	owner.music_workspace.visibility_changed.connect(_on_popup_visibility)
	owner.character_art.visibility_changed.connect(_on_popup_visibility)


func _owner() -> GameShell:
	return _owner_ref.get_ref() as GameShell


func is_active() -> bool:
	return _active


func workspace_is_open() -> bool:
	return _active and _workspace


func is_open() -> bool:
	return _active and _view.visible


func allowed() -> bool:
	var owner := _owner()
	if owner == null or not owner.is_visible_in_tree() or owner.navigator.full_stage_overlay_visible: return false
	if owner.menu_input_blocked.is_valid() and bool(owner.menu_input_blocked.call()): return false
	if owner.font_picker.visible or owner.character_art.visible or owner.music_workspace.visible or owner.navigator.draft_dialog.visible or owner.controller.text_editor_is_open() or owner.controller.radial_is_open(): return false
	var request := owner._current_view.active_interaction_request() if owner._current_view != null else null
	return request == null or request.kind == InteractionRequest.COMBAT


func open() -> bool:
	if is_open(): return true
	if not allowed(): return false
	var owner := _owner()
	if owner.navigator.draft_dialog.defer_if_dirty(owner.navigator.content_presenter.system_preferences, open): return true
	if not _active:
		_origin = owner.navigator.current_screen()
		var focused := owner.get_viewport().gui_get_focus_owner()
		_restore_focus = weakref(focused) if focused != null else null
		_active = true
		owner.pause_changed.emit(true)
	_page = &"main"
	_workspace = false
	rebuild()
	return true


func resume() -> void:
	var owner := _owner()
	if not _active: return
	if owner.navigator.draft_dialog.defer_if_dirty(owner.navigator.content_presenter.system_preferences, resume): return
	if _popup != null and _popup.visible: return
	_view.hide()
	_active = false
	_workspace = false
	if owner.navigator.current_screen() != _origin and owner._current_view != null and owner._current_view.session_started:
		owner.navigator.open_screen(_origin, false)
	owner.pause_changed.emit(false)
	var previous := _restore_focus.get_ref() as Control if _restore_focus != null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	_restore_focus = null


func rebuild() -> void:
	if not _active or not _view.visible and _workspace: return
	var owner := _owner()
	var view := owner._current_view
	if view == null or not view.session_started or view.party_setup_available:
		if _active:
			_active = false
			_view.hide()
			owner.pause_changed.emit(false)
		return
	if not _view.visible and (_popup != null and _popup.visible or owner.menu_input_blocked.is_valid() and bool(owner.menu_input_blocked.call())): return
	var slot := owner.navigator.content_presenter.system_preferences.active_slot_id
	var preview := owner.navigator.content_presenter.system_preferences.active_quick_preview
	var reasons := {&"saves": GameShellAvailability.save_reason(view), &"quick_save": GameShellAvailability.save_reason(view), &"quick_load": GameShellAvailability.load_reason(view), &"main_menu": GameShellAvailability.end_adventure_reason(view)}
	if view.combat_view != null and view.combat_view.outcome == &"active":
		reasons[&"saves"] = "Unavailable during battle."
		reasons[&"character_art"] = "Finish the battle before importing artwork."
	if preview == null:
		reasons[&"quick_load"] = "No quicksave in slot %s." % slot
	elif not preview.can_load:
		reasons[&"quick_load"] = preview.error_message
	var context := view.campaign_summary.title if view.campaign_summary != null else "Adventure"
	if view.combat_view != null and view.combat_view.outcome == &"active": context = "Battle in progress"
	_view.present(_page, context, reasons, slot, preview != null)


func poll() -> void:
	if _active and not _view.visible and not _workspace and _popup == null:
		rebuild()


func activate(action: StringName) -> void:
	var owner := _owner()
	match action:
		&"resume": resume()
		&"back": back()
		&"saves", &"settings", &"help":
			_page = action
			rebuild()
		&"display", &"audio", &"accessibility", &"controls":
			_open_workspace(&"system", {&"display": &"Display", &"audio": &"Audio", &"accessibility": &"Accessibility", &"controls": &"Controls"}[action])
		&"about", &"scenario_info", &"diagnostics": _open_workspace(&"system", &"Diagnostics")
		&"manage_saves": _open_workspace(&"save_load")
		&"music", &"character_art":
			_popup = owner.music_workspace if action == &"music" else owner.character_art
			_view.hide()
			owner.handle_system_action_requested(&"music_playlist" if action == &"music" else &"character_art", null)
		&"quick_save": owner.handle_system_action_requested(&"save", "quick")
		&"quick_load":
			_view.hide()
			owner.handle_system_action_requested(&"load", owner.navigator.content_presenter.system_preferences.active_slot_id)
		&"main_menu", &"quit":
			_view.hide()
			owner.handle_system_action_requested(&"end_adventure" if action == &"main_menu" else &"quit", null)


func back() -> bool:
	if not _active: return false
	if _popup != null and _popup.visible: return false
	if _workspace:
		if _owner().navigator.draft_dialog.defer_if_dirty(_owner().navigator.content_presenter.system_preferences, _return_from_workspace): return true
		_return_from_workspace()
	elif _page != &"main":
		_page = &"main"
		rebuild()
	else: resume()
	return true


func move(direction: Vector2i, _repeated: bool = false) -> bool:
	if not is_open(): return false
	_view.move_selection(direction)
	return true


func confirm() -> bool:
	if not is_open(): return false
	_view.activate_selected()
	return true


func selected_label() -> String:
	return _view.selected_label()


func handle_input(event: InputEvent) -> bool:
	if event.is_action_pressed(&"realmz_top_menu") and not event.is_echo() and allowed():
		if _active: resume()
		else: open()
		_owner().get_viewport().set_input_as_handled()
		return true
	if not is_open(): return false
	if event is InputEventKey and event.pressed:
		if event.echo: return true
		match event.keycode:
			KEY_ESCAPE: back()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: confirm()
			KEY_TAB: move(Vector2i.UP if event.shift_pressed else Vector2i.DOWN)
			KEY_UP: move(Vector2i.UP)
			KEY_DOWN: move(Vector2i.DOWN)
		_owner().get_viewport().set_input_as_handled()
	return true


func _open_workspace(route: StringName, section: StringName = &"") -> void:
	_workspace_origin = _owner().navigator.current_screen()
	_workspace = true
	_entering_workspace = true
	_view.hide()
	_owner().navigator.open_screen(route, true, section)
	_entering_workspace = false


func _return_from_workspace() -> void:
	if _owner().navigator.current_screen() != _workspace_origin:
		_owner().navigator.handle_back()
	_workspace = false
	rebuild()


func _on_route_changed(route: StringName) -> void:
	if not _active or _entering_workspace: return
	if _workspace and route == _workspace_origin:
		_workspace = false
		rebuild()
	elif not _view.visible and route == &"save_load":
		_workspace = true
		_workspace_origin = _origin


func _on_popup_visibility() -> void:
	if _active and _popup != null and not _popup.visible:
		_popup = null
		rebuild()
