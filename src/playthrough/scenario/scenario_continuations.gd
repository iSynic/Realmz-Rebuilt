## Creates scenario application-hook session continuations.

class_name ScenarioContinuations
extends RefCounted


static func application_hook(body: ScenarioApplicationContinuationBody) -> SessionContinuation:
	return SessionContinuation.new(&"application-hook", body)
