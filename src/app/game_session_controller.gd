class_name GameSessionController
extends Node

signal step_committed(step: SessionStep)

var _session: GameSession = GameSession.new()


func session() -> GameSession:
	return _session


func replace_session(replacement: GameSession) -> void:
	assert(replacement != null, "A session replacement is required")
	_session = replacement


func submit_intent(intent: PlayerIntent) -> SessionStep:
	var step: SessionStep = _session.submit_intent(intent)
	step_committed.emit(step)
	return step


func respond(response: InteractionResponse) -> SessionStep:
	var step: SessionStep = _session.respond(response)
	step_committed.emit(step)
	return step
