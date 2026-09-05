## Carries one character's committed gains or pending spell choices.

class_name LevelUpRequestBody
extends InteractionRequestBody

var mode: StringName
var prompt: String
var character_id: String
var character_name: String
var level: int
var gains: InteractionRequestValue.LevelGains
var point_total: int
var spells: Array[InteractionRequestValue.SpellChoice] = []


func to_data() -> Dictionary:
	var data := {"mode": String(mode), "prompt": prompt, "characterId": character_id, "characterName": character_name}
	if mode == &"result":
		data["level"] = level
		data["gains"] = gains.to_data()
	else:
		data["pointTotal"] = point_total
		data["spells"] = spells.map(func(value: InteractionRequestValue.SpellChoice) -> Dictionary: return value.to_data())
	return data


func prompt_text() -> String:
	return prompt
