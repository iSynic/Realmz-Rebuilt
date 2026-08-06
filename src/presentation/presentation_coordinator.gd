class_name PresentationCoordinator
extends Node

var _session_controller: GameSessionController
var _map_presenter: ClassicMapPresenter


func bind(session_controller: GameSessionController, map_presenter: ClassicMapPresenter) -> void:
	assert(session_controller != null, "Presentation requires a session controller")
	assert(map_presenter != null, "Presentation requires an explicit map presenter")
	_session_controller = session_controller
	_map_presenter = map_presenter
	_session_controller.step_committed.connect(_on_step_committed)
	_map_presenter.present(_session_controller.session().view())


func _on_step_committed(_step: SessionStep) -> void:
	_map_presenter.present(_session_controller.session().view())
