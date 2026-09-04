## Carries an indexed scenario or encounter choice.

class_name ChoiceRequestBody
extends InteractionRequestBody

var prompt: String
var options: Array[InteractionRequestValue.ChoiceOption] = []
var can_back_out: bool
var encounter_kind: StringName
var encounter_id: int
var has_can_back_out: bool
var has_encounter: bool


func to_data() -> Dictionary:
	var data := {"prompt": prompt, "options": options.map(func(value: InteractionRequestValue.ChoiceOption) -> Dictionary: return value.to_data())}
	if has_can_back_out: data["canBackOut"] = can_back_out
	if has_encounter:
		data["encounterKind"] = String(encounter_kind)
		data["encounterId"] = encounter_id
	return data


func prompt_text() -> String:
	return prompt
