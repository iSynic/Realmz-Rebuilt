## Carries one exact item-owned scenario program across its VM handoff.

class_name ItemXapContinuationBody
extends SessionContinuationBody

var character_id: String
var instance_id: String
var item_id: String
var program_id: String
var source_battle_id: String


func wire_payload(kind: StringName) -> Dictionary:
	return {"kind": String(kind), "characterId": character_id, "instanceId": instance_id, "itemId": item_id, "programId": program_id, "sourceBattleId": source_battle_id}
