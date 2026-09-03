class_name CharacterAgingResult
extends RefCounted

const AGE_GROUP_NAMES: Array[String] = ["Unknown", "Youth", "Young", "Prime", "Adult", "Senior"]

var previous_age_days: int
var age_days: int
var previous_age_group: int
var age_group: int
var transition: int
var applied_age_group: int


func _init(before_days: int, after_days: int, before_group: int, after_group: int, direction: int = 0, change_group: int = 0) -> void:
	previous_age_days = before_days
	age_days = after_days
	previous_age_group = before_group
	age_group = after_group
	transition = direction
	applied_age_group = change_group


func changed_group() -> bool:
	return transition != 0


func event_payload(character: CharacterState, race: RaceDefinition) -> Dictionary:
	var applied_changes: Array[int] = []
	if race != null and applied_age_group >= 1 and applied_age_group <= 5:
		for value: int in race.age_change(applied_age_group - 1):
			applied_changes.append(transition * value)
	var age_range := race.age_range(age_group - 1) if race != null and age_group >= 1 and age_group <= 5 else Vector2i.ZERO
	var group_name := age_group_name(age_group)
	var direction_text := "grown into" if transition > 0 else "returned to"
	return {
		"characterId": character.id,
		"characterName": character.name,
		"portraitId": character.portrait_id,
		"combatIconId": character.combat_icon_id,
		"raceId": character.race_id,
		"raceName": race.name if race != null else character.race_id,
		"previousAgeDays": previous_age_days,
		"ageDays": age_days,
		"previousAgeGroup": previous_age_group,
		"ageGroup": age_group,
		"ageGroupName": group_name,
		"ageMinimumYears": age_range.x,
		"ageMaximumYears": age_range.y,
		"transition": transition,
		"appliedAgeGroup": applied_age_group,
		"changes": applied_changes,
		"prompt": "%s has %s the %s age group." % [character.name, direction_text, group_name],
		"presentation": "classic-age-update",
		"soundId": 3002,
		"source": "classic",
	}


static func age_group_name(group: int) -> String:
	return AGE_GROUP_NAMES[group] if group >= 1 and group < AGE_GROUP_NAMES.size() else AGE_GROUP_NAMES[0]


static func update_payloads(events: Array[DomainEvent]) -> Array[Dictionary]:
	var updates: Array[Dictionary] = []
	for event: DomainEvent in events:
		if event.kind == &"character_age_changed" and event.payload.get("presentation") == "classic-age-update":
			updates.append(event.payload.duplicate(true))
	return updates


static func update_bodies(events: Array[DomainEvent]) -> Array[InteractionRequest.AgeUpdateBody]:
	var updates: Array[InteractionRequest.AgeUpdateBody] = []
	for payload: Dictionary in update_payloads(events):
		var request := InteractionRequest.age_update("character-aging", payload)
		assert(request != null and request.body is InteractionRequest.AgeUpdateBody, "A committed character-age event must satisfy the typed interaction contract")
		updates.append(request.body as InteractionRequest.AgeUpdateBody)
	return updates


static func sound_event(payload: Dictionary) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": int(payload.get("soundId", 3002)), "waitForCompletion": false, "source": "classic-age-update"})


static func sound_event_for_update(update: InteractionRequest.AgeUpdateBody) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": update.sound_id, "waitForCompletion": false, "source": "classic-age-update"})
