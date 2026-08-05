class_name PresentationCoordinator
extends Node

var _session_controller: GameSessionController


func bind(session_controller: GameSessionController) -> void:
	assert(session_controller != null, "Presentation requires a session controller")
	_session_controller = session_controller
	_session_controller.step_committed.connect(_on_step_committed)


func _on_step_committed(_step: SessionStep) -> void:
	# Screen presenters will consume the committed events and GameView here.
	pass
