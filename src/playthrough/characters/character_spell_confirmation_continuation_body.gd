## Carries one generated character's remaining starting-spell confirmation.

class_name CharacterSpellConfirmationContinuationBody
extends SessionContinuationBody

var character_id: String
var remaining: int


func wire_payload(kind: StringName) -> Dictionary:
	return {"kind": String(kind), "characterId": character_id, "remaining": remaining}
