## Carries a bounded multi-character selection such as held-over allies.

class_name SelectionRequestBody
extends InteractionRequestBody

var prompt: String
var maximum: int
var selected_ids: Array[String] = []
var required_ids: Array[String] = []
var candidates: Array[InteractionRequestValue.SelectionCandidate] = []


func to_data() -> Dictionary:
	return {"prompt": prompt, "maximum": maximum, "selectedIds": selected_ids.duplicate(), "requiredIds": required_ids.duplicate(), "candidates": candidates.map(func(value: InteractionRequestValue.SelectionCandidate) -> Dictionary: return value.to_data())}


func prompt_text() -> String:
	return prompt
