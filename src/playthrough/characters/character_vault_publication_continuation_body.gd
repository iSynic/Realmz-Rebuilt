## Carries one newly admitted character's optional Character Files publication.

class_name CharacterVaultPublicationContinuationBody
extends SessionContinuationBody

var character_id: String


func wire_payload(kind: StringName) -> Dictionary:
	return {"kind": String(kind), "characterId": character_id}
