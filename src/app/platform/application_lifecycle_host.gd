## Owns process-quit and end-adventure interaction state for the application host.
class_name ApplicationLifecycleHost
extends RefCounted

var _session_controller: GameSessionController
var _presentation: PresentationCoordinator
var _shell: GameShell
var _held_movement: HeldMovementController
var _save_operation: Callable
var _refresh_saves_operation: Callable
var _present_step_operation: Callable
var _closed_operation: Callable
var _quit_operation: Callable
var _interaction: InteractionRequest
var _save_and_quit_pending := false
var _close_waits_for_playback := false


func bind(
		session_controller: GameSessionController,
		presentation: PresentationCoordinator,
		shell: GameShell,
		held_movement: HeldMovementController,
		save_operation: Callable,
		refresh_saves_operation: Callable,
		present_step_operation: Callable,
		closed_operation: Callable,
		quit_operation: Callable
) -> void:
	_session_controller = session_controller
	_presentation = presentation
	_shell = shell
	_held_movement = held_movement
	_save_operation = save_operation
	_refresh_saves_operation = refresh_saves_operation
	_present_step_operation = present_step_operation
	_closed_operation = closed_operation
	_quit_operation = quit_operation


func has_active_interaction() -> bool:
	return _interaction != null


static func response_owner(has_host_interaction: bool, standalone_creator_active: bool) -> StringName:
	if has_host_interaction:
		return &"host"
	if standalone_creator_active:
		return &"standalone-creator"
	return &"session"


func request_quit() -> void:
	_held_movement.stop()
	if _interaction != null:
		return
	if _save_and_quit_pending:
		_save_and_quit_pending = false
		_set_save_and_quit_mode(false)
	var view := _session_controller.view()
	var in_combat := view.combat_view != null and view.combat_view.outcome == &"active"
	_interaction = ApplicationLifecycle.quit_application_request(view.session_started, in_combat)
	_presentation.present_host_interaction(_interaction)
	_shell.status.set_status("Confirm whether to quit Realmz Rebuilt.")


func request_end_adventure() -> void:
	_held_movement.stop()
	var view := _session_controller.view()
	if not view.session_started:
		_shell.show_splash()
		return
	var pending := view.active_interaction_request()
	if pending != null and pending.kind != InteractionRequest.COMBAT:
		_shell.status.set_status("Resolve the current interaction before ending the adventure.", true)
		return
	if _interaction != null:
		return
	var in_combat := view.combat_view != null and view.combat_view.outcome == &"active"
	_interaction = ApplicationLifecycle.end_adventure_request(in_combat)
	_presentation.present_host_interaction(_interaction)
	_shell.status.set_status("Choose how to return to the main menu.")


func respond(response: InteractionResponse) -> void:
	var action := ApplicationLifecycle.response_action(_interaction, response)
	if action.is_empty():
		_represent_error("The lifecycle response was invalid.")
		return
	var body := _interaction.body as LifecycleRequestBody
	var operation := body.operation if body != null else &""
	if operation == &"quit-application":
		_respond_quit(action)
		return
	if operation != &"end-adventure":
		_represent_error("The lifecycle operation was invalid.")
		return
	_respond_end_adventure(action)


func save_and_quit(slot_id: String) -> void:
	if not _save_and_quit_pending or not bool(_save_operation.call(slot_id)):
		return
	_save_and_quit_pending = false
	_set_save_and_quit_mode(false)
	_quit_operation.call()


func route_changed(route_id: StringName) -> void:
	if not _save_and_quit_pending or route_id == &"system":
		return
	_save_and_quit_pending = false
	_set_save_and_quit_mode(false)
	_shell.status.set_status("Save and quit cancelled.")


func handles_terminal_step(step: SessionStep, playback_active: bool) -> bool:
	if not ApplicationCombatPolicy.step_ends_session(step):
		return false
	if ApplicationCombatPolicy.should_defer_session_close(step, playback_active):
		_close_waits_for_playback = true
	else:
		_complete_closed_session()
	return true


func playback_step_settled(step: SessionStep) -> bool:
	if not _close_waits_for_playback or not ApplicationCombatPolicy.step_ends_session(step):
		return false
	_complete_closed_session()
	return true


func _respond_end_adventure(action: StringName) -> void:
	var result := ApplicationLifecycle.execute_end_adventure(
		action,
		func() -> bool: return bool(_save_operation.call("quick")),
		func() -> SessionStep: return _session_controller.close()
	)
	var state := StringName(result.get("state", &"invalid"))
	if state == &"cancelled":
		_interaction = null
		_presentation.refresh()
		_shell.status.set_status("Adventure continues.")
	elif state == &"save-failed":
		_presentation.present_host_interaction(_interaction)
	elif state == &"close-failed":
		var failed_step: SessionStep = result.get("step")
		_represent_error("End Adventure failed • %s" % (failed_step.error_message if failed_step != null else "The session close operation is unavailable."))
	elif state == &"pending":
		_interaction = null
		_present_step_operation.call(result.get("step"))
	elif state == &"closed":
		_complete_closed_session()
	else:
		_represent_error("The lifecycle response was invalid.")


func _respond_quit(action: StringName) -> void:
	if action == ApplicationLifecycle.SAVE_AND_QUIT:
		_interaction = null
		_presentation.dismiss_host_interaction()
		_save_and_quit_pending = true
		_refresh_saves_operation.call()
		_shell.navigator.content_presenter.set_save_and_quit_mode(true)
		_shell.navigator.open_screen(&"system")
		_shell.status.set_status("Choose a save slot, then Save and Quit.")
		return
	var has_session := _session_controller.view().session_started
	var state := ApplicationLifecycle.execute_quit(
		action,
		func() -> bool: return bool(_save_operation.call("quick")) if has_session else false,
		_quit_operation
	)
	if state == &"cancelled":
		_interaction = null
		_presentation.dismiss_host_interaction()
		_shell.status.set_status("Quit cancelled.")
	elif state == &"save-failed":
		_presentation.present_host_interaction(_interaction)


func _represent_error(message: String) -> void:
	_shell.status.set_status(message, true)
	_presentation.present_host_interaction(_interaction)


func _set_save_and_quit_mode(enabled: bool) -> void:
	_shell.navigator.content_presenter.set_save_and_quit_mode(enabled)
	if _shell.navigator.current_screen() == &"system" and _session_controller.view().session_started:
		_shell.navigator.refresh_current_workspace()


func _complete_closed_session() -> void:
	_close_waits_for_playback = false
	_interaction = null
	_presentation.dismiss_host_interaction()
	_closed_operation.call()
