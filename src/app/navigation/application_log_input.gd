## Gives read-only logs and diagnostics sole ownership of controller input.
class_name ApplicationLogInput
extends RefCounted


static func handle_input(application: Variant, event: InputEvent) -> bool:
	var presenter := application.get("_interaction_presenter") as InteractionPresenter
	var diagnostics := application.get("debug_tools") as DebugToolsHost
	if presenter != null and presenter.combat_log.handle_input(event):
		if event is InputEventKey or event is InputEventAction:
			application.get_viewport().set_input_as_handled()
		return true
	if diagnostics != null and diagnostics.handle_input(event):
		application.get_viewport().set_input_as_handled()
		return true
	if diagnostics != null and diagnostics.is_open():
		return true
	if presenter != null and presenter.handle_global_pointer_acknowledgement(event):
		application.get_viewport().set_input_as_handled()
		return true
	return false


static func handle_controller(application: Variant, action_id: StringName, direction: Vector2i) -> bool:
	var presenter := application.get("_interaction_presenter") as InteractionPresenter
	var diagnostics := application.get("debug_tools") as DebugToolsHost
	if presenter != null and presenter.combat_log.handle_controller(action_id, direction) or diagnostics != null and diagnostics.handle_controller(action_id, direction):
		return true
	if presenter == null:
		return false
	var view: GameView = application.session_controller.view()
	if action_id == &"realmz_controller_top_menu" and view != null and view.combat_view != null and not application.lifecycle_host.has_active_interaction() and not application._shell_presenter.navigation_overlay_active:
		presenter.combat_log.open()
		return true
	return false
