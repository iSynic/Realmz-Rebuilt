class_name ClassicAudioPresenter
extends Node

signal sound_observed(sound_id: int)

const CHANNEL_COUNT: int = 4

var last_sound_id: int = 0
var master_volume: float = 1.0
var last_media_diagnostic: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _channel_index: int = -1
var _pending_sounds: Array[Dictionary] = []
var _processing_sounds: bool = false
var _waiting_player: AudioStreamPlayer
var _waiting_finished_callback: Callable


func _ready() -> void:
	for index: int in range(CHANNEL_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "ClassicSoundChannel%d" % (index + 1)
		_players.append(player)
		add_child(player)
	_apply_volume()


func present_events(events: Array[DomainEvent], media: ClassicMediaCatalog) -> void:
	for event: DomainEvent in events:
		if event.kind != &"sound_requested":
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


func present_sound(sound_id: int, media: ClassicMediaCatalog, wait_for_completion: bool = false, stop_existing: bool = false) -> void:
	present_events([DomainEvent.new(&"sound_requested", {"soundId": sound_id, "waitForCompletion": wait_for_completion, "stopExisting": stop_existing, "source": "classic-presentation-workspace"})], media)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func _apply_volume() -> void:
	for player: AudioStreamPlayer in _players:
		player.volume_db = -80.0 if master_volume <= 0.0 else linear_to_db(master_volume)


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
	_drain_sound_queue()


func _next_channel() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	_channel_index = (_channel_index + 1) % _players.size()
	return _players[_channel_index]


func _stop_all() -> void:
	if _waiting_player != null and _waiting_finished_callback.is_valid() and _waiting_player.finished.is_connected(_waiting_finished_callback):
		_waiting_player.finished.disconnect(_waiting_finished_callback)
	_waiting_player = null
	_waiting_finished_callback = Callable()
	_processing_sounds = false
	_pending_sounds.clear()
	for player: AudioStreamPlayer in _players:
		player.stop()
