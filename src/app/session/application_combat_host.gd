## Coordinates asynchronous combat, queued Auto changes and committed feedback.
class_name ApplicationCombatHost
extends RefCounted

var continuation := PersistentAutoCoordinator.new()
var _session: GameSessionController
var _presentation: PresentationCoordinator
var _shell: GameShell
var _interaction: CombatInteractionController
var _present_status: Callable
var _lifecycle_pending: Callable
var _queued_auto: Dictionary = {}
var _inflight_auto: Dictionary = {}
var _flushing := false
var _skip_after_completion := false
var _started_usec := 0
var _activity_shown := false
var _journal_count := 0


func configure(session: GameSessionController, presentation: PresentationCoordinator, shell: GameShell, interaction: CombatInteractionController, blocker: Callable, present_status: Callable, lifecycle_pending: Callable) -> void:
	_session = session
	_presentation = presentation
	_shell = shell
	_interaction = interaction
	_present_status = present_status
	_lifecycle_pending = lifecycle_pending
	_session.combat_work_completed.connect(_complete)
	continuation.configure(_session.view, _session.session_identity, func() -> StringName:
		if _session.is_busy(): return &"combat-resolution"
		if not _queued_auto.is_empty(): return &"queued-auto-change"
		return StringName(blocker.call()), enqueue_response, func(step: SessionStep) -> void:
		var detail := step.error_message if step != null and not step.error_message.is_empty() else "The automatic activation did not commit."
		_shell.status.set_status("Party Auto paused • %s" % detail, true), func(reason: String) -> void:
		abort_auto(false)
		_shell.status.set_status(reason, true)
	)


func resolves_combat() -> bool:
	var view := _session.view()
	return view.combat_view != null and view.combat_view.outcome == &"active"


func enqueue_intent(intent: PlayerIntent) -> CombatSubmission:
	var submission := _session.enqueue_intent(intent)
	var change := ApplicationCombatPolicy.auto_change_to_queue(intent, true)
	if submission.accepted() and not change.is_empty():
		_inflight_auto[String(change["characterId"])] = bool(change["enabled"])
	_started(submission)
	return submission


func enqueue_response(response: InteractionResponse) -> CombatSubmission:
	var view := _session.view()
	if response != null and view.pending_interaction == null and view.combat_action_request != null and response.request_id == view.combat_action_request.request_id and response.kind == InteractionRequest.COMBAT:
		return enqueue_intent(ApplicationCombatPolicy.direct_intent(response.body as InteractionResponse.CombatBody))
	var submission := _session.enqueue_response(response)
	var body := response.body as InteractionResponse.CombatBody if response != null else null
	if submission.accepted() and body != null and body.action == &"set_auto":
		_inflight_auto[body.actor_id] = body.enabled
	_started(submission)
	return submission


func poll() -> void:
	if _session.is_busy() and not _activity_shown and Time.get_ticks_usec() - _started_usec >= 150_000:
		_activity_shown = true
		if _queued_auto.is_empty(): _shell.status.set_status("Resolving combat…")
	if _skip_after_completion or not _presentation.is_combat_playback_active(): flush_auto()
	continuation.poll()


func queue_auto(intent: PlayerIntent) -> bool:
	if intent == null or intent.kind != PlayerIntent.Kind.SET_COMBAT_AUTO: return false
	continuation.reset_progress()
	var change := ApplicationCombatPolicy.auto_change_to_queue(intent, _session.is_busy() or _presentation.is_combat_playback_active())
	if change.is_empty(): return false
	_queued_auto[String(change["characterId"])] = bool(change["enabled"])
	_shell.status.set_status("Manual control queued after this Auto activation." if not bool(change["enabled"]) else "Auto queued after this activation.")
	if not bool(change["enabled"]):
		_skip_after_completion = _session.is_busy()
		_presentation.skip_combat_playback()
	return true


func abort_auto(skip_playback: bool) -> bool:
	var changes := _inflight_auto.duplicate()
	changes.merge(_queued_auto, true)
	var ids := ApplicationCombatPolicy.auto_abort_ids(_session.view(), changes)
	if ids.is_empty(): return false
	for id: String in ids: _queued_auto[id] = false
	_shell.status.set_status("Full-party Auto cancelled. Manual control resumes at the next activation.")
	_skip_after_completion = _session.is_busy()
	if skip_playback: _presentation.skip_combat_playback()
	else: flush_auto()
	return true


func flush_auto() -> void:
	if _queued_auto.is_empty() or _session.is_busy() or _session.resolution_failed or _flushing: return
	if _lifecycle_pending.is_valid() and bool(_lifecycle_pending.call()): return
	_flushing = true
	var changes: Dictionary = {}
	var ids: Array[String] = []
	ids.assign(_queued_auto.keys())
	ids.sort()
	var intents: Array[PlayerIntent] = []
	for id: String in ids:
		var enabled := bool(_queued_auto[id])
		changes[id] = enabled
		_queued_auto.erase(id)
		intents.append(CombatIntents.set_auto(id, enabled))
		# Enabling the current character can execute an entire activation.
		if enabled: break
	if not intents.is_empty():
		var submission := _session.enqueue_auto_changes(intents)
		if submission.accepted(): _inflight_auto = changes
		_started(submission)
		if not submission.accepted(): _present_status.call(submission.rejection)
	_flushing = false


func invalidate() -> void:
	continuation.invalidate()
	_queued_auto.clear()
	_inflight_auto.clear()
	_skip_after_completion = false


func release() -> void:
	invalidate()
	_lifecycle_pending = Callable()
	continuation.configure(Callable(), Callable(), Callable(), Callable(), Callable())


func _started(submission: CombatSubmission) -> void:
	if not submission.accepted(): return
	_started_usec = Time.get_ticks_usec()
	_activity_shown = false
	_journal_count = _session.view().journal_entries.size()
	_interaction.resolution_pending = true


func _complete(job: CombatSessionJob) -> void:
	_inflight_auto.clear()
	_interaction.resolution_pending = false
	_present_status.call(job.step)
	if job.step.state != SessionStep.State.FAILED and _session.view().journal_entries.size() > _journal_count:
		_shell.status.show_activity_indicator(&"journal")
	continuation.complete(job.id, job.step)
	if _skip_after_completion:
		if not _queued_auto.is_empty():
			return
		_skip_after_completion = false
		_presentation.skip_combat_playback()
