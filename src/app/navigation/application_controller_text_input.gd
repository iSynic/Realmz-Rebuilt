## Maps normalized controller actions into the shared modal keyboard.
class_name ApplicationControllerTextInput
extends RefCounted


static func handle(controller: GameShellControllerAccess, action_id: StringName, direction: Vector2i) -> bool:
	if action_id == &"realmz_controller_confirm":
		controller.text.confirm()
	elif action_id == &"realmz_controller_back":
		controller.text.cancel()
	elif action_id == &"realmz_controller_section_previous":
		controller.text.page(-1)
	elif action_id == &"realmz_controller_section_next":
		controller.text.page(1)
	elif action_id in [&"realmz_controller_action_radial", &"realmz_controller_workspace_radial", &"realmz_controller_character_previous", &"realmz_controller_character_next"]:
		controller.text.edit(action_id)
	else:
		if direction != Vector2i.ZERO:
			controller.text.move(direction)
	return true
