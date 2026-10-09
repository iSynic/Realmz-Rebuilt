## Resolves presentation contexts and drives one retained audio channel.
class_name MusicPlaybackController
extends RefCounted

signal state_changed(context: int, title: String, playing: bool)
signal diagnostic_changed(message: String)

var _player: AudioStreamPlayer
var _library := MusicLibraryView.new()
var _load_track: Callable
var _queues: Dictionary[String, MusicPlaybackQueue] = {}
var _originals: Dictionary[String, AudioStream] = {}
var _titles: Dictionary[String, String] = {}
var _contexts: Dictionary[String, int] = {}
var _fallbacks: Dictionary[String, bool] = {}
var _active: String = ""
var _preview: bool = false
var _campaign: String = ""
var _context: int = 0
var _transition_pending: bool = false
var _settings: PresentationSettings
var _media: ClassicMediaCatalog
var _stock: ClassicMusicCatalog
var _scenario_loader: Callable
var _scenario_hashes: Dictionary[String, String] = {}
var _scenario_assets: Dictionary[String, MediaAsset] = {}
var _scenario_media: Dictionary[String, MediaSource] = {}


func set_scenario_loader(loader: Callable) -> void:
	_scenario_loader = loader


func scenario_music_ready(hash: String, stream: AudioStream) -> void:
	for key: String in _scenario_hashes:
		if _scenario_hashes[key] == hash:
			_originals[key] = _with_loop(stream, true)
	refresh()


func bind(player: AudioStreamPlayer) -> void:
	_player = player
	_player.finished.connect(_on_finished)


func set_library(library: MusicLibraryView, loader: Callable, changed_tracks: Array[String] = []) -> void:
	_library = library
	_load_track = loader
	for key: String in _fallbacks.keys():
		if _queues[key].retry_unavailable(changed_tracks):
			_fallbacks.erase(key)
			if key == _active and not _preview:
				_player.stop()
	refresh()


func present(context: int, settings: PresentationSettings, media: ClassicMediaCatalog, stock: ClassicMusicCatalog, campaign: String) -> void:
	_transition_pending = _transition_pending or campaign != _campaign or context != _context
	_campaign = campaign
	_context = context
	_settings = settings
	_media = media
	_stock = stock
	refresh()


func refresh() -> void:
	if _player == null:
		return
	if _preview and _settings != null and not _settings.music_enabled:
		_player.stop()
		_preview = false
	if _preview:
		return
	var entering := _transition_pending
	_transition_pending = false
	if _settings == null or not _settings.music_enabled or _context <= 0:
		stop()
		return
	var mode := _settings.music_mode(_context)
	if mode == PresentationSettings.MUSIC_OFF:
		_suspend()
		state_changed.emit(0, "", false)
		return
	if mode == PresentationSettings.MUSIC_CONTINUE:
		if not _active.is_empty() and not _player.playing:
			_start()
		return
	var key := JSON.stringify([_campaign, _context])
	if key != _active:
		entering = true
		_suspend()
		_active = key
	if not _queues.has(key):
		_queues[key] = MusicPlaybackQueue.new()
		_contexts[key] = _context
	var changed := _queues[key].configure(_library.resolve(_campaign, _context))
	if changed:
		_player.stop()
		_fallbacks.erase(key)
	if entering and not _player.playing:
		_queues[key].enter_context(_settings.music_transition)
	_resolve_original(key)
	if not _player.playing:
		_start()


func stop() -> void:
	if _preview:
		return
	_suspend()
	_active = ""
	state_changed.emit(0, "", false)


func preview(track_id: String) -> bool:
	var stream := _custom_stream(track_id)
	if stream == null:
		return false
	if not _preview:
		_suspend()
	_preview = true
	_player.stop()
	_player.stream = stream
	_player.play()
	state_changed.emit(0, "Preview: " + _library.tracks[track_id].title, true)
	return true


func end_preview() -> void:
	if not _preview:
		return
	_player.stop()
	_preview = false
	refresh()


func _suspend() -> void:
	if _player != null and _player.playing:
		if not _active.is_empty() and not _preview:
			_queues[_active].position = _player.get_playback_position()
		_player.stop()


func _start() -> void:
	var queue := _queues[_active]
	if _fallbacks.get(_active, false):
		_play_original(queue.position)
		return
	if queue.exhausted:
		state_changed.emit(0, "", false)
		return
	for attempt: int in queue.count():
		var id := queue.current()
		if id == "@original":
			_play_original(queue.position)
			return
		var stream := _custom_stream(id)
		if stream != null:
			_play(stream, _library.tracks[id].title, queue.position)
			return
		queue.advance(true)
		if queue.exhausted:
			break
	_fallbacks[_active] = true
	diagnostic_changed.emit("No tracks in this playlist are available. Using this context's original music.")
	_play_original(0.0)


func _custom_stream(id: String) -> AudioStream:
	var track := _library.tracks.get(id) as MusicLibraryView.Track
	var stream: AudioStream = _load_track.call(id) if track != null and _load_track.is_valid() else null
	if stream == null:
		diagnostic_changed.emit("Unavailable music: %s. Use Repair cache or import the file again." % (track.title if track != null else id))
		return null
	return _with_loop(stream, false)


func _play_original(position: float) -> void:
	var stream := _originals.get(_active) as AudioStream
	if stream == null and _scenario_assets.has(_active) and _scenario_loader.is_valid():
		stream = _with_loop(_scenario_loader.call(_scenario_assets[_active], _scenario_media[_active]), true)
		_originals[_active] = stream
	if stream == null:
		_player.stop()
		state_changed.emit(0, "", false)
		return
	_play(stream, _titles[_active], position)


func _play(stream: AudioStream, title: String, position: float) -> void:
	_player.stream = stream
	if _player.is_inside_tree():
		_player.play(position)
	state_changed.emit(_contexts[_active], title, true)


func _on_finished() -> void:
	if _preview:
		end_preview()
	elif not _active.is_empty():
		_queues[_active].advance()
		_start()


func _resolve_original(key: String) -> void:
	var stream: AudioStream
	var title := ""
	var asset := _media.scenario_music_asset(_context - 14) if _media != null and _context >= 15 and _context <= 17 else null
	var hash := asset.sha256 if asset != null else ""
	if _scenario_hashes.get(key, "") != hash:
		_originals.erase(key)
		if _queues[key].current() == "@original" or _fallbacks.get(key, false):
			_queues[key].position = 0.0
			_player.stop()
	if asset != null:
		stream = _originals.get(key) as AudioStream
		_scenario_hashes[key] = hash
		_scenario_assets[key] = asset
		_scenario_media[key] = _media.package_media
		if stream == null:
			stream = _media.audio_stream(asset)
		title = asset.label
	else:
		_scenario_hashes.erase(key)
		_scenario_assets.erase(key)
		_scenario_media.erase(key)
	if stream == null and _stock != null:
		stream = _stock.stream(_context)
		if stream != null:
			title = _stock.title(_context)
	_originals[key] = _with_loop(stream, true)
	_titles[key] = title if not title.is_empty() else ClassicMusicContext.context_name(_context)


func _with_loop(stream: AudioStream, looped: bool) -> AudioStream:
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		if (stream as AudioStreamOggVorbis).loop == looped:
			return stream
		var result := stream.duplicate() as AudioStreamOggVorbis
		result.loop = looped
		return result
	if stream is AudioStreamMP3:
		var result := stream.duplicate() as AudioStreamMP3
		result.loop = looped
		return result
	return stream
