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
var _progress := preload("res://src/app/session/auto_progress_monitor.gd").new()
var _pause: Callable
var _observed_session := 0


func configure(view: Callable, session_identity: Callable, blocker: Callable, submit: Callable, report_failure: Callable, pause: Callable = Callable()) -> void:
	_view = view
	_session_identity = session_identity
	_blocker = blocker
	_submit = submit
	_report_failure = report_failure
	_pause = pause


func request() -> void:
	_requested = true


func poll() -> void:
	if not _requested or _running or not _configured():
		return
	var current := _view.call() as GameView
	var session_identity := int(_session_identity.call())
	if session_identity != _observed_session:
		_progress.reset()
		_failed_revision = -1
		_observed_session = session_identity
	if current != null and current.pending_interaction != null and current.pending_interaction.kind != InteractionRequest.COMBAT:
		_progress.reset()
	_last_blocker = StringName(_blocker.call())
	if not _last_blocker.is_empty():
		return
	if current == null or current.revision == _failed_revision:
		_requested = false
		return
	var revision := current.revision
	var response := ApplicationCombatPolicy.persistent_auto_response(current)
	if response == null:
		_requested = false
		_progress.reset()
		return
	var confirmed := _view.call() as GameView
	if confirmed == null or int(_session_identity.call()) != session_identity or confirmed.revision != revision:
		return
	if _progress.before_activation(current):
		_requested = false
		if _pause.is_valid(): _pause.call("Party Auto paused after two complete rounds without progress. Choose an action or restart Auto.")
		return
	_running = true
	_requested = false
	var generation := _generation
	var step := _submit.call(response) as SessionStep
	_running = false
	if generation != _generation or int(_session_identity.call()) != session_identity:
		return
	if step == null or step.state == SessionStep.State.FAILED:
		_failed_revision = revision
		_report_failure.call(step)
		return
	_failed_revision = -1
	_progress.observe(step.events)
	_requested = true


func invalidate() -> void:
	_generation += 1
	_requested = false
	_running = false
	_failed_revision = -1
	_last_blocker = &""
	_progress.reset()


func reset_progress() -> void:
	_progress.reset()


func observation() -> Dictionary:
	var current := _view.call() as GameView if _view.is_valid() else null
	var combat := current.combat_view if current != null else null
	var active := combat != null and combat.outcome == &"active"
	return {"requested": _requested, "running": _running, "generation": _generation, "revision": current.revision if current != null else -1, "active": active, "outcome": String(combat.outcome) if combat != null else "", "actor": combat.active_actor_id if active else "", "round": combat.round_number if active else -1, "failedRevision": _failed_revision, "blocker": String(_last_blocker)}


func _configured() -> bool:
	return _view.is_valid() and _session_identity.is_valid() and _blocker.is_valid() and _submit.is_valid() and _report_failure.is_valid()
