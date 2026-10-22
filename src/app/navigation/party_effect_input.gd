## Keeps field-effect playback exclusive while retaining Pause and explicit reveal.
class_name PartyEffectInput
extends RefCounted


static func handle_input(application: Variant, event: InputEvent, key_event: InputEventKey) -> bool:
	if application.presentation_coordinator == null or not application.presentation_coordinator.party_effect_playback.is_active():
		return false
	if application.lifecycle_host.has_active_interaction(): return false
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.button_index == MOUSE_BUTTON_LEFT and application.shell_presenter.hud.world_reveal_contains_point(mouse.position):
		return true
	var pause_pointer: bool = mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT and application.shell_presenter.commands.pause_contains_point(mouse.position)
	if pause_pointer or key_event != null and key_event.pressed and not key_event.echo and key_event.keycode in [KEY_ESCAPE, KEY_F10]:
		application.presentation_coordinator.party_effect_playback.skip()
		application.shell_presenter.controller.pause.open()
	if mouse != null and not mouse.pressed:
		application.shell_presenter.commands.release_pointer_hold()
	if not event is InputEventMouseMotion:
		var viewport: Viewport = application.get_viewport()
		if viewport != null: viewport.set_input_as_handled()
	return true
