## Creates economy and service session continuations.

class_name ServiceContinuations
extends RefCounted


static func interaction(service_id: String, runtime_continuation: ScenarioRuntimeContinuation) -> SessionContinuation:
	var body := ServiceContinuationBody.new()
	body.service_id = service_id
	body.runtime_continuation = runtime_continuation.copy() if runtime_continuation != null else null
	return SessionContinuation.new(&"service-interaction", body)


static func pooled_wealth_departure(stage: StringName, direction: Vector2i) -> SessionContinuation:
	var body := ServiceContinuationBody.new()
	body.stage = stage
	body.direction = direction
	return SessionContinuation.new(&"pooled-wealth-departure", body)
