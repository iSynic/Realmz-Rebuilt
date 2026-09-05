## Creates exploration-owned session continuations.

class_name ExplorationContinuations
extends RefCounted


static func post_clock(body: ExplorationContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"post-clock", body)


static func post_move(body: ExplorationContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"post-move", body)


static func boat_choice(body: BoatContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"boat-choice", body)
