## Admits host movement and preserves held continuation after one committed step.
class_name ApplicationMovementInput
extends RefCounted


static func submit(application: Variant, direction: Vector2i) -> bool:
	if not application.shell_presenter.accepts_exploration_input() or not application.session_controller.view().session_started or application.session_controller.view().pending_interaction != null:
		return false
	var map_view: MapView = application.session_controller.view().map_view
	if MapTopology.is_diagonal_direction(direction) and (map_view == null or map_view.level_type != &"land"):
		return false
	var before: GameView = application.session_controller.view()
	var intent := ExplorationIntents.overhead_dungeon_move(direction) if map_view != null and map_view.level_type == &"dungeon" and (application.dungeon_presenter == null or not application.dungeon_presenter.is_active()) else ExplorationIntents.move(direction)
	var step: SessionStep = application.submit_intent(intent)
	var after: GameView = application.session_controller.view()
	if step.state == SessionStep.State.FAILED or after == null or after.pending_interaction != null or after.combat_view != null:
		return false
	return HeldMovementController.continues_after_step(direction, before.party_map_id, before.party_coordinate, after.party_map_id, after.party_coordinate, step.events, application.accepts_exploration_input())
