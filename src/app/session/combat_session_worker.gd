## Resolves serial combat jobs without accessing the scene tree.
class_name CombatSessionWorker
extends RefCounted

var _thread := Thread.new()
var _mutex := Mutex.new()
var _wake := Semaphore.new()
var _pending: CombatSessionJob
var _completed: CombatSessionJob
var _stopping := false
var _occupied := false


func submit(job: CombatSessionJob) -> Error:
	if _occupied or _stopping:
		return ERR_BUSY
	if not _thread.is_started():
		var error := _thread.start(_run)
		if error != OK: return error
	_mutex.lock()
	_pending = job
	_occupied = true
	_mutex.unlock()
	_wake.post()
	return OK


func take_completed() -> CombatSessionJob:
	_mutex.lock()
	var result := _completed
	_completed = null
	if result != null: _occupied = false
	_mutex.unlock()
	return result


func close() -> void:
	_mutex.lock()
	_stopping = true
	_mutex.unlock()
	_wake.post()
	if _thread.is_started(): _thread.wait_to_finish()
	_pending = null
	_completed = null
	_occupied = false


func _run() -> void:
	while true:
		_wake.wait()
		_mutex.lock()
		var job := _pending
		_pending = null
		var stopping := _stopping
		_mutex.unlock()
		if job != null:
			job.execute()
			_mutex.lock()
			_completed = job
			_mutex.unlock()
		if stopping: return
