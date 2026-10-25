## Stores the saveable character-creation draft owned by the active game state.

class_name CharacterDraftState
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
		"generatedCharacter": null if generated_character == null else CharacterStateCodec.encode(generated_character),
	}


static func from_data(value: Variant) -> CharacterDraftState:
	if not value is Dictionary:
		return null
	for field: String in ["name", "gender", "raceId", "casteId", "portraitId", "combatIconId", "finalized"]:
		if not value.has(field):
			return null
	if not value["name"] is String or not value["raceId"] is String or not value["casteId"] is String or not value["portraitId"] is String or not value["combatIconId"] is String or not value["finalized"] is bool:
		return null
	var gender_value := _integer(value["gender"])
	if gender_value not in [1, 2]:
		return null
	var result := CharacterDraftState.new()
	result.name = value["name"]
	result.gender = gender_value
	result.starting_level = _integer(value.get("startingLevel", 1))
	if not CharacterRules.STARTING_LEVELS.has(result.starting_level):
		return null
	result.race_id = value["raceId"]
	result.caste_id = value["casteId"]
	result.portrait_id = value["portraitId"]
	result.combat_icon_id = value["combatIconId"]
	result.finalized = value["finalized"]
	if value.has("generatedCharacter") and value["generatedCharacter"] != null:
		result.generated_character = CharacterStateCodec.decode(value["generatedCharacter"])
		if result.generated_character == null:
			return null
	return result


static func _integer(value: Variant) -> int:
	if value is int: return value
	if value is float:
		var number: float = value
		if is_finite(number) and number == floorf(number) and absf(number) <= 9_007_199_254_740_991.0: return int(number)
	return -1
