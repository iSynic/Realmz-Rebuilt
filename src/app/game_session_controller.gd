class_name GameSessionController
extends Node

signal step_committed(step: SessionStep)

var _session: GameSession = GameSession.new()
var _current_view: GameView = _session.view()
var _map_projection_size: Vector2i = SessionViewProjector.DEFAULT_MAP_VIEW_SIZE


func session() -> GameSession:
	return _session


func view() -> GameView:
	return _current_view


func set_map_projection_size(requested_size: Vector2i) -> bool:
	var normalized := Vector2i(maxi(requested_size.x, 1), maxi(requested_size.y, 1))
	if normalized == _map_projection_size:
		return false
	_map_projection_size = normalized
	_session.set_map_projection_size(normalized)
	_current_view = _session.view()
	return true


func replace_session(replacement: GameSession) -> void:
	assert(replacement != null, "A session replacement is required")
	_session = replacement
	_session.set_map_projection_size(_map_projection_size)
	_current_view = _session.view()


func start(content: RealmzContent, initial_seed: int) -> SessionStep:
	var replacement := GameSession.new()
	var step := replacement.start(content, initial_seed)
	if step.state != SessionStep.State.FAILED:
		replace_session(replacement)
	step_committed.emit(step)
	return step


func restore(content: RealmzContent, envelope: SessionSnapshot) -> SessionStep:
	var replacement := GameSession.new()
	var step := replacement.restore(content, envelope)
	if step.state != SessionStep.State.FAILED:
		replace_session(replacement)
	step_committed.emit(step)
	return step


func close() -> SessionStep:
	var step := _session.close()
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func submit_intent(intent: PlayerIntent) -> SessionStep:
	var step: SessionStep = _session.submit_intent(intent)
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func apply_debug_command(command: SessionDebugCommand) -> SessionStep:
	var step := _session.apply_debug_command(command)
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step


func respond(response: InteractionResponse) -> SessionStep:
	var step: SessionStep = _session.respond(response)
	_current_view = _session.view(step.events)
	step_committed.emit(step)
	return step
