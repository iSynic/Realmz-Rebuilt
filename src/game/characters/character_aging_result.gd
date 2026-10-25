## Implements deterministic character aging result rules without presentation dependencies.

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


func update_body(character: CharacterState, race: RaceDefinition) -> AgeUpdateRequestBody:
	var result := AgeUpdateRequestBody.new()
	result.character_id = character.id
	result.character_name = character.name
	result.portrait_id = character.portrait_id
	result.combat_icon_id = character.combat_icon_id
	result.race_id = character.race_id
	result.race_name = race.name if race != null else character.race_id
	result.previous_age_days = previous_age_days
	result.age_days = age_days
	result.previous_age_group = previous_age_group
	result.age_group = age_group
	result.age_group_name = age_group_name(age_group)
	var age_range := race.age_range(age_group - 1) if race != null and age_group >= 1 and age_group <= 5 else Vector2i.ZERO
	result.age_minimum_years = age_range.x
	result.age_maximum_years = age_range.y
	result.transition = transition
	result.applied_age_group = applied_age_group
	if race != null and applied_age_group >= 1 and applied_age_group <= 5:
		for value: int in race.age_change(applied_age_group - 1): result.changes.append(transition * value)
	var direction_text := "grown into" if transition > 0 else "returned to"
	result.prompt = "%s has %s the %s age group." % [character.name, direction_text, result.age_group_name]
	result.presentation = &"classic-age-update"
	result.sound_id = 3002
	result.source = &"classic"
	return result


static func age_group_name(group: int) -> String:
	return AGE_GROUP_NAMES[group] if group >= 1 and group < AGE_GROUP_NAMES.size() else AGE_GROUP_NAMES[0]


static func sound_event_for_update(update: AgeUpdateRequestBody) -> DomainEvent:
	return DomainEvent.new(&"sound_requested", {"soundId": update.sound_id, "waitForCompletion": false, "source": "classic-age-update"})
