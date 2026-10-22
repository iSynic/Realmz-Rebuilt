## Retains the guarded scripted fumble while its authored text is acknowledged.
class_name ScenarioFumbleContinuationBody
extends ScenarioRuntimeContinuationBody

var battle_id: String
var actor_id: String
var message_id: int
var context: ScenarioExecutionContext = ScenarioExecutionContext.empty()


func wire_payload() -> Dictionary:
	return {"battleId": battle_id, "actorId": actor_id, "messageId": message_id, "context": ScenarioExecutionContextCodec.encode(context)}
