class_name CharacterAgingResult
extends RefCounted

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


func event_payload(character: CharacterState) -> Dictionary:
	return {
		"characterId": character.id,
		"characterName": character.name,
		"previousAgeDays": previous_age_days,
		"ageDays": age_days,
		"previousAgeGroup": previous_age_group,
		"ageGroup": age_group,
		"transition": transition,
		"appliedAgeGroup": applied_age_group,
		"source": "classic",
	}
