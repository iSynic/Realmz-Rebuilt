## Carries one exclusive session transaction and its detached completion.
class_name CombatSessionJob
extends RefCounted

var id: int
var generation: int
var revision: int
var session: GameSession
var intent: PlayerIntent
var response: InteractionResponse
var auto_changes: Array[PlayerIntent] = []
var step: SessionStep
var view: GameView
var transaction_usec: int = 0
var projection_usec: int = 0
var publication_usec: int = 0
var deferred_projection_usec: int = 0


func execute() -> void:
	var started := Time.get_ticks_usec()
	if not auto_changes.is_empty(): step = _apply_auto_changes()
	elif intent != null: step = session.submit_intent(intent)
	else: step = session.respond(response)
	transaction_usec = Time.get_ticks_usec() - started
	if step == null:
		return
	started = Time.get_ticks_usec()
	view = session.view(step.events)
	projection_usec = Time.get_ticks_usec() - started


func _apply_auto_changes() -> SessionStep:
	var events: Array[DomainEvent] = []
	var last: SessionStep
	var failure: SessionStep
	for change: PlayerIntent in auto_changes:
		last = session.submit_intent(change)
		if last == null: return null
		events.append_array(last.events)
		if last.state == SessionStep.State.FAILED and failure == null: failure = last
	if failure != null:
		return SessionStep.failed(last.view_revision, failure.error_code, failure.error_message, events)
	last.events = events
	return last
