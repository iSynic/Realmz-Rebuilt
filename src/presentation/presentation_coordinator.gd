class_name PresentationCoordinator
extends Node

var _session_controller: GameSessionController
var _map_presenter: ClassicMapPresenter
var _interaction_presenter: InteractionPresenter
var _shell_presenter: ClassicShellPresenter
var _audio_presenter: ClassicAudioPresenter
var _media: PackageMediaCatalog


func bind(session_controller: GameSessionController, map_presenter: ClassicMapPresenter, interaction_presenter: InteractionPresenter, shell_presenter: ClassicShellPresenter, audio_presenter: ClassicAudioPresenter) -> void:
	assert(session_controller != null, "Presentation requires a session controller")
	assert(map_presenter != null, "Presentation requires an explicit map presenter")
	assert(interaction_presenter != null, "Presentation requires an explicit interaction presenter")
	assert(shell_presenter != null, "Presentation requires an explicit Classic shell presenter")
	assert(audio_presenter != null, "Presentation requires an explicit audio presenter")
	_session_controller = session_controller
	_map_presenter = map_presenter
	_interaction_presenter = interaction_presenter
	_shell_presenter = shell_presenter
	_audio_presenter = audio_presenter
	_session_controller.step_committed.connect(_on_step_committed)
	_present_current_view()


func _on_step_committed(step: SessionStep) -> void:
	_present_current_view()
	_shell_presenter.present_step(step)
	_shell_presenter.present_media_events(step.events, _media)
	_audio_presenter.present_events(step.events, _media)


func set_package_media(media: PackageMediaCatalog) -> void:
	_media = media


func _present_current_view() -> void:
	var game_view := _session_controller.session().view()
	_map_presenter.present(game_view)
	_interaction_presenter.present(game_view.pending_interaction)
	_shell_presenter.present(game_view)
