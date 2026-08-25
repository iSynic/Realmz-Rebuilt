class_name BundledPackageLoadTask
extends RefCounted

const PackageRepositoryScript := preload("res://src/infrastructure/packages/package_repository.gd")

var _thread := Thread.new()
var _mutex := Mutex.new()
var _running := false
var _finished := false
var _result: PackageLoadResult


func start(path: String, campaign_id: String, package_hash: String) -> bool:
	_mutex.lock()
	if _running or _finished or _thread.is_started():
		_mutex.unlock()
		return false
	_running = true
	_mutex.unlock()
	if _thread.start(_run.bind(path, campaign_id, package_hash)) == OK:
		return true
	_mutex.lock()
	_running = false
	_finished = true
	_result = PackageLoadResult.failed(&"package_thread_failed", "Could not start built-in library loading.")
	_mutex.unlock()
	return false


func is_running() -> bool:
	_mutex.lock()
	var value := _running
	_mutex.unlock()
	return value


func has_result() -> bool:
	_mutex.lock()
	var value := _finished
	_mutex.unlock()
	return value


func take_result() -> PackageLoadResult:
	if not has_result():
		return null
	_join_thread()
	_mutex.lock()
	var value := _result
	_result = null
	_finished = false
	_mutex.unlock()
	return value


func shutdown() -> void:
	_join_thread()


func _run(path: String, campaign_id: String, package_hash: String) -> void:
	var repository := PackageRepositoryScript.new()
	var loaded := repository.load_bundled_package(path, campaign_id, package_hash)
	repository.close()
	_mutex.lock()
	_result = loaded
	_running = false
	_finished = true
	_mutex.unlock()


func _join_thread() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()
