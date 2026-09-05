## Strictly decodes acknowledgement, yes/no, and age-update request bodies.
class_name InteractionDialogRequestDecoder
extends RefCounted


static func parse(request_kind: StringName, payload: Dictionary) -> InteractionRequestBody:
	match request_kind:
		&"acknowledge":
			return _acknowledgement_from_data(payload)
		&"yes_no":
			return _yes_no_from_data(payload)
		&"age_update":
			return _age_update_from_data(payload)
	return null


static func _acknowledgement_from_data(payload: Dictionary) -> AcknowledgeRequestBody:
	var allowed: Array = [
		"prompt", "messageId", "presentation", "journalEligible", "journalRecorded",
		"soundId", "playerMapId", "resourceType", "resourceId",
	]
	if not InteractionValueDecoderSupport.exact(payload, allowed, ["prompt"]):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["prompt"]):
		return null
	if not InteractionValueDecoderSupport.optional_ints(payload, ["messageId", "soundId", "resourceId"]):
		return null
	if not InteractionValueDecoderSupport.optional_strings(payload, ["presentation", "playerMapId", "resourceType"]):
		return null
	if not InteractionValueDecoderSupport.optional_bools(payload, ["journalEligible", "journalRecorded"]):
		return null
	if payload.has("journalEligible") != payload.has("journalRecorded"):
		return null
	if payload.has("resourceType") != payload.has("resourceId"):
		return null
	if payload.has("resourceType") and String(payload["resourceType"]).is_empty():
		return null
	var result := AcknowledgeRequestBody.new()
	result.prompt = payload["prompt"]
	result.message_id = int(payload.get("messageId", 0))
	result.presentation = StringName(payload.get("presentation", ""))
	result.journal_eligible = bool(payload.get("journalEligible", false))
	result.journal_recorded = bool(payload.get("journalRecorded", false))
	result.sound_id = int(payload.get("soundId", 0))
	result.player_map_id = String(payload.get("playerMapId", ""))
	result.resource_type = String(payload.get("resourceType", ""))
	result.resource_id = int(payload.get("resourceId", 0))
	result.has_message_id = payload.has("messageId")
	result.has_presentation = payload.has("presentation")
	result.has_journal_state = payload.has("journalEligible") or payload.has("journalRecorded")
	result.has_sound_id = payload.has("soundId")
	result.has_player_map_id = payload.has("playerMapId")
	result.has_resource = payload.has("resourceType")
	return result


static func _yes_no_from_data(payload: Dictionary) -> YesNoRequestBody:
	var allowed: Array = ["prompt", "yesId", "yesLabel", "noId", "noLabel", "regionId"]
	if not InteractionValueDecoderSupport.exact(payload, allowed, ["yesLabel", "noLabel"]):
		return null
	if not InteractionValueDecoderSupport.strings(payload, ["yesLabel", "noLabel"]):
		return null
	if not InteractionValueDecoderSupport.optional_strings(payload, ["prompt", "regionId"]):
		return null
	if not InteractionValueDecoderSupport.optional_ints(payload, ["yesId", "noId"]):
		return null
	if payload.has("yesId") != payload.has("noId"):
		return null
	var result := YesNoRequestBody.new()
	result.prompt = String(payload.get("prompt", ""))
	result.yes_id = int(payload.get("yesId", 0))
	result.yes_label = payload["yesLabel"]
	result.no_id = int(payload.get("noId", 0))
	result.no_label = payload["noLabel"]
	result.region_id = String(payload.get("regionId", ""))
	result.has_prompt = payload.has("prompt")
	result.has_ids = payload.has("yesId") or payload.has("noId")
	result.has_region_id = payload.has("regionId")
	return result


static func _age_update_from_data(payload: Dictionary) -> AgeUpdateRequestBody:
	var fields: Array = [
		"characterId", "characterName", "portraitId", "combatIconId", "raceId", "raceName",
		"previousAgeDays", "ageDays", "previousAgeGroup", "ageGroup", "ageGroupName",
		"ageMinimumYears", "ageMaximumYears", "transition", "appliedAgeGroup", "changes",
		"prompt", "presentation", "soundId", "source",
	]
	var string_fields: Array = [
		"characterId", "characterName", "portraitId", "combatIconId", "raceId", "raceName",
		"ageGroupName", "prompt", "presentation", "source",
	]
	var integer_fields: Array = [
		"previousAgeDays", "ageDays", "previousAgeGroup", "ageGroup", "ageMinimumYears",
		"ageMaximumYears", "transition", "appliedAgeGroup", "soundId",
	]
	if not InteractionValueDecoderSupport.exact(payload, fields, fields):
		return null
	if not InteractionValueDecoderSupport.strings(payload, string_fields):
		return null
	if not InteractionValueDecoderSupport.ints(payload, integer_fields) or not payload["changes"] is Array:
		return null
	var result := AgeUpdateRequestBody.new()
	result.character_id = payload["characterId"]
	result.character_name = payload["characterName"]
	result.portrait_id = payload["portraitId"]
	result.combat_icon_id = payload["combatIconId"]
	result.race_id = payload["raceId"]
	result.race_name = payload["raceName"]
	result.previous_age_days = payload["previousAgeDays"]
	result.age_days = payload["ageDays"]
	result.previous_age_group = payload["previousAgeGroup"]
	result.age_group = payload["ageGroup"]
	result.age_group_name = payload["ageGroupName"]
	result.age_minimum_years = payload["ageMinimumYears"]
	result.age_maximum_years = payload["ageMaximumYears"]
	result.transition = payload["transition"]
	result.applied_age_group = payload["appliedAgeGroup"]
	for change: Variant in payload["changes"]:
		if not InteractionValueDecoderSupport.whole(change):
			return null
		result.changes.append(int(change))
	result.prompt = payload["prompt"]
	result.presentation = StringName(payload["presentation"])
	result.sound_id = payload["soundId"]
	result.source = StringName(payload["source"])
	return result
