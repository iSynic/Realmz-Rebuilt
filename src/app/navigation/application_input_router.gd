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
	if _handle_debug_or_acknowledgement_input(event):
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
	if pending != null:
		_handle_pending_interaction_input(event, key_event, pending)
		return
	if _application.accepts_route_input() and _application._shell_presenter.handle_route_shortcut(event):
		_mark_handled()
		return
	if _application.accepts_exploration_input():
		_handle_exploration_input(event, key_event)


func handle_controller_action(action_id: StringName, pressed: bool, repeated: bool = false) -> void:
	var direction_action := _controller_direction(action_id)
	if not pressed:
		if direction_action != Vector2i.ZERO:
			_controller_directions.erase(action_id)
			if _application._held_movement != null:
				_application._held_movement.stop(&"controller")
			var remaining := _combined_controller_direction()
			if remaining != Vector2i.ZERO and _application.accepts_exploration_input() and not _application._dungeon_presenter.is_active() and not _application._shell_presenter.controller_radial_is_open():
				_application._held_movement.start(&"controller", remaining)
		return
	if direction_action != Vector2i.ZERO:
		_controller_directions[action_id] = direction_action
	if _application.presentation_coordinator != null and _application.presentation_coordinator.is_combat_playback_active():
		if action_id == &"realmz_controller_back":
			_application.abort_full_party_auto(true)
		_mark_handled()
		return
	if _application._shell_presenter.controller_text_editor_is_open():
		if action_id == &"realmz_controller_confirm":
			_application._shell_presenter.confirm_controller_text_editor()
		elif action_id == &"realmz_controller_back":
			_application._shell_presenter.cancel_controller_text_editor()
		elif action_id == &"realmz_controller_section_previous":
			_application._shell_presenter.page_controller_text_editor(-1)
		elif action_id == &"realmz_controller_section_next":
			_application._shell_presenter.page_controller_text_editor(1)
		elif action_id in [&"realmz_controller_action_radial", &"realmz_controller_workspace_radial", &"realmz_controller_character_previous", &"realmz_controller_character_next"]:
			_application._shell_presenter.edit_controller_text(action_id)
		else:
			var text_direction := _controller_direction(action_id)
			if text_direction != Vector2i.ZERO:
				_application._shell_presenter.move_controller_text_editor(text_direction)
		_mark_handled()
		return
	if _application._shell_presenter.controller_radial_is_open():
		if action_id == &"realmz_controller_confirm":
			_application._shell_presenter.confirm_controller_radial()
		elif action_id == &"realmz_controller_back":
			_application._shell_presenter.cancel_controller_radial()
		elif action_id == &"realmz_controller_section_previous":
			_application._shell_presenter.page_controller_radial(-1)
		elif action_id == &"realmz_controller_section_next":
			_application._shell_presenter.page_controller_radial(1)
		else:
			var radial_direction := _controller_direction(action_id)
			if radial_direction != Vector2i.ZERO:
				_application._shell_presenter.move_controller_radial(radial_direction)
		_mark_handled()
		return
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if combat_pending and _handle_controller_combat(action_id, direction_action, _controller_scroll_direction(action_id), repeated):
		_mark_handled()
		return
	if action_id == &"realmz_controller_action_radial":
		_stop_controller_movement()
		if pending != null and _application._shell_presenter.open_controller_interaction_radial(_application._interaction_presenter.controller_actions(), _application._interaction_presenter.activate_controller_action):
			_mark_handled()
			return
		if _application._shell_presenter.open_controller_action_radial():
			_mark_handled()
		return
	if action_id == &"realmz_controller_workspace_radial":
		_stop_controller_movement()
		if _application._shell_presenter.open_controller_workspace_radial():
			_mark_handled()
		return
	if action_id == &"realmz_controller_back":
		_stop_controller_movement()
		var back := InputEventAction.new()
		back.action = &"realmz_back"
		back.pressed = true
		handle_input(back)
		return
	if action_id == &"realmz_controller_system" and _application.accepts_route_input():
		_application._shell_presenter.open_system_workspace()
		_mark_handled()
		return
	if action_id == &"realmz_controller_confirm":
		if _application._shell_presenter.open_controller_text_editor():
			_mark_handled()
			return
		if _focus.activate_focused(_application):
			_mark_handled()
		return
	if action_id == &"realmz_controller_section_previous" or action_id == &"realmz_controller_section_next":
		_focus.focus_next(_application, action_id == &"realmz_controller_section_previous")
		_mark_handled()
		return
	if action_id == &"realmz_controller_character_previous" or action_id == &"realmz_controller_character_next":
		if _application._shell_presenter.controller_select_relative_character(-1 if action_id == &"realmz_controller_character_previous" else 1):
			_mark_handled()
		return
	if action_id == &"realmz_controller_inspect":
		_application._shell_presenter.show_controller_detail(_focus.inspection_text(_application))
		_mark_handled()
		return
	var scroll_direction := _controller_scroll_direction(action_id)
	if scroll_direction != Vector2i.ZERO:
		if _focus.scroll_active(_application, scroll_direction):
			_mark_handled()
		return
	var direction := direction_action
	var focused: Control = _application.get_viewport().gui_get_focus_owner()
	if direction != Vector2i.ZERO and (focused != null or not _application.accepts_exploration_input()):
		_focus.move(_application, direction)
		_mark_handled()
		return
	if direction != Vector2i.ZERO and _application.accepts_exploration_input():
		if _application._dungeon_presenter.is_active():
			if not repeated:
				_application._dungeon_presenter.handle_keyboard_press(direction)
		else:
			var combined := _combined_controller_direction()
			if _application._held_movement.active_source() == &"controller":
				_application._held_movement.update(&"controller", combined)
			else:
				_application._held_movement.start(&"controller", combined)
		_mark_handled()


func clear_controller_state() -> void:
	_controller_directions.clear()
	_stop_controller_movement()


func _handle_controller_combat(action_id: StringName, direction: Vector2i, scroll_direction: Vector2i, repeated: bool) -> bool:
	var battlefield: BattlefieldInteractionController = _application._battlefield_presenter.interaction
	if scroll_direction != Vector2i.ZERO:
		return _application._battlefield_presenter.controller_pan(scroll_direction)
	if action_id == &"realmz_controller_back":
		if _application.abort_full_party_auto(false):
			return true
		return battlefield.cancel_targeting() or battlefield.cancel_movement_preview()
	if battlefield.targeting != null:
		if direction != Vector2i.ZERO:
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
			battlefield.inspect_target_preview()
			return true
		return false
	if action_id == &"realmz_controller_confirm" and battlefield.has_movement_preview():
		return battlefield.confirm_movement_preview()
	if direction != Vector2i.ZERO and not repeated and _application._interaction_presenter.combat.accepts_spatial_input():
		battlefield.preview_movement_direction(_combined_controller_direction())
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
