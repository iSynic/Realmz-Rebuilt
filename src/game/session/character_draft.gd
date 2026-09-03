class_name CharacterDraft
extends RefCounted

var name: String = ""
var gender: int = 1
var starting_level: int = 1
var race_id: String = ""
var caste_id: String = ""
var portrait_id: String = ""
var combat_icon_id: String = ""
var finalized: bool = false
var generated_character: CharacterState


func to_creation_spec() -> CharacterCreationSpec:
	return CharacterCreationSpec.new(name, race_id, caste_id, gender, portrait_id, combat_icon_id, starting_level)


func is_ready() -> bool:
	return not name.strip_edges().is_empty() and not race_id.is_empty() and not caste_id.is_empty()


func has_generated_character() -> bool:
	return generated_character != null


func to_data() -> Dictionary:
	return {
		"name": name,
		"gender": gender,
		"startingLevel": starting_level,
		"raceId": race_id,
		"casteId": caste_id,
		"portraitId": portrait_id,
		"combatIconId": combat_icon_id,
		"finalized": finalized,
		"generatedCharacter": null if generated_character == null else generated_character.to_data(),
	}


static func from_data(value: Variant) -> CharacterDraft:
	if not value is Dictionary:
		return null
	for field: String in ["name", "gender", "raceId", "casteId", "portraitId", "combatIconId", "finalized"]:
		if not value.has(field):
			return null
	if not value["name"] is String or not value["raceId"] is String or not value["casteId"] is String or not value["portraitId"] is String or not value["combatIconId"] is String or not value["finalized"] is bool:
		return null
	if not value["gender"] is int or int(value["gender"]) not in [1, 2]:
		return null
	var result := CharacterDraft.new()
	result.name = value["name"]
	result.gender = value["gender"]
	var starting_level_value: Variant = value.get("startingLevel", 1)
	if not starting_level_value is int:
		return null
	result.starting_level = starting_level_value
	if not CharacterRules.STARTING_LEVELS.has(result.starting_level):
		return null
	result.race_id = value["raceId"]
	result.caste_id = value["casteId"]
	result.portrait_id = value["portraitId"]
	result.combat_icon_id = value["combatIconId"]
	result.finalized = value["finalized"]
	if value.has("generatedCharacter") and value["generatedCharacter"] != null:
		result.generated_character = CharacterState.from_data(value["generatedCharacter"])
		if result.generated_character == null:
			return null
	return result
