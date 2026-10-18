## Routes persistence hotkeys through the existing save/load availability and shell actions.
class_name ApplicationSaveInput
extends RefCounted


static func handle_input(shell: GameShell, view: GameView, event: InputEventKey) -> bool:
	var action := UiInputActions.quick_save_load_action(event)
	if action.is_empty():
		return false
	var preferences: SystemScreenController = shell.navigator.content_presenter.system_preferences
	if action == &"save":
		if GameShellAvailability.save_reason(view).is_empty():
			shell.handle_system_action_requested(&"save", "quick")
	else:
		var preview: SaveSlotPreview = preferences.saves.active_quick_preview
		if GameShellAvailability.load_reason(view).is_empty() and preview != null and preview.can_load:
			shell.handle_system_action_requested(&"load", preferences.saves.active_slot_id)
	shell.get_viewport().set_input_as_handled()
	return true
