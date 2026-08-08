class_name PresentationCoordinator
extends Node

var _session_controller: GameSessionController
var _map_presenter: ClassicMapPresenter
var _dungeon_presenter: DungeonMap3DPresenter
var _interaction_presenter: InteractionPresenter
var _shell_presenter: ClassicApplicationShell
var _audio_presenter: ClassicAudioPresenter
var _media: PackageMediaCatalog
var _active_route: StringName = &"exploration"


func bind(session_controller: GameSessionController, map_presenter: ClassicMapPresenter, dungeon_presenter: DungeonMap3DPresenter, interaction_presenter: InteractionPresenter, shell_presenter: ClassicApplicationShell, audio_presenter: ClassicAudioPresenter) -> void:
	assert(session_controller != null, "Presentation requires a session controller")
	assert(map_presenter != null, "Presentation requires an explicit map presenter")
	assert(dungeon_presenter != null, "Presentation requires an explicit topology-derived dungeon presenter")
	assert(interaction_presenter != null, "Presentation requires an explicit interaction presenter")
	assert(shell_presenter != null, "Presentation requires an explicit Classic shell presenter")
	assert(audio_presenter != null, "Presentation requires an explicit audio presenter")
	_session_controller = session_controller
	_map_presenter = map_presenter
	_dungeon_presenter = dungeon_presenter
	_interaction_presenter = interaction_presenter
	_shell_presenter = shell_presenter
	_audio_presenter = audio_presenter
	_session_controller.step_committed.connect(_on_step_committed)
	_present_current_view()


func _on_step_committed(step: SessionStep) -> void:
	_present_current_view(false)
	_shell_presenter.present_step(step)
	_shell_presenter.present_media_events(step.events, _media)
	_audio_presenter.present_events(step.events, _media)
	var passive_classic_text := ""
	for event: DomainEvent in step.events:
		if event.kind == &"message_shown" and event.payload.has("classicClick") and not bool(event.payload.get("classicClick", false)):
			passive_classic_text = String(event.payload.get("text", ""))
	var game_view := _session_controller.view()
	_present_interaction(game_view)
	if game_view.pending_interaction == null and not passive_classic_text.is_empty():
		_interaction_presenter.present_passive_classic_text(passive_classic_text)


func set_package_media(media: PackageMediaCatalog) -> void:
	_media = media
	_map_presenter.set_media_catalog(media)
	_shell_presenter.set_package_media(media)


func set_active_route(route_id: StringName) -> void:
	_active_route = route_id
	_present_current_view()


func set_dungeon_3d_enabled(enabled: bool) -> void:
	_dungeon_presenter.set_enabled(enabled)
	_present_current_view()


func _present_current_view(include_interaction: bool = true) -> void:
	var game_view := _session_controller.view()
	_map_presenter.present(game_view)
	_dungeon_presenter.present(game_view)
	var exploration_visible := _active_route == &"exploration" and game_view != null and game_view.session_started
	_map_presenter.visible = exploration_visible and not _dungeon_presenter.is_active()
	_dungeon_presenter.visible = exploration_visible and _dungeon_presenter.is_active()
	_shell_presenter.present(game_view)
	if include_interaction:
		_present_interaction(game_view)


func _present_interaction(game_view: GameView) -> void:
	_interaction_presenter.present(game_view.pending_interaction, _shell_presenter.latest_classic_text())
