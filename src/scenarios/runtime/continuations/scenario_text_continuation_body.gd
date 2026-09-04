## Carries a Classic textbox message or acquired player-map identity.

class_name ScenarioTextContinuationBody
extends ScenarioRuntimeContinuationBody

var message_id: int
var player_map_id: String


func wire_payload() -> Dictionary:
	if not player_map_id.is_empty():
		return {"playerMapId": player_map_id}
	return {"messageId": message_id}
