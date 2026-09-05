## Coordinates application input router within application startup and host integration.

class_name ApplicationInputRouter
extends RefCounted

## Translates host input into application routes, interaction responses, and typed game intents.

var _application: Variant


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


func _handle_debug_or_acknowledgement_input(event: InputEvent) -> bool:
	if _application._debug_tools != null and _application._debug_tools.handle_input(event):
		_mark_handled()
		return true
	if _application._debug_tools != null and _application._debug_tools.is_open():
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
