## Coordinates game session controller within application startup and host integration.

class_name GameSessionController
extends Node

signal step_committed(step: SessionStep)
signal intent_submitted(intent: PlayerIntent)
signal response_submitted(response: InteractionResponse)
signal combat_work_completed(job: CombatSessionJob)

var _session: GameSession = GameSession.new()
var _current_view: GameView = _session.view()
var _map_projection_size: Vector2i = SessionViewProjector.DEFAULT_MAP_VIEW_SIZE
var _worker := CombatSessionWorker.new()
var _pending: CombatSessionJob
var _generation := 0
var _next_job_id := 1
var _projection_pending := false
var _replacement_pending: GameSession
var resolution_failed := false


func _init() -> void:
	step_committed.connect(_log_scenario_fault)


func _log_scenario_fault(step: SessionStep) -> void:
	for event: DomainEvent in step.events:
		if event.kind == &"scenario_runtime_faulted":
			printerr("Scenario runtime fault: " + JSON.stringify(event.payload))


func session() -> GameSession:
	return null if is_busy() or resolution_failed else _session


func session_identity() -> int:
	return _session.get_instance_id()


func is_busy() -> bool:
	return _pending != null


func view() -> GameView:
	return _current_view


func set_map_projection_size(requested_size: Vector2i) -> bool:
	var normalized := Vector2i(maxi(requested_size.x, 1), maxi(requested_size.y, 1))
	if normalized == _map_projection_size:
		return false
	_map_projection_size = normalized
	if is_busy() or resolution_failed:
		_projection_pending = true
		return false
	_session.set_map_projection_size(normalized)
	_current_view = _session.view()
	return true


func replace_session(replacement: GameSession) -> void:
	assert(replacement != null, "A session replacement is required")
	if is_busy():
		_replacement_pending = replacement
		return
	_generation += 1
	resolution_failed = false
	_session = replacement
	_session.set_map_projection_size(_map_projection_size)
	_projection_pending = false
	_current_view = _session.view()


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	if is_busy(): return _busy_step()
	var replacement := GameSession.new()
	var step := replacement.start(content, initial_seed)
	if step.state != SessionStep.State.FAILED:
		replace_session(replacement)
	step_committed.emit(step)
	return step


func restore(content: RealmzContent, envelope: SessionSnapshot) -> SessionStep:
	if is_busy(): return _busy_step()
	var replacement := GameSession.new()
	var step := replacement.restore(content, envelope)
	if step.state != SessionStep.State.FAILED:
		replace_session(replacement)
	step_committed.emit(step)
	return step


func close() -> SessionStep:
	if is_busy(): return _busy_step()
	var step: SessionStep
	if resolution_failed:
		replace_session(GameSession.new())
		step = SessionStep.completed(_current_view.revision)
	else:
		step = _session.close()
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if is_busy() or resolution_failed: return _busy_step()
	intent_submitted.emit(intent)
	var step: SessionStep = _session.submit_intent(intent)
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func apply_debug_command(command: SessionDebugCommand) -> SessionStep:
	if is_busy() or resolution_failed: return _busy_step()
	var step := _session.apply_debug_command(command)
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func respond(response: InteractionResponse) -> SessionStep:
	if is_busy() or resolution_failed: return _busy_step()
	response_submitted.emit(response)
	var step: SessionStep = _session.respond(response)
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func enqueue_intent(intent: PlayerIntent) -> CombatSubmission:
	if is_busy() or resolution_failed: return CombatSubmission.rejected(_busy_step())
	var job := _new_job()
	job.intent = intent
	var result := _enqueue(job)
	return result


func enqueue_response(response: InteractionResponse) -> CombatSubmission:
	if is_busy() or resolution_failed: return CombatSubmission.rejected(_busy_step())
	var job := _new_job()
	job.response = response
	var result := _enqueue(job)
	return result


func poll_combat_work() -> void:
	var job := _worker.take_completed()
	if job == null: return
	var publication_started := Time.get_ticks_usec()
	if job != _pending or job.generation != _generation or job.revision != _current_view.revision:
		job.step = null
		job.view = null
	_pending = null
	if job.step == null or job.view == null:
		resolution_failed = true
		job.step = SessionStep.failed(_current_view.revision, &"combat_worker_failed", "Combat resolution did not return a complete transaction.")
	else:
		_current_view = job.view
	if _projection_pending and not resolution_failed:
		var projection_started := Time.get_ticks_usec()
		_projection_pending = false
		_session.set_map_projection_size(_map_projection_size)
		_current_view = _session.view()
		job.deferred_projection_usec = Time.get_ticks_usec() - projection_started
	step_committed.emit(job.step)
	combat_work_completed.emit(job)
	if _replacement_pending != null:
		var replacement := _replacement_pending
		_replacement_pending = null
		replace_session(replacement)
	job.publication_usec = Time.get_ticks_usec() - publication_started


func enqueue_auto_changes(changes: Array[PlayerIntent]) -> CombatSubmission:
	if is_busy() or resolution_failed: return CombatSubmission.rejected(_busy_step())
	if changes.is_empty() or changes.any(func(change: PlayerIntent) -> bool: return change == null or change.kind != PlayerIntent.Kind.SET_COMBAT_AUTO or not change.payload is CombatIntentPayloads.Auto):
		return CombatSubmission.rejected(SessionStep.failed(_current_view.revision, &"invalid_auto_changes", "An Auto batch requires roster toggle commands."))
	if changes.filter(func(change: PlayerIntent) -> bool: return (change.payload as CombatIntentPayloads.Auto).enabled).size() > 1:
		return CombatSubmission.rejected(SessionStep.failed(_current_view.revision, &"invalid_auto_changes", "An Auto batch can enable only one character before yielding."))
	var job := _new_job()
	job.auto_changes = changes.duplicate()
	return _enqueue(job)


func shutdown_worker() -> void:
	_worker.close()
	_pending = null
	_replacement_pending = null


func _exit_tree() -> void:
	shutdown_worker()


func _new_job() -> CombatSessionJob:
	var job := CombatSessionJob.new()
	job.id = _next_job_id
	job.generation = _generation
	job.revision = _current_view.revision
	job.session = _session
	return job


func _enqueue(job: CombatSessionJob) -> CombatSubmission:
	if job.intent == null and job.response == null and job.auto_changes.is_empty():
		return CombatSubmission.rejected(SessionStep.failed(_current_view.revision, &"invalid_combat_submission", "A combat command is required."))
	_pending = job
	if not job.auto_changes.is_empty():
		for change: PlayerIntent in job.auto_changes: intent_submitted.emit(change)
	elif job.intent != null: intent_submitted.emit(job.intent)
	else: response_submitted.emit(job.response)
	var error := _worker.submit(job)
	if error != OK:
		_pending = null
		return CombatSubmission.rejected(SessionStep.failed(_current_view.revision, &"combat_worker_unavailable", "The combat worker could not accept the command (%d)." % error))
	_next_job_id += 1
	return CombatSubmission.queued(job.id)


func _busy_step() -> SessionStep:
	if resolution_failed:
		return SessionStep.failed(_current_view.revision, &"combat_worker_failed", "Combat resolution failed. Load a saved adventure or return to the main menu.")
	return SessionStep.failed(_current_view.revision, &"combat_transaction_pending", "Wait for the current combat activation to finish.")
