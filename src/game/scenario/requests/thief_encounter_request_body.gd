## Carries the character and action choices for a Classic thief encounter.

class_name ThiefEncounterRequestBody
extends InteractionRequestBody

var encounter_id: int
var prompt: String
var sound_id: int
var characters: Array[InteractionRequestValue.ThiefCharacter] = []


func to_data() -> Dictionary:
	return {"encounterId": encounter_id, "prompt": prompt, "soundId": sound_id, "characters": characters.map(func(value: InteractionRequestValue.ThiefCharacter) -> Dictionary: return value.to_data())}


func prompt_text() -> String:
	return prompt
