## Coordinates pause navigation without changing the playthrough or its rules.
class_name GameShellPauseController
extends RefCounted

var _owner_ref: WeakRef
var _view: PauseMenuView
var _active := false
var _workspace := false
var _entering_workspace := false
var _page: StringName = &"main"
var _origin: StringName
var _workspace_origin: StringName
var _restore_focus: WeakRef
var _backdrop: Control
var _navigator_layer: int


func _init(owner: GameShell) -> void:
	_owner_ref = weakref(owner)
	_view = owner.get_node("PauseMenu") as PauseMenuView
	_backdrop = owner.get_node("PauseBackdrop") as Control
	_navigator_layer = owner.navigator.z_index
	_view.action_requested.connect(activate)
	owner.navigator.screen_changed.connect(_on_route_changed)


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
	if owner.font_picker.visible or owner.character_art.visible or owner.music_workspace.visible or owner.navigator.draft_dialog.visible or owner.controller.text.is_open() or owner.controller.radial.is_open(): return false
	var request := owner.current_view.active_interaction_request() if owner.current_view != null else null
	return request == null or request.kind == InteractionRequest.COMBAT


func open() -> bool:
	if is_open(): return true
	if not allowed(): return false
	var owner := _owner()
	owner.controller_prompts.hide_prompts()
	if owner.navigator.draft_dialog.defer_if_dirty(owner.navigator.content_presenter.system_preferences, open): return true
	if not _active:
		_view.reset_selection()
		_origin = owner.navigator.current_screen()
		var focused := owner.get_viewport().gui_get_focus_owner()
		_restore_focus = weakref(focused) if focused != null else null
		_active = true
		_backdrop.show()
		owner.navigator.shared_menu_backdrop = true
		owner.pause_changed.emit(true)
	_page = &"main"
	_workspace = false
	rebuild()
	return true


func resume() -> void:
	var owner := _owner()
	if not _active: return
	if owner.navigator.draft_dialog.defer_if_dirty(owner.navigator.content_presenter.system_preferences, resume): return
	_view.hide()
	_active = false
	_workspace = false
	if owner.navigator.current_screen() != _origin and owner.current_view != null and owner.current_view.session_started:
		owner.navigator.open_screen(_origin, false)
	_backdrop.hide()
	owner.navigator.shared_menu_backdrop = false
	owner.navigator.z_index = _navigator_layer
	owner.pause_changed.emit(false)
	var previous := _restore_focus.get_ref() as Control if _restore_focus != null else null
	if is_instance_valid(previous) and previous.is_visible_in_tree(): previous.grab_focus()
	_restore_focus = null


func rebuild() -> void:
	if not _active or not _view.visible and _workspace: return
	var owner := _owner()
	var view := owner.current_view
	if view == null or not view.session_started or view.party_setup_available:
		if _active:
			_active = false
			_view.hide()
			_backdrop.hide()
			owner.navigator.shared_menu_backdrop = false
			owner.navigator.z_index = _navigator_layer
			owner.pause_changed.emit(false)
		return
	if not _view.visible and owner.menu_input_blocked.is_valid() and bool(owner.menu_input_blocked.call()): return
	var slot := owner.navigator.content_presenter.system_preferences.saves.active_slot_id
	var preview := owner.navigator.content_presenter.system_preferences.saves.active_quick_preview
	var reasons := {&"saves": GameShellAvailability.save_reason(view), &"quick_save": GameShellAvailability.save_reason(view), &"quick_load": GameShellAvailability.load_reason(view), &"main_menu": GameShellAvailability.end_adventure_reason(view)}
	if view.combat_view != null and view.combat_view.outcome == &"active":
		reasons[&"saves"] = "Unavailable during battle."
	if preview == null:
		reasons[&"quick_load"] = "No quicksave in slot %s." % slot
	elif not preview.can_load:
		reasons[&"quick_load"] = preview.error_message
	var context := view.campaign_summary.title if view.campaign_summary != null else "Adventure"
	if view.combat_view != null and view.combat_view.outcome == &"active": context = "Battle in progress"
	_view.present(_page, context, reasons, slot, preview != null, _detail_text())


func _detail_text() -> String:
	if _page == &"about":
		return "Realmz Rebuilt %s\n\nPlay Classic Realmz adventures on modern computers.\n\nOriginal Rebuilt code: GPL-3.0-or-later.\nRealmz-derived content: CC BY-NC-SA 4.0.\nThird-party components retain their own licenses." % ProjectSettings.get_setting("application/config/version", "")
	if _page != &"scenario_info": return ""
	var summary := _owner().current_view.campaign_summary
	if summary == null: return "Scenario details are unavailable."
	var parts: PackedStringArray = [summary.title]
	if not summary.version.is_empty(): parts.append("Version %s" % summary.version)
	if not summary.author.is_empty(): parts.append("By %s" % summary.author)
	for value: String in [summary.description, summary.restriction_description]:
		if not value.is_empty(): parts.append(value)
	var limits: PackedStringArray = ["Up to %d characters" % summary.maximum_party_size]
	if summary.maximum_level > 0: limits.append("Maximum character level: %d" % summary.maximum_level)
	if not summary.banned_races.is_empty(): limits.append("Excluded races: %s" % ", ".join(summary.banned_race_names if not summary.banned_race_names.is_empty() else summary.banned_races))
	if not summary.banned_castes.is_empty(): limits.append("Excluded castes: %s" % ", ".join(summary.banned_caste_names if not summary.banned_caste_names.is_empty() else summary.banned_castes))
	parts.append("Party restrictions\n%s" % "\n".join(limits))
	if summary.recommended_party_levels > 0: parts.append("Recommended party total levels: %d" % summary.recommended_party_levels)
	if not summary.compatibility_warning_summaries.is_empty(): parts.append("Import notes\n%s" % "\n".join(summary.compatibility_warning_summaries))
	parts.append("Campaign identity\n%s" % summary.campaign_id)
	parts.append("Package revision\n%s" % summary.package_hash)
	return "\n\n".join(parts)


func poll() -> void:
	if _active and not _view.visible and not _workspace:
		rebuild()


func activate(action: StringName) -> void:
	var owner := _owner()
	match action:
		&"resume": resume()
		&"back": back()
		&"saves", &"help", &"about", &"scenario_info":
			_page = action
			rebuild()
		&"settings":
			_page = &"main"
			_open_workspace(&"system", &"Display")
		&"interface": _open_workspace(&"system", &"Interface")
		&"diagnostics": _open_workspace(&"system", &"Diagnostics")
		&"manage_saves": _open_workspace(&"save_load")
		&"quick_save": owner.handle_system_action_requested(&"save", "quick")
		&"quick_load":
			_view.hide()
			owner.handle_system_action_requested(&"load", owner.navigator.content_presenter.system_preferences.saves.active_slot_id)
		&"main_menu", &"quit":
			_view.hide()
			owner.handle_system_action_requested(&"end_adventure" if action == &"main_menu" else &"quit", null)


func back() -> bool:
	if not _active: return false
	if _owner().navigator.content_presenter.system_preferences.close_local_picker(): return true
	if _workspace:
		if _owner().navigator.draft_dialog.defer_if_dirty(_owner().navigator.content_presenter.system_preferences, _return_from_workspace): return true
		_return_from_workspace()
	elif _page != &"main":
		_page = &"help" if _page in [&"about", &"scenario_info"] else &"main"
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


func set_controller_prompts(family: String) -> void:
	_view.set_controller_prompts(family, _owner().settings.controller)


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
	_owner().navigator.z_index = 100
	_entering_workspace = true
	_view.hide()
	_owner().navigator.open_screen(route, true, section)
	_entering_workspace = false


func _return_from_workspace() -> void:
	_owner().navigator.z_index = _navigator_layer
	if _owner().navigator.current_screen() != _workspace_origin:
		_owner().navigator.handle_back()
	_workspace = false
	rebuild()


func _on_route_changed(route: StringName) -> void:
	if not _active or _entering_workspace: return
	if _workspace and route == _workspace_origin:
		_owner().navigator.z_index = _navigator_layer
		_workspace = false
		rebuild()
	elif not _view.visible and route == &"save_load":
		_owner().navigator.z_index = 100
		_workspace = true
		_workspace_origin = _origin
