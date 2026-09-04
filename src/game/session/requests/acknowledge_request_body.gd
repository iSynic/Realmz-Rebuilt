## Carries a blocking acknowledgement and its optional presentation metadata.

class_name AcknowledgeRequestBody
extends InteractionRequestBody

var prompt: String
var message_id: int
var presentation: StringName
var journal_eligible: bool
var journal_recorded: bool
var sound_id: int
var player_map_id: String
var resource_type: String
var resource_id: int
var has_message_id: bool
var has_presentation: bool
var has_journal_state: bool
var has_sound_id: bool
var has_player_map_id: bool
var has_resource: bool


func to_data() -> Dictionary:
	var data := {"prompt": prompt}
	if has_message_id: data["messageId"] = message_id
	if has_presentation: data["presentation"] = String(presentation)
	if has_journal_state:
		data["journalEligible"] = journal_eligible
		data["journalRecorded"] = journal_recorded
	if has_sound_id: data["soundId"] = sound_id
	if has_player_map_id: data["playerMapId"] = player_map_id
	if has_resource:
		data["resourceType"] = resource_type
		data["resourceId"] = resource_id
	return data


func prompt_text() -> String:
	return prompt
