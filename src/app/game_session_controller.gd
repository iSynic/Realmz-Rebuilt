class_name GameSessionController
extends Node

signal step_committed(step: SessionStep)

var _session: GameSession = GameSession.new()


func session() -> GameSession:
	return _session


func replace_session(replacement: GameSession) -> void:
	assert(replacement != null, "A session replacement is required")
	_session = replacement


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	var replacement := GameSession.new()
	var step := replacement.start(content, initial_seed)
	if step.state != SessionStep.State.FAILED:
		replace_session(replacement)
	step_committed.emit(step)
	return step


func restore(content: RealmzContent, envelope: SaveEnvelope) -> SessionStep:
	var replacement := GameSession.new()
	var step := replacement.restore(content, envelope)
	if step.state != SessionStep.State.FAILED:
		replace_session(replacement)
	step_committed.emit(step)
	return step


func submit_intent(intent: PlayerIntent) -> SessionStep:
	var step: SessionStep = _session.submit_intent(intent)
	step_committed.emit(step)
	return step


func respond(response: InteractionResponse) -> SessionStep:
	var step: SessionStep = _session.respond(response)
	step_committed.emit(step)
	return step
