extends RefCounted

const END_ADVENTURE_REQUEST_ID := "host.lifecycle.end-adventure"
const QUIT_APPLICATION_REQUEST_ID := "host.lifecycle.quit-application"
const SAVE_AND_END: StringName = &"save-and-end"
const END_WITHOUT_SAVING: StringName = &"end-without-saving"
const SAVE_AND_QUIT: StringName = &"save-and-quit"
const QUIT_WITHOUT_SAVING: StringName = &"quit-without-saving"
const CANCEL: StringName = &"cancel"


static func end_adventure_request(in_combat: bool) -> InteractionRequest:
	var options: Array[Dictionary] = []
	if not in_combat:
		options.append({"action": SAVE_AND_END, "label": "Save and end adventure"})
	options.append({"action": END_WITHOUT_SAVING, "label": "End adventure without saving"})
	options.append({"action": CANCEL, "label": "Cancel"})
	return InteractionRequest.new(END_ADVENTURE_REQUEST_ID, InteractionRequest.SESSION_LIFECYCLE, {
		"operation": "end-adventure",
		"prompt": "End the active adventure?",
		"inCombat": in_combat,
		"options": options,
	})


static func quit_application_request(has_active_session: bool, in_combat: bool) -> InteractionRequest:
	var options: Array[Dictionary] = []
	if has_active_session and not in_combat:
		options.append({"action": SAVE_AND_QUIT, "label": "Save and quit Realmz 2"})
	options.append({"action": QUIT_WITHOUT_SAVING, "label": "Quit Realmz 2"})
	options.append({"action": CANCEL, "label": "Cancel"})
	return InteractionRequest.new(QUIT_APPLICATION_REQUEST_ID, InteractionRequest.SESSION_LIFECYCLE, {
		"operation": "quit-application",
		"prompt": "Quit Realmz 2?",
		"hasActiveSession": has_active_session,
		"inCombat": in_combat,
		"options": options,
	})


static func response_action(request: InteractionRequest, response: InteractionResponse) -> StringName:
	if request == null or response == null or request.kind != InteractionRequest.SESSION_LIFECYCLE:
		return &""
	if response.request_id != request.request_id or response.kind != request.kind:
		return &""
	var action := StringName(response.payload.get("action", &""))
	for option: Dictionary in request.payload.get("options", []):
		if StringName(option.get("action", &"")) == action:
			return action
	return &""


static func allows_close(action: StringName, save_succeeded: bool = true) -> bool:
	if action == SAVE_AND_END:
		return save_succeeded
	return action == END_WITHOUT_SAVING


static func execute_end_adventure(action: StringName, save_operation: Callable, close_operation: Callable) -> Dictionary:
	if action == CANCEL:
		return {"state": &"cancelled", "step": null}
	if action == SAVE_AND_END:
		if not save_operation.is_valid() or not bool(save_operation.call()):
			return {"state": &"save-failed", "step": null}
	elif action != END_WITHOUT_SAVING:
		return {"state": &"invalid", "step": null}
	if not close_operation.is_valid():
		return {"state": &"close-failed", "step": null}
	var step: SessionStep = close_operation.call()
	if step == null or step.state == SessionStep.State.FAILED:
		return {"state": &"close-failed", "step": step}
	return {"state": &"closed", "step": step}


static func execute_quit(action: StringName, save_operation: Callable, quit_operation: Callable) -> StringName:
	if action == CANCEL:
		return &"cancelled"
	if action == SAVE_AND_QUIT:
		if not save_operation.is_valid() or not bool(save_operation.call()):
			return &"save-failed"
	elif action != QUIT_WITHOUT_SAVING:
		return &"invalid"
	if not quit_operation.is_valid():
		return &"quit-failed"
	quit_operation.call()
	return &"quit-requested"
