## Carries a binary authored choice and its optional scenario identities.

class_name YesNoRequestBody
extends InteractionRequestBody

var prompt: String
var yes_id: int
var yes_label: String
var no_id: int
var no_label: String
var region_id: String
var has_prompt: bool
var has_ids: bool
var has_region_id: bool


func to_data() -> Dictionary:
	var data := {"yesLabel": yes_label, "noLabel": no_label}
	if has_prompt: data["prompt"] = prompt
	if has_ids:
		data["yesId"] = yes_id
		data["noId"] = no_id
	if has_region_id: data["regionId"] = region_id
	return data


func prompt_text() -> String:
	return prompt
