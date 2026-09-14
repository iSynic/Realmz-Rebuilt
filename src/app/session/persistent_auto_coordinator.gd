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
var _generation: int = 0
var _failed_revision: int = -1
var _last_blocker: StringName = &""


func configure(view: Callable, session_identity: Callable, blocker: Callable, submit: Callable, report_failure: Callable) -> void:
	_view = view
	_session_identity = session_identity
	_blocker = blocker
	_submit = submit
	_report_failure = report_failure


func request() -> void:
	if not _requested:
		_generation += 1
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
	var session_identity := int(_session_identity.call())
	var revision := current.revision
	var response := ApplicationCombatPolicy.persistent_auto_response(current)
	if response == null:
		_requested = false
		return
	var confirmed := _view.call() as GameView
	if confirmed == null or int(_session_identity.call()) != session_identity or confirmed.revision != revision:
		return
	_running = true
	_requested = false
	var step := _submit.call(response) as SessionStep
	_running = false
	if step == null or step.state == SessionStep.State.FAILED:
		_failed_revision = revision
		_report_failure.call(step)
		return
	_failed_revision = -1
	request()


func invalidate() -> void:
	_generation += 1
	_requested = false
	_running = false
	_failed_revision = -1
	_last_blocker = &""


func observation() -> Dictionary:
	var current := _view.call() as GameView if _view.is_valid() else null
	var combat := current.combat_view if current != null else null
	return {"requested": _requested, "running": _running, "generation": _generation, "revision": current.revision if current != null else -1, "actor": combat.active_actor_id if combat != null else "", "round": combat.round_number if combat != null else -1, "failedRevision": _failed_revision, "blocker": String(_last_blocker)}


func _configured() -> bool:
	return _view.is_valid() and _session_identity.is_valid() and _blocker.is_valid() and _submit.is_valid() and _report_failure.is_valid()
