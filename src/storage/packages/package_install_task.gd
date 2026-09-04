## Validates and loads package install task data at the immutable package boundary.

class_name PackageInstallTask
extends RefCounted


var _thread := Thread.new()
var _repository: PackageRepository
var _mutex := Mutex.new()
var _state: StringName = PackageOperationStatus.IDLE
var _phase: StringName = &""
var _completed: int = 0
var _total: int = 0
var _message: String = ""
var _cancel_requested: bool = false
var _result: PackageInstallResult


func _init(repository: PackageRepository = null) -> void:
	_repository = repository if repository != null else PackageRepository.new()


func start(source_path: String, install_root: String = "user://packages") -> bool:
	if source_path.is_empty() or snapshot().is_running() or _thread.is_started():
		return false
	_mutex.lock()
	_state = PackageOperationStatus.RUNNING
	_phase = &"queued"
	_completed = 0
	_total = 0
	_message = "Preparing campaign…"
	_cancel_requested = false
	_result = null
	_mutex.unlock()
	var error := _thread.start(_run_install.bind(source_path, install_root))
	if error == OK:
		return true
	_mutex.lock()
	_state = PackageOperationStatus.FAILED
	_message = "Could not start campaign preparation (error %d)." % error
	_mutex.unlock()
	return false


func cancel() -> void:
	_mutex.lock()
	if _state == PackageOperationStatus.RUNNING:
		_cancel_requested = true
		_message = "Cancelling after the current integrity item…"
	_mutex.unlock()


func snapshot() -> RefCounted:
	_mutex.lock()
	var result := PackageOperationStatus.new(_state, _phase, _completed, _total, _message)
	_mutex.unlock()
	return result


func take_result() -> PackageInstallResult:
	var current := snapshot()
	if current.is_running() or current.state == PackageOperationStatus.IDLE:
		return null
	_join_thread()
	_mutex.lock()
	var result := _result
	_result = null
	_state = PackageOperationStatus.IDLE
	_phase = &""
	_completed = 0
	_total = 0
	_message = ""
	_mutex.unlock()
	return result


func shutdown() -> void:
	cancel()
	_join_thread()


func _run_install(source_path: String, install_root: String) -> void:
	var result := _repository.install_package(source_path, install_root, _on_progress, _is_cancel_requested)
	_mutex.lock()
	_result = result
	if result != null and result.is_ok():
		_state = PackageOperationStatus.SUCCEEDED
		_phase = &"complete"
		_completed = 1
		_total = 1
		_message = "Campaign ready."
	elif result != null and result.error_code == &"package_cancelled":
		_state = PackageOperationStatus.CANCELLED
		_message = "Campaign preparation cancelled."
	else:
		_state = PackageOperationStatus.FAILED
		_message = result.error_message if result != null else "Campaign preparation failed."
	_mutex.unlock()


func _on_progress(operation_phase: StringName, completed_units: int, total_units: int) -> void:
	_mutex.lock()
	_phase = operation_phase
	_completed = completed_units
	_total = total_units
	if not _cancel_requested:
		_message = _message_for(operation_phase, completed_units, total_units)
	_mutex.unlock()


func _is_cancel_requested() -> bool:
	_mutex.lock()
	var requested := _cancel_requested
	_mutex.unlock()
	return requested


func _join_thread() -> void:
	if _thread.is_started():
		_thread.wait_to_finish()


static func _message_for(operation_phase: StringName, completed_units: int, total_units: int) -> String:
	match operation_phase:
		&"opening": return "Opening campaign package…"
		&"checking-install": return "Opening installed campaign…"
		&"restoring-runtime-image": return "Restoring verified campaign data…"
		&"validating-source": return "Checking external package before installation…"
		&"validating-integrity": return "Checking external package files %d of %d…" % [completed_units, total_units]
		&"reading-documents": return "Reading compiled Realmz content %d of %d…" % [completed_units, total_units]
		&"constructing-content": return "Loading compiled Realmz content…"
		&"copying-package": return "Installing immutable package…"
		&"validating-install": return "Checking installed copy…"
		&"complete": return "Campaign ready."
	return "Preparing campaign…"
