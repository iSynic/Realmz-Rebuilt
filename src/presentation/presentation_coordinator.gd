class_name PresentationCoordinator
extends Node

var _session_controller: GameSessionController
var _map_presenter: ClassicMapPresenter
var _interaction_presenter: InteractionPresenter


func bind(session_controller: GameSessionController, map_presenter: ClassicMapPresenter, interaction_presenter: InteractionPresenter) -> void:
	assert(session_controller != null, "Presentation requires a session controller")
	assert(map_presenter != null, "Presentation requires an explicit map presenter")
	assert(interaction_presenter != null, "Presentation requires an explicit interaction presenter")
	_session_controller = session_controller
	_map_presenter = map_presenter
	_interaction_presenter = interaction_presenter
	_session_controller.step_committed.connect(_on_step_committed)
	_present_current_view()


func _on_step_committed(_step: SessionStep) -> void:
	_present_current_view()


func _present_current_view() -> void:
	var game_view := _session_controller.session().view()
	_map_presenter.present(game_view)
	_interaction_presenter.present(game_view.pending_interaction)
