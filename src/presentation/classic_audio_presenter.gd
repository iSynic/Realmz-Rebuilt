class_name ClassicAudioPresenter
extends Node

signal sound_observed(sound_id: int)

const CHANNEL_COUNT: int = 4

var last_sound_id: int = 0
var master_volume: float = 1.0
var _players: Array[AudioStreamPlayer] = []
var _channel_index: int = -1
var _pending_sounds: Array[Dictionary] = []
var _processing_sounds: bool = false


func _ready() -> void:
	for index: int in range(CHANNEL_COUNT):
		var player := AudioStreamPlayer.new()
		player.name = "ClassicSoundChannel%d" % (index + 1)
		_players.append(player)
		add_child(player)
	_apply_volume()


func present_events(events: Array[DomainEvent], media: PackageMediaCatalog) -> void:
	for event: DomainEvent in events:
		if event.kind != &"sound_requested":
			continue
		last_sound_id = int(event.payload.get("soundId", 0))
		sound_observed.emit(last_sound_id)
		if media == null:
			continue
		var asset := media.sound_by_resource_id(last_sound_id)
		if asset == null:
			continue
		var bytes := media.read_bytes(asset)
		var stream := _decode_stream(asset, bytes)
		if stream == null:
			continue
		_pending_sounds.append({"stream": stream, "waitForCompletion": bool(event.payload.get("waitForCompletion", false))})
	_drain_sound_queue()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func _apply_volume() -> void:
	for player: AudioStreamPlayer in _players:
		player.volume_db = -80.0 if master_volume <= 0.0 else linear_to_db(master_volume)


func _drain_sound_queue() -> void:
	if _processing_sounds:
		return
	_processing_sounds = true
	while not _pending_sounds.is_empty():
		var request: Dictionary = _pending_sounds.pop_front()
		var player := _next_channel()
		if player == null:
			continue
		player.stop()
		player.stream = request["stream"] as AudioStream
		player.play()
		if bool(request["waitForCompletion"]) and player.playing:
			await player.finished
	_processing_sounds = false


func _next_channel() -> AudioStreamPlayer:
	if _players.is_empty():
		return null
	_channel_index = (_channel_index + 1) % _players.size()
	return _players[_channel_index]


func _decode_stream(asset: PackageMediaAsset, bytes: PackedByteArray) -> AudioStream:
	if bytes.is_empty():
		return null
	var mime := asset.mime_type.to_lower()
	var extension := asset.path.get_extension().to_lower()
	if mime == "audio/wav" or mime == "audio/x-wav" or extension == "wav":
		return AudioStreamWAV.load_from_buffer(bytes)
	if mime in ["audio/mpeg", "audio/mp3"] or extension == "mp3":
		return AudioStreamMP3.load_from_buffer(bytes)
	if mime in ["audio/ogg", "audio/vorbis"] or extension == "ogg":
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null
