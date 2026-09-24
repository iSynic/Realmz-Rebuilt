## Coordinates application input router within application startup and host integration.

class_name ApplicationInputRouter
extends RefCounted

## Translates host input into application routes, interaction responses, and typed game intents.

var _application: Variant
var _focus := ControllerFocusNavigator.new()
var _controller_directions: Dictionary = {}


func _init(application: Variant) -> void:
	_application = application


func handle_input(event: InputEvent) -> void:
	if _application._shell_presenter.controller.handle_navigation_modal_input(event):
		return
	if _application._shell_presenter.controller.handle_top_menu_input(event):
		return
	if _handle_debug_or_acknowledgement_input(event):
		return
	var focus: Control = _application.get_viewport().gui_get_focus_owner()
	if event is InputEventKey and (focus is LineEdit or focus is TextEdit):
		return
	var released_direction := UiInputActions.released_movement_direction(event)
	if released_direction != Vector2i.ZERO and _application._held_movement != null:
		if not (_application._dungeon_presenter.is_active() and _application._dungeon_presenter.handle_keyboard_release(released_direction)) and _application._held_movement.active_direction() == released_direction:
			_application._held_movement.stop(&"keyboard")
	var key_event := event as InputEventKey
	if _handle_playback_or_combat_modifier_input(event, key_event):
		return
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if _handle_combat_inspection_input(event, combat_pending):
		return
	if _application.click_to_move != null and _application.click_to_move.handle_input(event):
		_mark_handled()
		return
	var mouse_button := event as InputEventMouseButton
	if mouse_button != null and mouse_button.button_index == MOUSE_BUTTON_LEFT and not mouse_button.pressed:
		_application._shell_presenter.commands.release()
	if not event.is_pressed():
		return
	if combat_pending and _application._battlefield_presenter.interaction.dismiss_reveal_friends():
		_mark_handled()
		return
	if _handle_back_input(event, combat_pending):
		return
	if _application.lifecycle_host.has_active_interaction():
		return
	if _handle_classic_keyboard_input(key_event, pending):
		_mark_handled()
		return
	if pending != null:
		_handle_pending_interaction_input(event, key_event, pending)
		return
	if _application.accepts_route_input() and _application._shell_presenter.handle_route_shortcut(event):
		_mark_handled()
		return
	if _application.accepts_exploration_input():
		_handle_exploration_input(event, key_event)


func handle_controller_action(action_id: StringName, pressed: bool, repeated: bool = false) -> void:
	if _application._shell_presenter.controller.handle_navigation_modal_controller(action_id, pressed, _controller_direction(action_id)):
		_mark_handled()
		return
	if not pressed and action_id == &"realmz_controller_confirm":
		_application._shell_presenter.controller.release_controller_hold()
	var direction_action := _controller_direction(action_id)
	if _update_controller_direction(action_id, direction_action, pressed):
		return
	if _application.presentation_coordinator != null and _application.presentation_coordinator.is_combat_playback_active():
		if action_id == &"realmz_controller_back":
			if _application.click_to_move != null: _application.click_to_move.cancel("Move To cancelled.")
			_application.abort_full_party_auto(true)
		_mark_handled()
		return
	if _handle_controller_overlay(action_id):
		return
	if _application.lifecycle_host.has_active_interaction() and action_id in [
		&"realmz_controller_action_radial",
		&"realmz_controller_workspace_radial",
		&"realmz_controller_top_menu",
		&"realmz_controller_character_previous",
		&"realmz_controller_character_next",
		&"realmz_controller_system",
	]:
		_mark_handled()
		return
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	var routed_direction := _combined_controller_direction() if direction_action != Vector2i.ZERO else Vector2i.ZERO
	if combat_pending and _handle_controller_combat(action_id, routed_direction, _controller_scroll_direction(action_id), repeated):
		_mark_handled()
		return
	if not combat_pending and _application.click_to_move != null and _application.click_to_move.handle_controller(action_id, routed_direction):
		_mark_handled()
		return
	if _handle_controller_navigation_action(action_id):
		return
	_handle_controller_direction(routed_direction, repeated)


func handle_controller_direction(direction: Vector2i, repeated: bool = false) -> void:
	if _application._shell_presenter.controller.handle_navigation_modal_controller(&"", true, direction):
		_mark_handled()
		return
	if _top_menu_is_open():
		_application._shell_presenter.controller.move_top_menu(direction, repeated)
		_mark_handled()
		return
	if direction == Vector2i.ZERO:
		_stop_controller_movement()
		return
	if _application.presentation_coordinator != null and _application.presentation_coordinator.is_combat_playback_active():
		return
	if _application._shell_presenter.controller.text_editor_is_open():
		_application._shell_presenter.controller.move_text_editor(direction)
		_mark_handled()
		return
	if _application._shell_presenter.controller.radial_is_open():
		_application._shell_presenter.controller.move_radial(direction)
		_mark_handled()
		return
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	if pending != null and pending.kind == InteractionRequest.COMBAT and _handle_controller_combat(&"", direction, Vector2i.ZERO, repeated):
		_mark_handled()
		return
	if _application.click_to_move != null and _application.click_to_move.handle_controller(&"", direction):
		_mark_handled()
		return
	_handle_controller_direction(direction, repeated)


func _handle_controller_navigation_action(action_id: StringName) -> bool:
	var interaction_blocking: bool = _application._interaction_presenter.has_blocking_request()
	if _top_menu_is_open():
		_handle_top_menu_action(action_id)
		return true
	if _music_playlist_owns_controller() and action_id not in [
		&"realmz_controller_back",
		&"realmz_controller_confirm",
		&"realmz_controller_up",
		&"realmz_controller_down",
		&"realmz_controller_left",
		&"realmz_controller_right",
		&"realmz_controller_scroll_up",
		&"realmz_controller_scroll_down",
		&"realmz_controller_scroll_left",
		&"realmz_controller_scroll_right",
	]:
		_mark_handled()
		return true
	if _handle_radial_or_top_menu_action(action_id, interaction_blocking):
		return true
	if _handle_back_or_confirm_action(action_id):
		return true
	if action_id == &"realmz_controller_system" and _application.accepts_route_input():
		_application._shell_presenter.open_system_workspace()
		_mark_handled()
		return true
	if action_id == &"realmz_controller_section_previous" or action_id == &"realmz_controller_section_next":
		var delta := -1 if action_id == &"realmz_controller_section_previous" else 1
		if not _application._shell_presenter.controller.cycle_section(delta):
			_focus.focus_next(_controller_focus_root(), delta < 0)
		_mark_handled()
		return true
	if action_id == &"realmz_controller_character_previous" or action_id == &"realmz_controller_character_next":
		if _application._shell_presenter.controller.select_relative_character(-1 if action_id == &"realmz_controller_character_previous" else 1):
			_mark_handled()
		return true
	if action_id == &"realmz_controller_inspect":
		_application._shell_presenter.controller.show_detail(_focus.inspection_text(_controller_focus_root()))
		_mark_handled()
		return true
	var scroll_direction := _controller_scroll_direction(action_id)
	if scroll_direction != Vector2i.ZERO:
		if _focus.scroll_active(_controller_focus_root(), scroll_direction):
			_mark_handled()
		return true
	return false


func _handle_top_menu_action(action_id: StringName) -> void:
	if action_id == &"realmz_controller_confirm":
		_application._shell_presenter.controller.confirm_top_menu()
	elif action_id == &"realmz_controller_back" or action_id == &"realmz_controller_top_menu":
		_application._shell_presenter.controller.back_top_menu()
	else:
		var menu_direction := _controller_direction(action_id)
		if menu_direction != Vector2i.ZERO:
			_application._shell_presenter.controller.move_top_menu(menu_direction, false)
	_mark_handled()


func _handle_radial_or_top_menu_action(action_id: StringName, interaction_blocking: bool) -> bool:
	if action_id == &"realmz_controller_action_radial":
		_stop_controller_movement()
		if interaction_blocking:
			var interaction_controls: Variant = _application._interaction_presenter.controller
			_application._shell_presenter.controller.open_interaction_radial(interaction_controls.actions(), func(command_id: StringName) -> bool: return interaction_controls.activate_action(command_id))
			_mark_handled()
			return true
		if _application._shell_presenter.controller.open_action_radial():
			_mark_handled()
		return true
	if action_id == &"realmz_controller_workspace_radial":
		_stop_controller_movement()
		if interaction_blocking:
			_mark_handled()
			return true
		if _application._shell_presenter.controller.open_workspace_radial():
			_mark_handled()
		return true
	if action_id != &"realmz_controller_top_menu":
		return false
	_stop_controller_movement()
	if not interaction_blocking and _application.accepts_route_input():
		_application._shell_presenter.controller.open_top_menu()
		_mark_handled()
	return true


func _handle_back_or_confirm_action(action_id: StringName) -> bool:
	if action_id == &"realmz_controller_back":
		_stop_controller_movement()
		if _focus.cancel_active_popup():
			_mark_handled()
			return true
		var back := InputEventAction.new()
		back.action = &"realmz_back"
		back.pressed = true
		handle_input(back)
		return true
	if action_id != &"realmz_controller_confirm":
		return false
	if _application._interaction_presenter.controller.submit_acknowledgement():
		_mark_handled()
		return true
	if _application._shell_presenter.controller.open_text_editor():
		_mark_handled()
		return true
	if _focus.activate_focused(_controller_focus_root()):
		_mark_handled()
	return true


func _handle_controller_direction(direction: Vector2i, repeated: bool) -> void:
	if direction != Vector2i.ZERO and not _application.accepts_exploration_input():
		_focus.move(_controller_focus_root(), direction)
		_mark_handled()
		return
	if direction != Vector2i.ZERO and _application.accepts_exploration_input():
		if _application._dungeon_presenter.is_active():
			if not repeated:
				_application._dungeon_presenter.handle_keyboard_press(direction)
		else:
			if _application._held_movement.active_source() == &"controller":
				_application._held_movement.update(&"controller", direction)
			else:
				_application._held_movement.start(&"controller", direction)
		_mark_handled()


func _update_controller_direction(action_id: StringName, direction: Vector2i, pressed: bool) -> bool:
	if pressed:
		if direction != Vector2i.ZERO:
			_controller_directions[action_id] = direction
		return false
	if direction == Vector2i.ZERO:
		return true
	_controller_directions.erase(action_id)
	if _application._held_movement != null:
		_application._held_movement.stop(&"controller")
	var remaining := _combined_controller_direction()
	if remaining != Vector2i.ZERO and _application.accepts_exploration_input() and not _application._dungeon_presenter.is_active() and not _application._shell_presenter.controller.radial_is_open() and not (_application.click_to_move != null and _application.click_to_move.is_selecting_destination()):
		_application._held_movement.start(&"controller", remaining)
	return true


func clear_controller_state() -> void:
	_controller_directions.clear()
	_stop_controller_movement()


func _handle_controller_overlay(action_id: StringName) -> bool:
	if _application._shell_presenter.controller.text_editor_is_open():
		return _handle_controller_text_editor(action_id)
	if not _application._shell_presenter.controller.radial_is_open():
		return false
	return _handle_controller_radial(action_id)


func _handle_controller_text_editor(action_id: StringName) -> bool:
	if action_id == &"realmz_controller_confirm":
		_application._shell_presenter.controller.confirm_text_editor()
	elif action_id == &"realmz_controller_back":
		_application._shell_presenter.controller.cancel_text_editor()
	elif action_id == &"realmz_controller_section_previous":
		_application._shell_presenter.controller.page_text_editor(-1)
	elif action_id == &"realmz_controller_section_next":
		_application._shell_presenter.controller.page_text_editor(1)
	elif action_id in [&"realmz_controller_action_radial", &"realmz_controller_workspace_radial", &"realmz_controller_character_previous", &"realmz_controller_character_next"]:
		_application._shell_presenter.controller.edit_text(action_id)
	else:
		var direction := _controller_direction(action_id)
		if direction != Vector2i.ZERO:
			_application._shell_presenter.controller.move_text_editor(direction)
	_mark_handled()
	return true


func _handle_controller_radial(action_id: StringName) -> bool:
	if action_id == &"realmz_controller_confirm":
		_application._shell_presenter.controller.confirm_radial()
	elif action_id == &"realmz_controller_back":
		_application._shell_presenter.controller.cancel_radial()
	elif action_id == &"realmz_controller_section_previous":
		_application._shell_presenter.controller.page_radial(-1)
	elif action_id == &"realmz_controller_section_next":
		_application._shell_presenter.controller.page_radial(1)
	else:
		var scroll_direction := _controller_scroll_direction(action_id)
		if scroll_direction != Vector2i.ZERO:
			_application._shell_presenter.controller.scroll_radial(scroll_direction)
			_mark_handled()
			return true
		var direction := _controller_direction(action_id)
		if direction != Vector2i.ZERO:
			_application._shell_presenter.controller.move_radial(direction)
	_mark_handled()
	return true


func _handle_controller_combat(action_id: StringName, direction: Vector2i, scroll_direction: Vector2i, repeated: bool) -> bool:
	var inspector: CombatInspectionCard = _application._interaction_presenter.combat.inspector
	if inspector != null and inspector.handle_controller(action_id, direction, scroll_direction):
		return true
	if _application.click_to_move != null and _application.click_to_move.handle_controller(action_id, direction):
		return true
	var battlefield: BattlefieldInteractionController = _application._battlefield_presenter.interaction
	if scroll_direction != Vector2i.ZERO:
		return _application._battlefield_presenter.controller_pan(scroll_direction)
	if action_id == &"realmz_controller_back":
		if _application.abort_full_party_auto(false):
			return true
		return battlefield.cancel_targeting() or battlefield.cancel_movement_preview()
	if battlefield.targeting != null:
		if direction != Vector2i.ZERO:
			if battlefield.targeting.mode in [&"combatant", &"sequence"]:
				battlefield.cycle_target_candidate(direction.x if direction.x != 0 else direction.y)
			else:
				battlefield.move_target_preview(direction)
			return true
		if action_id == &"realmz_controller_confirm":
			battlefield.select_target_preview()
			return true
		if action_id == &"realmz_controller_action_radial":
			battlefield.confirm_targeting()
			return true
		if action_id == &"realmz_controller_workspace_radial":
			battlefield.rotate_targeting()
			return true
		if action_id == &"realmz_controller_section_previous":
			battlefield.cycle_target_candidate(-1)
			return true
		if action_id == &"realmz_controller_section_next":
			battlefield.cycle_target_candidate(1)
			return true
		if action_id == &"realmz_controller_inspect":
			battlefield.controller.inspect_target_preview()
			return true
		return true
	if action_id == &"realmz_controller_confirm" and battlefield.controller.has_movement_preview():
		return battlefield.confirm_movement_preview()
	if action_id == &"realmz_controller_inspect":
		return battlefield.controller.inspect_focused_combatant()
	if direction != Vector2i.ZERO and not repeated and _application._interaction_presenter.combat.accepts_spatial_input():
		battlefield.preview_movement_direction(direction)
		return true
	return false


func _combined_controller_direction() -> Vector2i:
	var result := Vector2i.ZERO
	for direction: Vector2i in _controller_directions.values():
		result += direction
	return Vector2i(clampi(result.x, -1, 1), clampi(result.y, -1, 1))


func _stop_controller_movement() -> void:
	if _application._held_movement != null:
		_application._held_movement.stop(&"controller")


func _controller_focus_root() -> Control:
	var music_root: Control = _application._shell_presenter.controller.music_playlist_focus_root()
	if music_root != null:
		return music_root
	return _application._interaction_presenter.controller.focus_root() if _application._interaction_presenter != null and _application._interaction_presenter.has_blocking_request() else _application


func _music_playlist_owns_controller() -> bool:
	return _application._shell_presenter.controller.music_playlist_focus_root() != null


func _top_menu_is_open() -> bool:
	var access: Variant = _application._shell_presenter.controller
	return access.has_method("top_menu_is_open") and access.top_menu_is_open()


func _controller_direction(action_id: StringName) -> Vector2i:
	match action_id:
		&"realmz_controller_up": return Vector2i.UP
		&"realmz_controller_down": return Vector2i.DOWN
		&"realmz_controller_left": return Vector2i.LEFT
		&"realmz_controller_right": return Vector2i.RIGHT
	return Vector2i.ZERO


func _controller_scroll_direction(action_id: StringName) -> Vector2i:
	match action_id:
		&"realmz_controller_scroll_up": return Vector2i.UP
		&"realmz_controller_scroll_down": return Vector2i.DOWN
		&"realmz_controller_scroll_left": return Vector2i.LEFT
		&"realmz_controller_scroll_right": return Vector2i.RIGHT
	return Vector2i.ZERO


func _handle_debug_or_acknowledgement_input(event: InputEvent) -> bool:
	if _application.debug_tools != null and _application.debug_tools.handle_input(event):
		_mark_handled()
		return true
	if _application.debug_tools != null and _application.debug_tools.is_open():
		return true
	if _application._interaction_presenter != null and _application._interaction_presenter.handle_global_pointer_acknowledgement(event):
		_mark_handled()
		return true
	return false


func _handle_playback_or_combat_modifier_input(event: InputEvent, key_event: InputEventKey) -> bool:
	if _application.presentation_coordinator != null and _application.presentation_coordinator.is_combat_playback_active():
		if key_event != null and key_event.pressed and key_event.keycode == KEY_ESCAPE and _application.click_to_move != null:
			_application.click_to_move.cancel("Move To cancelled.")
		if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE and _application.abort_full_party_auto(true):
			_mark_handled()
		elif key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			_application.presentation_coordinator.skip_combat_playback()
			_mark_handled()
		return true
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if combat_pending and key_event != null and not key_event.echo and (key_event.keycode == KEY_ALT or key_event.physical_keycode == KEY_ALT):
		var dock_available: bool = _application._interaction_presenter.combat.set_fast_spell_dock_held(key_event.pressed)
		if dock_available or not key_event.pressed:
			_mark_handled()
		return true
	if combat_pending and key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_ESCAPE and _application.abort_full_party_auto(false):
		_mark_handled()
		return true
	return false


func _handle_combat_inspection_input(event: InputEvent, combat_pending: bool) -> bool:
	var inspector: CombatInspectionCard = _application._interaction_presenter.combat.inspector
	if combat_pending and inspector != null and inspector.handle_input(event):
		_mark_handled()
		return true
	if combat_pending and event.is_action_pressed(&"realmz_inspect_movement"):
		_application._battlefield_presenter.interaction.set_movement_costs_visible(true)
		_mark_handled()
		return true
	if combat_pending and event.is_action_released(&"realmz_inspect_movement"):
		_application._battlefield_presenter.interaction.set_movement_costs_visible(false)
		_mark_handled()
		return true
	return false


func _handle_back_input(event: InputEvent, combat_pending: bool) -> bool:
	if not event.is_action_pressed(&"realmz_back"):
		return false
	if combat_pending and _application._battlefield_presenter.interaction.cancel_targeting():
		_mark_handled()
		return true
	if _application._interaction_presenter.handle_back_request():
		_mark_handled()
		return true
	if _application._interaction_presenter.has_blocking_request():
		_application._shell_presenter.status.set_status("Choose a response before leaving this interaction.")
		_mark_handled()
		return true
	if _application._interaction_presenter.dismiss_passive_text() or _application._shell_presenter.handle_back():
		_mark_handled()
		return true
	return false


func _handle_pending_interaction_input(event: InputEvent, key_event: InputEventKey, pending: InteractionRequest) -> void:
	if pending.kind != InteractionRequest.COMBAT:
		return
	if _application._battlefield_presenter.interaction.targeting != null and event.is_action_pressed(&"realmz_target") and _application._battlefield_presenter.interaction.target_with_keyboard():
		_mark_handled()
		return
	if _application._battlefield_presenter.interaction.targeting != null and event.is_action_pressed(&"realmz_confirm_target") and _application._battlefield_presenter.interaction.confirm_targeting():
		_mark_handled()
		return
	var combat_fast_spell := UiInputActions.fast_spell_slot(event, true)
	var use_fast_spell := UiInputActions.combat_fast_spell_use_requested(event)
	if combat_fast_spell >= 0 and (_application._interaction_presenter.combat.activate_fast_spell_from_dock(combat_fast_spell) if use_fast_spell and key_event.alt_pressed else _application._interaction_presenter.combat.handle_fast_spell(combat_fast_spell, use_fast_spell)):
		_mark_handled()
		return
	var combat_direction := UiInputActions.movement_direction(event)
	if combat_direction != Vector2i.ZERO and _application._interaction_presenter.combat.accepts_spatial_input() and _application._battlefield_presenter.interaction.submit_movement_direction(combat_direction):
		_mark_handled()


func _handle_exploration_input(event: InputEvent, key_event: InputEventKey) -> void:
	if key_event != null and key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE and _application.presentation_coordinator.toggle_dungeon_view():
		_mark_handled()
		return
	var fast_spell_slot := UiInputActions.fast_spell_slot(event)
	if fast_spell_slot >= 0:
		_application.handle_field_fast_spell(fast_spell_slot, UiInputActions.fast_spell_use_requested(event))
		_mark_handled()
		return
	if event.is_action_pressed(&"realmz_search"):
		_application.submit_intent(ExplorationIntents.toggle_search())
		_mark_handled()
		return
	if event.is_action_pressed(&"realmz_camp"):
		_application.submit_intent(ExplorationIntents.camp())
		_mark_handled()
		return
	if event.is_action_pressed(&"realmz_rest"):
		_application.submit_intent(ExplorationIntents.rest())
		_mark_handled()
		return
	if event.is_action_pressed(&"realmz_heal"):
		_application.submit_intent(ExplorationIntents.heal())
		_mark_handled()
		return
	var direction := UiInputActions.movement_direction(event)
	if direction != Vector2i.ZERO:
		if not event is InputEventKey or not (event as InputEventKey).echo:
			if _application._dungeon_presenter.is_active():
				_application._dungeon_presenter.handle_keyboard_press(direction)
			else:
				_application._held_movement.start(&"keyboard", direction)
		_mark_handled()


func _mark_handled() -> void:
	_application.get_viewport().set_input_as_handled()


func _handle_classic_keyboard_input(event: InputEventKey, pending: InteractionRequest) -> bool:
	var shell: GameShell = _application._shell_presenter
	if event == null or not shell.settings.classic_keyboard_shortcuts or shell.controller.radial_is_open():
		return false
	var root: Control = _controller_focus_root()
	if _music_playlist_owns_controller(): return false
	if ClassicKeyboardShortcuts.visible_button(shell, &"cast") != null and _application._battlefield_presenter.interaction.targeting == null:
		var action := ClassicKeyboardShortcuts.action(event, "spells")
		if not action.is_empty():
			if not event.echo:
				if action == &"abort":
					if pending != null and pending.kind == InteractionRequest.COMBAT: _application._interaction_presenter.combat.close_spellbook()
					else: shell.handle_back()
				else: ClassicKeyboardShortcuts.activate_visible(shell, action)
			return true
	if pending != null and pending.kind == InteractionRequest.COMBAT and shell.navigator.current_screen() == &"combat":
		if _application._battlefield_presenter.interaction.targeting != null: return false
		if not _application._interaction_presenter.combat.accepts_spatial_input(): return false
		var action := ClassicKeyboardShortcuts.action(event, "combat")
		if action == &"weapon":
			action = &"fire_weapon" if (pending.body as CombatRequestBody).weapon_mode == &"melee" else &"attack"
		if action.is_empty(): return false
		if not event.echo:
			if action == &"center_pointer": _application._battlefield_presenter.controller_pan(Vector2i.ZERO, true)
			else: _application._interaction_presenter.controller.activate_action(action)
		return true
	if root != null and ClassicKeyboardShortcuts.visible_button(root, &"equip") != null:
		var action := ClassicKeyboardShortcuts.action(event, "inventory")
		if not action.is_empty():
			if not event.echo: ClassicKeyboardShortcuts.activate_visible(root, action)
			return true
	if pending != null:
		if pending.kind != InteractionRequest.SHOP: return false
		var action := ClassicKeyboardShortcuts.action(event, "shop")
		if action.is_empty(): return false
		if not event.echo: ClassicKeyboardShortcuts.activate_visible(root, action)
		return true
	if not _application.accepts_exploration_input(): return false
	var action := ClassicKeyboardShortcuts.action(event, "exploration")
	if action.is_empty():
		return not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D]
	if event.echo: return true
	_application._held_movement.stop()
	if action == &"trade":
		shell.navigator.open_screen(&"inventory")
		ClassicKeyboardShortcuts.activate_visible.call_deferred(shell.navigator, &"trade")
	elif action in [&"scrolls", &"make_scroll"]:
		shell.navigator.open_screen(&"spells", true, &"Scrolls" if action == &"scrolls" else &"Known")
	else:
		if action in [&"service", &"encounter"]:
			if (shell.commands.contextual_service() != null) != (action == &"service"): return true
			action = &"contextual"
		for entry: ControllerRadialEntry in shell.commands.controller_entries():
			if entry.id == action and entry.enabled:
				shell.commands.activate(action)
				break
	return true
