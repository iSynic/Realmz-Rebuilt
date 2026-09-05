## Carries one source-ordered character aging acknowledgement.

class_name AgeUpdateRequestBody
extends InteractionRequestBody

var character_id: String
var character_name: String
var portrait_id: String
var combat_icon_id: String
var race_id: String
var race_name: String
var previous_age_days: int
var age_days: int
var previous_age_group: int
var age_group: int
var age_group_name: String
var age_minimum_years: int
var age_maximum_years: int
var transition: int
var applied_age_group: int
var changes: Array[int] = []
var prompt: String
var presentation: StringName
var sound_id: int
var source: StringName


func to_data() -> Dictionary:
	return {"characterId": character_id, "characterName": character_name, "portraitId": portrait_id, "combatIconId": combat_icon_id, "raceId": race_id, "raceName": race_name, "previousAgeDays": previous_age_days, "ageDays": age_days, "previousAgeGroup": previous_age_group, "ageGroup": age_group, "ageGroupName": age_group_name, "ageMinimumYears": age_minimum_years, "ageMaximumYears": age_maximum_years, "transition": transition, "appliedAgeGroup": applied_age_group, "changes": changes.duplicate(), "prompt": prompt, "presentation": String(presentation), "soundId": sound_id, "source": String(source)}


func prompt_text() -> String:
	return prompt


func same_values(other: AgeUpdateRequestBody) -> bool:
	return other != null \
		and character_id == other.character_id and character_name == other.character_name \
		and portrait_id == other.portrait_id and combat_icon_id == other.combat_icon_id \
		and race_id == other.race_id and race_name == other.race_name \
		and previous_age_days == other.previous_age_days and age_days == other.age_days \
		and previous_age_group == other.previous_age_group and age_group == other.age_group \
		and age_group_name == other.age_group_name \
		and age_minimum_years == other.age_minimum_years and age_maximum_years == other.age_maximum_years \
		and transition == other.transition and applied_age_group == other.applied_age_group \
		and changes == other.changes and prompt == other.prompt and presentation == other.presentation \
		and sound_id == other.sound_id and source == other.source
