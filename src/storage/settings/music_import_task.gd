## Owns a cancellable copy/decode/install job without blocking the application frame loop.
class_name MusicImportTask
extends RefCounted

var state: StringName = &"idle"
var message: String = ""
var records: Dictionary = {}
var source_name: String = ""
var _root: String
var _job: String
var _thread: Thread
var _phase: StringName
var _pid: int = -1
var _started: int = 0
var _prepared: Dictionary = {}
var _mutex := Mutex.new()
var _cancelled: bool = false


func start(source: String, library_root: String, helper_root: String = "", display_name: String = "") -> bool:
	return _start(source, library_root, helper_root, display_name)


func start_packaged(asset: MediaAsset, media: MediaSource, cache_root: String, helper_root: String = "") -> bool:
	return _start(asset.path, cache_root, helper_root, asset.label, asset, media)


func _start(source: String, library_root: String, helper_root: String, display_name: String, asset: MediaAsset = null, media: MediaSource = null) -> bool:
	if state != &"idle":
		return false
	_root = ProjectSettings.globalize_path(library_root)
	_job = _root.path_join("staging/import-" + Crypto.new().generate_random_bytes(12).hex_encode())
	source_name = display_name if not display_name.is_empty() else source.get_file()
	var helper := helper_root
	if helper.is_empty():
		helper = ProjectSettings.globalize_path("res://music-importer") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("music-importer")
	state = &"running"
	message = "Copying and checking %s…" % source_name
	_phase = &"preparing"
	_thread = Thread.new()
	var prepare := MusicImportFiles.prepare.bind(ProjectSettings.globalize_path(source), _job, helper, is_cancelled)
	if asset != null:
		prepare = MusicImportFiles.prepare_packaged.bind(asset, media, _job, helper, is_cancelled)
	if _thread.start(prepare) != OK:
		_thread = null
		_fail("Could not start the music import worker.")
		return false
	return true


func poll() -> void:
	if _thread != null:
		if _thread.is_alive():
			return
		var result: Dictionary = _thread.wait_to_finish()
		_thread = null
		if is_cancelled():
			_complete_cancel()
			return
		if result.has("error"):
			_fail(String(result.error))
			return
		if _phase == &"preparing":
			_begin_decoder(result)
		else:
			records = result.tracks
			state = &"succeeded"
			message = "Imported %s" % source_name
		return
	if _pid <= 0:
		return
	if OS.is_process_running(_pid):
		if not is_cancelled() and Time.get_ticks_msec() - _started > 120000:
			message = "Music conversion exceeded its two-minute time limit."
			cancel()
		return
	_pid = -1
	if is_cancelled():
		_complete_cancel()
		return
	_phase = &"finishing"
	message = "Checking playback and installing %s…" % source_name
	_thread = Thread.new()
	if _thread.start(MusicImportFiles.finalize.bind(_job, _root, String(_prepared.hash), source_name, String(_prepared.converter), is_cancelled)) != OK:
		_thread = null
		_fail("Could not validate the converted music.")


func cancel() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)


func is_cancelled() -> bool:
	_mutex.lock()
	var value := _cancelled
	_mutex.unlock()
	return value


func close() -> void:
	if state == &"running":
		cancel()
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
		return
	MusicImportFiles.remove_job(_job)
	_job = ""


func _begin_decoder(prepared: Dictionary) -> void:
	_prepared = prepared
	_pid = OS.create_process(String(prepared.executable), PackedStringArray(["--input", _job.path_join("source"), "--output", _job.path_join("audio"), "--name", source_name.get_basename(), "--result", _job.path_join("result.json")]), false)
	if _pid <= 0:
		_fail("Could not launch the bundled music importer.")
		return
	_started = Time.get_ticks_msec()
	message = "Decoding %s…" % source_name
	_phase = &"decoding"


func _fail(error: String) -> void:
	state = &"failed"
	message = error
	MusicImportFiles.remove_job(_job)
	_job = ""


func _complete_cancel() -> void:
	state = &"cancelled"
	message = "Music import cancelled." if not message.contains("time limit") else message
	MusicImportFiles.remove_job(_job)
	_job = ""
