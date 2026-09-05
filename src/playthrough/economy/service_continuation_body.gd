## Carries one service interaction or pooled-wealth departure choice.

class_name ServiceContinuationBody
extends SessionContinuationBody

var service_id: String
var runtime_continuation: ScenarioRuntimeContinuation
var stage: StringName
var direction: Vector2i


func wire_payload(kind: StringName) -> Dictionary:
	if kind == &"pooled-wealth-departure":
		return {"kind": String(kind), "stage": String(stage), "directionX": direction.x, "directionY": direction.y}
	return {"kind": String(kind), "serviceId": service_id, "runtimeContinuation": {} if runtime_continuation == null else runtime_continuation.to_data()}
