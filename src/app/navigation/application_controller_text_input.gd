## Maps normalized controller actions into the shared modal keyboard.
class_name ApplicationControllerTextInput
extends RefCounted


static func handle(controller: GameShell.ControllerAccess, action_id: StringName, direction: Vector2i) -> bool:
	if action_id == &"realmz_controller_confirm":
		controller.confirm_text_editor()
	elif action_id == &"realmz_controller_back":
		controller.cancel_text_editor()
	elif action_id == &"realmz_controller_section_previous":
		controller.page_text_editor(-1)
	elif action_id == &"realmz_controller_section_next":
		controller.page_text_editor(1)
	elif action_id in [&"realmz_controller_action_radial", &"realmz_controller_workspace_radial", &"realmz_controller_character_previous", &"realmz_controller_character_next"]:
		controller.edit_text(action_id)
	else:
		if direction != Vector2i.ZERO:
			controller.move_text_editor(direction)
	return true
