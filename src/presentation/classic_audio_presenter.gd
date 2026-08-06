class_name ClassicAudioPresenter
extends Node

signal sound_observed(sound_id: int)

var last_sound_id: int = 0
var master_volume: float = 1.0
var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	add_child(_player)
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
		_player.stream = stream
		_player.play()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume()


func _apply_volume() -> void:
	if _player != null:
		_player.volume_db = -80.0 if master_volume <= 0.0 else linear_to_db(master_volume)


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
