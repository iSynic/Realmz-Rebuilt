## Validates one detached immutable package without installing or publishing it.
class_name PackageReadTask
extends RefCounted

var _thread := Thread.new()
var _mutex := Mutex.new()
var _cancelled := false
var _result: PackageLoadResult
var _repository := PackageRepository.new()


func configure(application: RealmzContent, assets: Array[MediaAsset]) -> void:
	assert(not _thread.is_started())
	_repository.set_application_content(application, assets)


func start(path: String) -> bool:
	if _thread.is_started():
		return false
	_cancelled = false
	_result = null
	return _thread.start(_read.bind(path)) == OK


func is_running() -> bool:
	return _thread.is_started() and _thread.is_alive()


func take_result() -> PackageLoadResult:
	if not _thread.is_started() or _thread.is_alive():
		return null
	_thread.wait_to_finish()
	var result := _result
	_result = null
	return result


func shutdown() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	if _thread.is_started():
		_thread.wait_to_finish()
	_result = null
	_repository.close()


func _read(path: String) -> void:
	_result = _repository.load_package(path, Callable(), _is_cancelled)


func _is_cancelled() -> bool:
	_mutex.lock()
	var result := _cancelled
	_mutex.unlock()
	return result
