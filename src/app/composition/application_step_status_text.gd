## Converts committed game events into the shell's short human-readable status.
class_name ApplicationStepStatusText
extends RefCounted


static func for_event(event: DomainEvent) -> String:
	match event.kind:
		&"character_draft_generated": return "Classic character roll ready for review"
		&"character_draft_spells_changed": return "%d starting-spell points remain" % event.payload.get("remaining", 0)
		&"character_spell_confirmation_requested": return "%d starting-spell points remain • confirm acceptance" % event.payload.get("remaining", 0)
		&"character_spell_confirmation_declined": return "Choose more starting spells or accept the remaining points"
		&"character_draft_cancelled": return "Character creation cancelled"
		&"character_finalized": return "Character added to party setup"
		&"character_vault_confirmation_requested": return "Character added • choose whether to publish a reusable vault revision"
		&"character_publication_declined": return "Character kept in this campaign party only"
		&"vault_character_imported": return "Vault character added to party setup"
		&"party_member_removed": return "Character removed from party setup"
		&"party_created": return "Party assembled • the adventure begins"
		&"character_age_changed": return "%s entered a new age group" % event.payload.get("characterName", "A party member")
		&"message_shown": return "Scenario text" if event.payload.has("classicClick") else event.payload.get("text", "Message")
		&"map_transitioned": return "Entered %s" % event.payload.get("targetMapId", "map")
		&"movement_blocked": return "Blocked • %s" % event.payload.get("reason", "unknown")
	return ""


static func for_interaction(request: InteractionRequest) -> String:
	var acknowledge := request.body as AcknowledgeRequestBody
	if request.kind == InteractionRequest.ACKNOWLEDGE and acknowledge != null and acknowledge.presentation == &"classic-textbox":
		return "Scenario text • continue when ready"
	var prompt := request.body.prompt_text()
	return prompt if not prompt.is_empty() else "Choose an option"
