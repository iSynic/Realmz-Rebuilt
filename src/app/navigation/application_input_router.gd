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
	if _update_controller_direction(action_id, direction_action, pressed):
		return
	if _application.presentation_coordinator != null and _application.presentation_coordinator.is_combat_playback_active():
		if action_id == &"realmz_controller_back":
			_application.abort_full_party_auto(true)
		_mark_handled()
		return
	if _handle_controller_overlay(action_id):
		return
	if _application.lifecycle_host.has_active_interaction() and action_id in [
		&"realmz_controller_action_radial",
		&"realmz_controller_workspace_radial",
		&"realmz_controller_character_previous",
		&"realmz_controller_character_next",
		&"realmz_controller_system",
	]:
		_mark_handled()
		return
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	var combat_pending := pending != null and pending.kind == InteractionRequest.COMBAT
	if combat_pending and _handle_controller_combat(action_id, direction_action, _controller_scroll_direction(action_id), repeated):
		_mark_handled()
		return
	if _handle_controller_navigation_action(action_id):
		return
	_handle_controller_direction(direction_action, repeated)


func _handle_controller_navigation_action(action_id: StringName) -> bool:
	var pending: InteractionRequest = _application.session_controller.view().active_interaction_request()
	if action_id == &"realmz_controller_action_radial":
		_stop_controller_movement()
		if pending != null and _application._shell_presenter.controller.open_interaction_radial(_application._interaction_presenter.controller.actions(), _application._interaction_presenter.controller.activate_action):
			_mark_handled()
			return true
		if _application._shell_presenter.controller.open_action_radial():
			_mark_handled()
		return true
	if action_id == &"realmz_controller_workspace_radial":
		_stop_controller_movement()
		if _application._shell_presenter.controller.open_workspace_radial():
			_mark_handled()
		return true
	if action_id == &"realmz_controller_back":
		_stop_controller_movement()
		var back := InputEventAction.new()
		back.action = &"realmz_back"
		back.pressed = true
		handle_input(back)
		return true
	if action_id == &"realmz_controller_system" and _application.accepts_route_input():
		_application._shell_presenter.open_system_workspace()
		_mark_handled()
		return true
	if action_id == &"realmz_controller_confirm":
		if _application._interaction_presenter.controller.submit_acknowledgement():
			_mark_handled()
			return true
		if _application._shell_presenter.controller.open_text_editor():
			_mark_handled()
			return true
		if _focus.activate_focused(_controller_focus_root()):
			_mark_handled()
		return true
	if action_id == &"realmz_controller_section_previous" or action_id == &"realmz_controller_section_next":
		_focus.focus_next(_controller_focus_root(), action_id == &"realmz_controller_section_previous")
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
			var combined := _combined_controller_direction()
			if _application._held_movement.active_source() == &"controller":
				_application._held_movement.update(&"controller", combined)
			else:
				_application._held_movement.start(&"controller", combined)
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
	if remaining != Vector2i.ZERO and _application.accepts_exploration_input() and not _application._dungeon_presenter.is_active() and not _application._shell_presenter.controller.radial_is_open():
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
		var direction := _controller_direction(action_id)
		if direction != Vector2i.ZERO:
			_application._shell_presenter.controller.move_radial(direction)
	_mark_handled()
	return true


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
			battlefield.controller.inspect_target_preview()
			return true
		return true
	if action_id == &"realmz_controller_confirm" and battlefield.controller.has_movement_preview():
		return battlefield.confirm_movement_preview()
	if action_id == &"realmz_controller_inspect":
		return battlefield.controller.inspect_focused_combatant()
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


func _controller_focus_root() -> Control:
	return _application._interaction_presenter if _application._interaction_presenter != null and _application._interaction_presenter.has_blocking_request() else _application


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
