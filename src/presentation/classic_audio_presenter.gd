class_name ClassicAudioPresenter
extends Node

signal sound_observed(sound_id: int)
signal blocking_state_changed(blocking: bool)
signal music_state_changed(playlist_id: int, title: String, playing: bool)

const CHANNEL_COUNT: int = 4

var last_sound_id: int = 0
var master_volume: float = 1.0
var sound_volume: float = 1.0
var music_volume: float = 0.8
var reduced_sound: bool = false
var current_music_playlist_id: int = 0
var current_music_title: String = ""
var last_media_diagnostic: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _channel_index: int = -1
var _pending_sounds: Array[Dictionary] = []
var _processing_sounds: bool = false
var _waiting_player: AudioStreamPlayer
var _waiting_finished_callback: Callable
var _music_player: AudioStreamPlayer


func _ready() -> void:
	for index: int in range(CHANNEL_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "ClassicSoundChannel%d" % (index + 1)
		_players.append(player)
		add_child(player)
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "ClassicMusicChannel"
	add_child(_music_player)
	_apply_volume()


func present_events(events: Array[DomainEvent], media: ClassicMediaCatalog) -> void:
	for event: DomainEvent in events:
		if event.kind != &"sound_requested":
			continue
		if reduced_sound and bool(event.payload.get("reducedSoundEligible", false)):
			continue
		if bool(event.payload.get("stopExisting", false)):
			_stop_all()
		last_sound_id = int(event.payload.get("soundId", 0))
		sound_observed.emit(last_sound_id)
		if media == null:
			continue
		var asset := media.asset_by_resource("snd ", last_sound_id)
		if asset == null:
			last_media_diagnostic = media.resolution_diagnostic("snd ", last_sound_id, "classic-sound")
			continue
		var stream := media.audio_stream_by_resource("snd ", last_sound_id)
		last_media_diagnostic = media.resolution_diagnostic("snd ", last_sound_id, "classic-sound", "decoded" if stream != null else "decode-failed")
		if stream == null:
			continue
		_pending_sounds.append({"stream": stream, "waitForCompletion": bool(event.payload.get("waitForCompletion", false))})
	_drain_sound_queue()


func present_sound(sound_id: int, media: ClassicMediaCatalog, wait_for_completion: bool = false, stop_existing: bool = false, reduced_sound_eligible: bool = false) -> void:
	present_events([DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": wait_for_completion, "stopExisting": stop_existing, "reducedSoundEligible": reduced_sound_eligible, "source": "classic-presentation-workspace"})], media)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func set_sound_volume(value: float) -> void:
	sound_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func set_reduced_sound(enabled: bool) -> void:
	reduced_sound = enabled


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func present_music_context(playlist_id: int, settings: PresentationSettings, media: ClassicMediaCatalog, stock_music: ClassicMusicCatalog) -> void:
	if settings == null or not settings.music_enabled or playlist_id <= 0:
		stop_music()
		return
	var mode := settings.music_mode(playlist_id)
	if mode == PresentationSettings.MUSIC_CONTINUE:
		return
	if mode == PresentationSettings.MUSIC_OFF:
		stop_music()
		return
	if current_music_playlist_id == playlist_id and _music_player != null and _music_player.playing:
		return
	var stream: AudioStream
	var title := ""
	if media != null and playlist_id >= 15 and playlist_id <= 17:
		var package_asset := media.scenario_music_asset(playlist_id - 14)
		if package_asset != null:
			stream = media.audio_stream(package_asset)
			title = package_asset.label
	if stream == null and stock_music != null:
		stream = stock_music.stream(playlist_id)
		title = stock_music.title(playlist_id)
	if stream == null:
		if current_music_playlist_id != playlist_id:
			stop_music()
		return
	_music_player.stop()
	_music_player.stream = stream
	if _music_player.is_inside_tree():
		_music_player.play()
	current_music_playlist_id = playlist_id
	current_music_title = title if not title.is_empty() else ClassicMusicContext.context_name(playlist_id)
	music_state_changed.emit(current_music_playlist_id, current_music_title, true)


func stop_music() -> void:
	if _music_player != null:
		_music_player.stop()
	var changed := current_music_playlist_id != 0 or not current_music_title.is_empty()
	current_music_playlist_id = 0
	current_music_title = ""
	if changed:
		music_state_changed.emit(0, "", false)


func is_blocking() -> bool:
	return _processing_sounds


func _apply_volume() -> void:
	for player: AudioStreamPlayer in _players:
		var effective_sound := master_volume * sound_volume
		player.volume_db = -80.0 if effective_sound <= 0.0 else linear_to_db(effective_sound)
	if _music_player != null:
		var effective_music := master_volume * music_volume
		_music_player.volume_db = -80.0 if effective_music <= 0.0 else linear_to_db(effective_music)


func _drain_sound_queue() -> void:
	if _processing_sounds:
		return
	while not _pending_sounds.is_empty():
		var request: Dictionary = _pending_sounds.pop_front()
		var player := _next_channel()
		if player == null:
			continue
		player.stop()
		player.stream = request["stream"] as AudioStream
		player.play()
		if bool(request["waitForCompletion"]) and player.playing:
			_processing_sounds = true
			blocking_state_changed.emit(true)
			_waiting_player = player
			_waiting_finished_callback = _on_waiting_sound_finished.bind(player)
			player.finished.connect(_waiting_finished_callback, CONNECT_ONE_SHOT)
			return


func _on_waiting_sound_finished(player: AudioStreamPlayer) -> void:
	if player != _waiting_player:
		return
	_waiting_player = null
	_waiting_finished_callback = Callable()
	_processing_sounds = false
	blocking_state_changed.emit(false)
	_drain_sound_queue()


func _next_channel() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	_channel_index = (_channel_index + 1) % _players.size()
	return _players[_channel_index]


func _stop_all() -> void:
	var was_blocking := _processing_sounds
	if _waiting_player != null and _waiting_finished_callback.is_valid() and _waiting_player.finished.is_connected(_waiting_finished_callback):
		_waiting_player.finished.disconnect(_waiting_finished_callback)
	_waiting_player = null
	_waiting_finished_callback = Callable()
	_processing_sounds = false
	_pending_sounds.clear()
	for player: AudioStreamPlayer in _players:
		player.stop()
	if was_blocking:
		blocking_state_changed.emit(false)
