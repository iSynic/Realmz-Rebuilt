## Prepares immutable scenario tracks in a separate presentation cache.
class_name ScenarioMusicHost
extends Node

class Source extends RefCounted:
	var asset: MediaAsset
	var media: MediaSource

var _repository: MusicLibraryRepository
var _helper_root: String
var _playback: MusicPlaybackController
var _job: MusicImportTask
var _source: Source
var _pending: Source
var _attempted: Dictionary[String, bool] = {}
var _streams: Dictionary[String, AudioStream] = {}
var _stream_order: Array[String] = []


func _init(directory: String = "user://scenario-music", helper_root: String = "") -> void:
	_repository = MusicLibraryRepository.new(directory)
	_helper_root = helper_root
	set_process(false)


func bind(playback: MusicPlaybackController) -> void:
	_playback = playback
	_playback.set_scenario_loader(request)


func request(asset: MediaAsset, media: MediaSource) -> AudioStream:
	var hash := asset.sha256
	if _streams.has(hash):
		return _streams[hash]
	var stream := _cached_stream(hash)
	if stream != null:
		return stream
	if _attempted.has(hash) or _source != null and _source.asset.sha256 == hash:
		return null
	if _pending == null or _pending.asset.sha256 != hash:
		_pending = Source.new()
		_pending.asset = asset
		_pending.media = media
	set_process(true)
	return null


func _process(_delta: float) -> void:
	if _job == null:
		if _pending == null:
			set_process(false)
			return
		_source = _pending
		_pending = null
		_attempted[_source.asset.sha256] = true
		_job = MusicImportTask.new()
		_job.start_packaged(_source.asset, _source.media, _repository.root, _helper_root)
	_job.poll()
	if _job.state == &"running":
		return
	var stream: AudioStream
	var error := _job.message
	var hash := _source.asset.sha256
	if _job.state == &"succeeded" and _job.records.has(hash + ":0"):
		if _repository.accept_import(_job.records):
			stream = _cached_stream(hash)
			error = "The decoded scenario music could not be loaded."
		else:
			error = _repository.last_error
	if stream == null:
		_playback.diagnostic_changed.emit("Scenario music unavailable (%s): %s" % [_source.asset.label, error])
	_job.close()
	_job = null
	_source = null
	if stream != null:
		_playback.scenario_music_ready(hash, stream)
	set_process(_pending != null)


func _cached_stream(hash: String) -> AudioStream:
	var id := hash + ":0"
	var record: Dictionary = _repository.snapshot().tracks.get(id, {})
	if record.is_empty():
		return null
	var path := _repository.playback_path(id)
	var audio_hash: String = record.cacheHash if not String(record.cacheHash).is_empty() else hash
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != audio_hash:
		return null
	var stream: AudioStream = AudioStreamMP3.load_from_file(path) if record.playbackFormat == "mp3" else AudioStreamOggVorbis.load_from_file(path)
	if stream != null:
		_streams[hash] = stream
		_stream_order.append(hash)
		if _stream_order.size() > 4:
			_streams.erase(_stream_order.pop_front())
	return stream


func _exit_tree() -> void:
	if _job != null:
		_job.close()
