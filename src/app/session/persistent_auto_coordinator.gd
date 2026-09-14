## Schedules one persistent party-Auto activation after presentation settles.
class_name PersistentAutoCoordinator
extends RefCounted

var _view: Callable
var _session_identity: Callable
var _blocker: Callable
var _submit: Callable
var _report_failure: Callable
var _requested: bool = false
var _running: bool = false
var _failed_revision: int = -1
var _last_blocker: StringName = &""


func configure(view: Callable, session_identity: Callable, blocker: Callable, submit: Callable, report_failure: Callable) -> void:
	_view = view
	_session_identity = session_identity
	_blocker = blocker
	_submit = submit
	_report_failure = report_failure


func request() -> void:
	_requested = true
	poll()


func poll() -> void:
	if not _requested or _running or not _configured():
		return
	_last_blocker = StringName(_blocker.call())
	if not _last_blocker.is_empty():
		return
	var current := _view.call() as GameView
	if current == null or current.revision == _failed_revision:
		_requested = false
		return
	if ApplicationCombatPolicy.persistent_auto_response(current) == null:
		_requested = false
		return
	_running = true
	_requested = false
	_continue_after_draw.call_deferred(int(_session_identity.call()), current.revision)


func invalidate() -> void:
	_requested = false
	_running = false
	_failed_revision = -1
	_last_blocker = &""


func observation() -> Dictionary:
	var current := _view.call() as GameView if _view.is_valid() else null
	return {"requested": _requested, "running": _running, "revision": current.revision if current != null else -1, "failedRevision": _failed_revision, "blocker": String(_last_blocker)}


func _continue_after_draw(session_identity: int, revision: int) -> void:
	if DisplayServer.get_name() == "headless":
		await (Engine.get_main_loop() as SceneTree).process_frame
	else:
		await RenderingServer.frame_post_draw
	if not _running:
		return
	var current := _view.call() as GameView
	if current == null or int(_session_identity.call()) != session_identity or current.revision != revision:
		_running = false
		poll()
		return
	_last_blocker = StringName(_blocker.call())
	if not _last_blocker.is_empty():
		_running = false
		_requested = true
		return
	var response := ApplicationCombatPolicy.persistent_auto_response(current)
	if response == null:
		_running = false
		return
	var step := _submit.call(response) as SessionStep
	_running = false
	if step == null or step.state == SessionStep.State.FAILED:
		_failed_revision = current.revision
		_requested = false
		_report_failure.call(step)
		return
	_failed_revision = -1
	poll()


func _configured() -> bool:
	return _view.is_valid() and _session_identity.is_valid() and _blocker.is_valid() and _submit.is_valid() and _report_failure.is_valid()
