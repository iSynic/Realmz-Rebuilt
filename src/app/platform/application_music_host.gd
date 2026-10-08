## Connects managed music storage, cancellable imports, and detached UI drafts.
class_name ApplicationMusicHost
extends Node

class Source extends RefCounted:
	var path: String
	var name: String

var _repository: MusicLibraryRepository
var _dialog: MusicPlaylistDialog
var _playback: MusicPlaybackController
var _game_view: Callable
var _job: MusicImportTask
var _pending: Array[Source] = []
var _streams: Dictionary[String, AudioStream] = {}
var _stream_order: Array[String] = []
var _completed: int = 0
var _total: int = 0
var _last_progress: String = ""


func _init(directory: String = "user://music") -> void:
	_repository = MusicLibraryRepository.new(directory)
	set_process(false)


func bind(dialog: MusicPlaylistDialog, playback: MusicPlaybackController, game_view: Callable) -> void:
	_dialog = dialog
	_playback = playback
	_game_view = game_view
	_dialog.opened.connect(_open)
	_dialog.import_requested.connect(_import)
	_dialog.import_cancelled.connect(_cancel)
	_dialog.preview_requested.connect(func(id: String) -> void: _playback.preview(id))
	_dialog.preview_stopped.connect(_playback.end_preview)
	_dialog.remove_requested.connect(_remove)
	_dialog.repair_requested.connect(_repair)
	_dialog.apply_requested.connect(_apply)
	_playback.diagnostic_changed.connect(_dialog.report)
	_refresh_library()


func _open() -> void:
	var view := _game_view.call() as GameView
	var campaign := view.campaign_id if view != null else ""
	var title := view.campaign_summary.title if view != null and view.campaign_summary != null else ""
	_dialog.present_library(MusicLibraryView.from_data(_repository.snapshot()), campaign, title)
	if not _repository.last_error.is_empty():
		_dialog.report(_repository.last_error)


func _import(paths: PackedStringArray) -> void:
	if _job != null or not _pending.is_empty():
		return
	if paths.size() > 64:
		_dialog.report("Choose no more than 64 music files per import.")
		return
	for path: String in paths:
		var source := Source.new()
		source.path = path
		source.name = path.get_file()
		_pending.append(source)
	_completed = 0
	_total = _pending.size()
	set_process(true)


func _repair(id: String) -> void:
	if _job != null or not _pending.is_empty():
		return
	var track: Dictionary = _repository.snapshot().tracks.get(id, {})
	if track.is_empty():
		return
	var source := Source.new()
	source.path = _repository.source_path(id)
	source.name = track.sourceName
	_pending.append(source)
	_completed = 0
	_total = 1
	set_process(true)


func _cancel() -> void:
	_pending.clear()
	if _job != null:
		_job.cancel()
	else:
		_dialog.set_import_status(false, "Music import cancelled.")
		set_process(false)


func _process(_delta: float) -> void:
	if _job == null:
		if _pending.is_empty():
			set_process(false)
			return
		var source := _pending.pop_front() as Source
		_job = MusicImportTask.new()
		_job.start(source.path, _repository.root, "", source.name)
	_job.poll()
	var progress := "%d / %d  •  %s" % [_completed + 1, _total, _job.message]
	if progress != _last_progress:
		_last_progress = progress
		_dialog.set_import_status(true, progress)
	if _job.state == &"running":
		return
	_finish_import()


func _finish_import() -> void:
	var message := _job.message
	if _job.state == &"succeeded":
		if _repository.accept_import(_job.records):
			for id: String in _job.records:
				_streams.erase(id)
				_stream_order.erase(id)
			var changed_tracks: Array[String] = []
			changed_tracks.assign(_job.records.keys())
			_refresh_library(changed_tracks)
		else:
			message = _repository.last_error
	_dialog.report("%s: %s" % [_job.source_name, message])
	_job.close()
	_job = null
	_completed += 1
	_dialog.set_import_status(not _pending.is_empty(), message)
	if _pending.is_empty():
		set_process(false)


func _apply(draft: MusicLibraryView) -> void:
	var success := _repository.save_preferences(draft.playlist_data(), draft.assignment_data())
	if success:
		_playback.set_library(MusicLibraryView.from_data(_repository.snapshot()), _load_track)
	_dialog.apply_result(success, _repository.last_error)


func _remove(id: String) -> void:
	if _repository.remove_track(id):
		_streams.erase(id)
		_stream_order.erase(id)
		_refresh_library()
		_dialog.report("Track removed from the library and its playlists.")
	else:
		_dialog.report(_repository.last_error)


func _refresh_library(changed_tracks: Array[String] = []) -> void:
	var library := MusicLibraryView.from_data(_repository.snapshot())
	_playback.set_library(library, _load_track, changed_tracks)
	_dialog.merge_imports(library)


func _load_track(id: String) -> AudioStream:
	if _streams.has(id):
		return _streams[id]
	var record: Dictionary = _repository.snapshot().tracks.get(id, {})
	if record.is_empty():
		return null
	var path := _repository.playback_path(id)
	var hash: String = record.cacheHash if not String(record.cacheHash).is_empty() else record.sourceHash
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != hash:
		return null
	var stream: AudioStream = AudioStreamMP3.load_from_file(path) if record.playbackFormat == "mp3" else AudioStreamOggVorbis.load_from_file(path)
	if stream != null:
		_streams[id] = stream
		_stream_order.append(id)
		if _stream_order.size() > 4:
			_streams.erase(_stream_order.pop_front())
	return stream


func _exit_tree() -> void:
	if _job != null:
		_job.close()
