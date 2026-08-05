class_name GameSession
extends RefCounted

var _started: bool = false
var _view_revision: int = 0
var _pending_interaction: InteractionRequest


func start(_content: Variant, _seed: int) -> SessionStep:
	if _started:
		return SessionStep.failed(_view_revision, "session_already_started", "The session has already started.")
	_started = true
	_view_revision += 1
	return SessionStep.completed(_view_revision)


func restore(_content: Variant, _save_envelope: Variant) -> SessionStep:
	_started = true
	_view_revision += 1
	return SessionStep.completed(_view_revision)


func submit_intent(intent: PlayerIntent) -> SessionStep:
	if not _started:
		return SessionStep.failed(_view_revision, "session_not_started", "Start or restore the session first.")
	if _pending_interaction != null:
		return SessionStep.failed(_view_revision, "interaction_pending", "Respond to the pending interaction first.")
	if intent == null:
		return SessionStep.failed(_view_revision, "invalid_intent", "A typed player intent is required.")
	_view_revision += 1
	return SessionStep.completed(_view_revision)


func respond(response: InteractionResponse) -> SessionStep:
	if _pending_interaction == null:
		return SessionStep.failed(_view_revision, "no_interaction_pending", "There is no interaction to resume.")
	if response == null or response.request_id != _pending_interaction.request_id:
		return SessionStep.failed(_view_revision, "interaction_mismatch", "The response does not match the pending request.")
	_pending_interaction = null
	_view_revision += 1
	return SessionStep.completed(_view_revision)


func view() -> GameView:
	return GameView.new(_view_revision, _started, _pending_interaction)


func snapshot() -> Dictionary:
	var pending_data: Variant = null
	if _pending_interaction != null:
		pending_data = _pending_interaction.to_data()
	return {
		"view_revision": _view_revision,
		"started": _started,
		"pending_interaction": pending_data,
	}
