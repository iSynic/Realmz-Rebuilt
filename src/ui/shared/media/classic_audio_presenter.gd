## Presents Classic audio presenter through the Godot interface.

class_name ClassicAudioPresenter
extends Node

signal sound_observed(sound_id: int)
signal character_effect_requested(event: DomainEvent)
signal blocking_state_changed(blocking: bool)
signal music_state_changed(playlist_id: int, title: String, playing: bool)

const CHANNEL_COUNT: int = 4
const CHARACTER_EFFECT_FRAME_SECONDS: float = 0.055

var last_sound_id: int = 0
var master_volume: float = 1.0
var sound_volume: float = 1.0
var music_volume: float = 0.8
var reduced_sound: bool = false
var current_music_playlist_id: int = 0
var current_music_title: String = ""
var last_media_diagnostic: Dictionary = {}
var music := MusicPlaybackController.new()
var _players: Array[AudioStreamPlayer] = []
var _busy_players: Dictionary = {}
var _channel_index: int = -1
var _pending_sounds: Array[Dictionary] = []
var _processing_sounds: bool = false
var _waiting_player: AudioStreamPlayer
var _waiting_for_completion := false
var _waiting_finished_callback: Callable
var _music_player: AudioStreamPlayer
var _effect_seconds_remaining := 0.0
var _effect_first_frame := false


func _ready() -> void:
	for index: int in range(CHANNEL_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "ClassicSoundChannel%d" % (index + 1)
		_players.append(player)
		add_child(player)
		player.finished.connect(func() -> void: _busy_players.erase(player))
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "ClassicMusicChannel"
	add_child(_music_player)
	music.bind(_music_player)
	music.state_changed.connect(_on_music_state_changed)
	_apply_volume()
	set_process(false)


func _process(delta: float) -> void:
	if _effect_first_frame:
		_effect_first_frame = false
		return
	_effect_seconds_remaining -= delta
	if _effect_seconds_remaining > 0.0:
		return
	set_process(false)
	_processing_sounds = false
	blocking_state_changed.emit(false)
	_drain_sound_queue()


func present_events(events: Array[DomainEvent], media: ClassicMediaCatalog) -> void:
	for event: DomainEvent in events:
		if event.kind == &"character_effect_requested":
			_pending_sounds.append({"effect": event})
			continue
		if event.kind != &"sound_requested":
			continue
		if reduced_sound and bool(event.payload.get("reducedSoundEligible", false)):
			continue
		last_sound_id = int(event.payload.get("soundId", 0))
		sound_observed.emit(last_sound_id)
		var stop_existing := bool(event.payload.get("stopExisting", false))
		if media == null:
			if stop_existing: _pending_sounds.append({"stopExisting": true})
			continue
		var asset := media.asset_by_resource("snd ", last_sound_id)
		if asset == null:
			last_media_diagnostic = media.resolution_diagnostic("snd ", last_sound_id, "classic-sound")
			if stop_existing: _pending_sounds.append({"stopExisting": true})
			continue
		var stream := media.audio_stream_by_resource("snd ", last_sound_id)
		last_media_diagnostic = media.resolution_diagnostic("snd ", last_sound_id, "classic-sound", "decoded" if stream != null else "decode-failed")
		if stream == null:
			if stop_existing: _pending_sounds.append({"stopExisting": true})
			continue
		_pending_sounds.append({"stream": stream, "waitForCompletion": bool(event.payload.get("waitForCompletion", false)), "stopExisting": stop_existing})
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


func present_music_context(playlist_id: int, settings: PresentationSettings, media: ClassicMediaCatalog, stock_music: ClassicMusicCatalog, campaign_id: String = "") -> void:
	music.present(playlist_id, settings, media, stock_music, campaign_id)


func stop_music() -> void:
	music.stop()


func skip_effects() -> void:
	_pending_sounds.clear()
	_stop_playing_channels()


func _on_music_state_changed(context: int, title: String, playing: bool) -> void:
	current_music_playlist_id = context
	current_music_title = title
	music_state_changed.emit(context, title, playing)


func is_blocking() -> bool:
	return _processing_sounds


func is_input_blocking() -> bool:
	if not _processing_sounds:
		return false
	if _waiting_player == null or _waiting_for_completion:
		return true
	return _pending_sounds.any(func(request: Dictionary) -> bool: return request.has("effect") or bool(request.get("waitForCompletion", false)))


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
		var request: Dictionary = _pending_sounds[0]
		if request.has("effect"):
			_pending_sounds.pop_front()
			var event: DomainEvent = request["effect"]
			_effect_seconds_remaining = maxi(0, int(event.payload.get("frameCount", 0))) * CHARACTER_EFFECT_FRAME_SECONDS
			_processing_sounds = true
			_effect_first_frame = true
			set_process(true)
			blocking_state_changed.emit(true)
			character_effect_requested.emit(event)
			return
		if bool(request.get("stopExisting", false)):
			_stop_playing_channels()
		if not request.has("stream"):
			_pending_sounds.pop_front()
			continue
		var player := _next_channel()
		if player == null:
			_pending_sounds.pop_front()
			continue
		# Retain four-way overlap, but do not truncate a still-audible action
		# merely because accelerated playback has wrapped the channel ring.
		if _busy_players.has(player):
			_wait_for_sound(player, false)
			return
		_pending_sounds.pop_front()
		_channel_index = _players.find(player)
		player.stream = request["stream"] as AudioStream
		player.play()
		if player.playing:
			_busy_players[player] = true
		if bool(request["waitForCompletion"]) and player.playing:
			_wait_for_sound(player)
			return


func _wait_for_sound(player: AudioStreamPlayer, wait_for_completion: bool = true) -> void:
	_processing_sounds = true
	_waiting_player = player
	_waiting_for_completion = wait_for_completion
	_waiting_finished_callback = _on_waiting_sound_finished.bind(player)
	player.finished.connect(_waiting_finished_callback, CONNECT_ONE_SHOT)
	blocking_state_changed.emit(true)


func _on_waiting_sound_finished(player: AudioStreamPlayer) -> void:
	if player != _waiting_player:
		return
	_waiting_player = null
	_waiting_for_completion = false
	_waiting_finished_callback = Callable()
	_processing_sounds = false
	blocking_state_changed.emit(false)
	_drain_sound_queue()


func _next_channel() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	for offset: int in range(1, _players.size() + 1):
		var candidate := _players[(_channel_index + offset) % _players.size()]
		if not _busy_players.has(candidate):
			return candidate
	return _players[(_channel_index + 1) % _players.size()]


func _stop_playing_channels() -> void:
	var was_blocking := _processing_sounds
	set_process(false)
	_effect_seconds_remaining = 0.0
	_effect_first_frame = false
	if _waiting_player != null and _waiting_finished_callback.is_valid() and _waiting_player.finished.is_connected(_waiting_finished_callback):
		_waiting_player.finished.disconnect(_waiting_finished_callback)
	_waiting_player = null
	_waiting_for_completion = false
	_waiting_finished_callback = Callable()
	_processing_sounds = false
	_busy_players.clear()
	for player: AudioStreamPlayer in _players:
		player.stop()
	if was_blocking:
		blocking_state_changed.emit(false)
