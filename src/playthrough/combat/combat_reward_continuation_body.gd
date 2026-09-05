## Carries one battle reward workflow and its scenario return point.

class_name CombatRewardContinuationBody
extends SessionContinuationBody

var battle_id: String
var runtime_continuation: ScenarioRuntimeContinuation


func wire_payload(kind: StringName) -> Dictionary:
	return {"kind": String(kind), "battleId": battle_id, "runtimeContinuation": {} if runtime_continuation == null else runtime_continuation.to_data()}
