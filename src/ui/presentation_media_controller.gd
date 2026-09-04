## Owns effective Classic media composition and route-aware music presentation.

class_name PresentationMediaController
extends RefCounted

var _map_presenter: ClassicMapPresenter
var _battlefield_presenter: ClassicBattlefieldPresenter
var _shell_presenter: GameShell
var _audio_presenter: ClassicAudioPresenter
var _package_media: MediaSource
var _character_media: MediaSource
var _application_media := ApplicationMediaCatalog.new()
var _stock_music := ClassicMusicCatalog.new()
var _catalog: ClassicMediaCatalog
var _active_route: StringName = &"exploration"
var _game_view: GameView


func bind(
	map_presenter: ClassicMapPresenter,
	battlefield_presenter: ClassicBattlefieldPresenter,
	shell_presenter: GameShell,
	audio_presenter: ClassicAudioPresenter
) -> void:
	assert(map_presenter != null, "Presentation media requires the map presenter")
	assert(battlefield_presenter != null, "Presentation media requires the battlefield presenter")
	assert(shell_presenter != null, "Presentation media requires the application shell")
	assert(audio_presenter != null, "Presentation media requires the audio presenter")
	_map_presenter = map_presenter
	_battlefield_presenter = battlefield_presenter
	_shell_presenter = shell_presenter
	_audio_presenter = audio_presenter


func set_package_media(media: MediaSource) -> void:
	_package_media = media
	_catalog = ClassicMediaCatalog.new(media, _application_media, _character_media)
	_map_presenter.set_media_catalog(_catalog)
	_battlefield_presenter.set_media_catalog(_catalog)
	_shell_presenter.set_package_media(_catalog)
	refresh_music()


func set_application_character_media(media: MediaSource) -> void:
	_character_media = media
	set_package_media(_package_media)


func catalog() -> ClassicMediaCatalog:
	return _catalog


func present_music_context(active_route: StringName, game_view: GameView) -> void:
	_active_route = active_route
	_game_view = game_view
	refresh_music()


func refresh_music() -> void:
	if _audio_presenter == null or _shell_presenter == null:
		return
	_audio_presenter.present_music_context(
		ClassicMusicContext.playlist_for(_active_route, _game_view),
		_shell_presenter.settings,
		_catalog,
		_stock_music
	)
